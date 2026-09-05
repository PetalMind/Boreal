import AppKit
import Charts
import Observation
import SwiftUI

extension Notification.Name {
    static let borealNativeGameDidStart = Notification.Name("BorealNativeGameDidStart")
    static let borealNativeGameDidStop = Notification.Name("BorealNativeGameDidStop")
}

nonisolated struct OverlayGame: Hashable, Sendable {
    let id: UUID
    let name: String
    let launchedAt: Date
    let performanceLogURL: URL?
    let graphics: String
}

nonisolated enum GameOverlayDetailLevel: String, CaseIterable, Sendable {
    case minimal, standard, diagnostic
}

nonisolated enum MemoryPressureLevel: String, Sendable {
    case normal = "Normal", warning = "Warning", critical = "Critical"
}

nonisolated struct GamePerformanceSnapshot: Equatable, Sendable {
    var framesPerSecond: Double?
    var cpuUsage: Double?
    var gpuUsage: Double?
    var memoryUsedBytes: UInt64?
    var memoryTotalBytes: UInt64?
    var cpuTemperatureCelsius: Double?
    var gpuTemperatureCelsius: Double?
    var frameTimeMilliseconds: Double?
    var onePercentLowFPS: Double?
    var thermalState: String?
    var memoryPressure: MemoryPressureLevel?
    var swapUsedBytes: UInt64?
    var gpuAllocatedBytes: UInt64?

    var hasMemoryPressure: Bool { memoryPressure == .warning || memoryPressure == .critical }

    static let unavailable = GamePerformanceSnapshot()
}

nonisolated struct GamePerformanceSample: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let snapshot: GamePerformanceSnapshot
}

nonisolated struct GamePerformanceChartPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let value: Double
    let series: String
}

@MainActor @Observable
private final class GameOverlayViewModel {
    var snapshot = GamePerformanceSnapshot.unavailable
    var samples: [GamePerformanceSample] = []
    var detailLevel = GameOverlayDetailLevel.standard
    var gameName = "—"
    var sessionStartedAt: Date?
    var displayResolution = "—"
    var translationLayer = "—"
    var processorName = "Apple Silicon"
    private var sampledGameID: UUID?

    func prepare(for game: OverlayGame) {
        let isSameSession = sampledGameID == game.id && sessionStartedAt == game.launchedAt
        gameName = game.name
        sessionStartedAt = game.launchedAt
        guard !isSameSession else { return }
        sampledGameID = game.id
        snapshot = .unavailable
        samples.removeAll(keepingCapacity: true)
    }

    func record(_ snapshot: GamePerformanceSnapshot, at timestamp: Date = .now) {
        self.snapshot = snapshot
        samples.append(GamePerformanceSample(timestamp: timestamp, snapshot: snapshot))
        samples = Array(samples.suffix(60))
    }

    func chartPoints(
        for keyPath: KeyPath<GamePerformanceSnapshot, Double?>,
        series: String
    ) -> [GamePerformanceChartPoint] {
        var segment = 0
        return samples.compactMap { sample in
            guard let value = sample.snapshot[keyPath: keyPath] else {
                segment += 1
                return nil
            }
            return GamePerformanceChartPoint(
                id: sample.id,
                timestamp: sample.timestamp,
                value: value,
                series: "\(series)-\(segment)"
            )
        }
    }
}

@MainActor
final class GameOverlayController {
    static let shared = GameOverlayController()
    private let model = GameOverlayViewModel()
    private let sampler = GameMetricsSampler()
    private var panel: NSPanel?
    private var samplingTask: Task<Void, Never>?
    private var activeGames: [OverlayGame] = []
    private var managedGames: [OverlayGame] = []
    private var nativeGame: OverlayGame?
    private var expectedNativeGame: (id: UUID, name: String, installationURL: URL)?
    private var nativeGameProcessID: pid_t?
    private var isTemporarilyHidden = false
    private var preferredGameScreen: NSScreen?
    private var gameUsesFullScreenFrame = false
    private var activeSpaceObserver: NSObjectProtocol?
    private var applicationActivationObserver: NSObjectProtocol?
    private var applicationLaunchObserver: NSObjectProtocol?
    private var applicationTerminationObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var visibilityRefreshTasks: [Task<Void, Never>] = []

    private init() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.restoreOverlayVisibility(preferPointerScreen: true) } }
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.updatePreferredGameScreen(for: application)
                self?.scheduleFullscreenVisibilityRefresh()
            }
        }
        applicationLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.nativeApplicationLaunched(notification) }
        }
        applicationTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.nativeApplicationTerminated(notification) }
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleFullscreenVisibilityRefresh() } }
    }

    func synchronize(games: [OverlayGame]) {
        managedGames = games
        activeGames = (games + [nativeGame].compactMap { $0 }).sorted { $0.launchedAt > $1.launchedAt }
        if activeGames.isEmpty {
            isTemporarilyHidden = false
            preferredGameScreen = nil
            gameUsesFullScreenFrame = false
        }
        guard UserDefaults.standard.object(forKey: "gameOverlayEnabled") as? Bool ?? true,
              let game = activeGames.first, !isTemporarilyHidden else { hide(); return }
        model.prepare(for: game)
        model.detailLevel = configuredDetailLevel
        model.translationLayer = game.graphics
        model.processorName = Self.processorName
        show()
    }

    func expectNativeGame(name: String, installationURL: URL) {
        let expectation = (id: UUID(), name: name, installationURL: installationURL.standardizedFileURL)
        expectedNativeGame = expectation
        if let application = NSWorkspace.shared.runningApplications.first(where: { matches($0, installationURL: expectation.installationURL) }) {
            activateNativeGame(expectation, application: application)
        }
    }

    func settingsChanged() { synchronize(games: activeGames); if let panel { position(panel) } }
    func setDetailLevel(_ level: GameOverlayDetailLevel) {
        UserDefaults.standard.set(level.rawValue, forKey: "gameOverlayDetailLevel")
        settingsChanged()
    }

    func cycleDetailLevel() {
        let next: GameOverlayDetailLevel = switch configuredDetailLevel {
        case .minimal: .standard
        case .standard: .diagnostic
        case .diagnostic: .minimal
        }
        setDetailLevel(next)
    }

    func toggleVisibility() {
        guard !activeGames.isEmpty else { return }
        isTemporarilyHidden.toggle(); synchronize(games: activeGames)
    }

    private func show() {
        let panel = panel ?? makePanel(); self.panel = panel
        panel.contentView = NSHostingView(rootView: GameOverlayView(model: model))
        position(panel); panel.orderFrontRegardless(); startSampling()
    }

    private func hide() {
        samplingTask?.cancel(); samplingTask = nil; panel?.orderOut(nil); model.snapshot = .unavailable
    }

    private func nativeApplicationLaunched(_ notification: Notification) {
        guard let expectation = expectedNativeGame,
              let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              matches(application, installationURL: expectation.installationURL) else { return }
        activateNativeGame(expectation, application: application)
    }

    private func nativeApplicationTerminated(_ notification: Notification) {
        guard let processID = nativeGameProcessID,
              let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.processIdentifier == processID else { return }
        nativeGame = nil
        nativeGameProcessID = nil
        synchronize(games: managedGames)
        NotificationCenter.default.post(name: .borealNativeGameDidStop, object: nil)
    }

    private func activateNativeGame(
        _ expectation: (id: UUID, name: String, installationURL: URL),
        application: NSRunningApplication
    ) {
        nativeGameProcessID = application.processIdentifier
        nativeGame = OverlayGame(
            id: expectation.id,
            name: expectation.name,
            launchedAt: .now,
            performanceLogURL: nil,
            graphics: "Native macOS"
        )
        expectedNativeGame = nil
        updatePreferredGameScreen(for: application)
        synchronize(games: managedGames)
        NotificationCenter.default.post(name: .borealNativeGameDidStart, object: nil)
        scheduleFullscreenVisibilityRefresh()
    }

    private func matches(_ application: NSRunningApplication, installationURL: URL) -> Bool {
        guard let bundleURL = application.bundleURL?.standardizedFileURL else { return false }
        if installationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            return bundleURL == installationURL
        }
        return bundleURL.path == installationURL.path || bundleURL.path.hasPrefix(installationURL.path + "/")
    }

    private func restoreOverlayVisibility(preferPointerScreen: Bool = false) {
        guard !activeGames.isEmpty, !isTemporarilyHidden,
              UserDefaults.standard.object(forKey: "gameOverlayEnabled") as? Bool ?? true,
              let panel else { return }
        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier != Bundle.main.bundleIdentifier {
            updatePreferredGameScreen(for: application)
        }
        position(panel, preferPointerScreen: preferPointerScreen)
        panel.orderFrontRegardless()
    }

    private func scheduleFullscreenVisibilityRefresh() {
        visibilityRefreshTasks.forEach { $0.cancel() }
        visibilityRefreshTasks = [0.0, 0.2, 0.6, 1.2, 2.5, 4.0].map { delay in
            Task { [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                self?.restoreOverlayVisibility(preferPointerScreen: true)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 286, height: 286),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.sharingType = .none
        panel.canBecomeVisibleWithoutLogin = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.setAccessibilityLabel("Boreal game performance overlay")
        return panel
    }

    private func position(_ panel: NSPanel, preferPointerScreen: Bool = false) {
        let size: NSSize = switch configuredDetailLevel {
        case .minimal: .init(width: 248, height: 250)
        case .standard: .init(width: 300, height: 520)
        case .diagnostic: .init(width: 520, height: 850)
        }
        panel.setContentSize(size)
        let pointer = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard let screen = preferredGameScreen
                ?? (preferPointerScreen ? pointer : nil)
                ?? NSScreen.main
                ?? pointer
                ?? NSScreen.screens.first else { return }
        model.displayResolution = "\(Int(screen.frame.width * screen.backingScaleFactor))×\(Int(screen.frame.height * screen.backingScaleFactor))"
        let frame = gameUsesFullScreenFrame ? screen.frame : screen.visibleFrame
        let margin: CGFloat = 18
        let origin: NSPoint = switch UserDefaults.standard.string(forKey: "gameOverlayPosition") ?? "topRight" {
        case "topLeft": .init(x: frame.minX + margin, y: frame.maxY - size.height - margin)
        case "bottomLeft": .init(x: frame.minX + margin, y: frame.minY + margin)
        case "bottomRight": .init(x: frame.maxX - size.width - margin, y: frame.minY + margin)
        default: .init(x: frame.maxX - size.width - margin, y: frame.maxY - size.height - margin)
        }
        panel.setFrameOrigin(origin)
    }

    /// Finds the display occupied by the active game's largest application window.
    /// Quartz window bounds and display bounds use the same top-left coordinate
    /// system. Wine can place a fullscreen game above layer 0 (Darksiders II uses
    /// layer 21), so accept application layers below the system shielding level.
    private func updatePreferredGameScreen(for application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        let candidates = windows.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == application.processIdentifier,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer >= 0,
                  layer < Int(CGShieldingWindowLevel()),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 320, rect.height >= 240 else { return nil }
            return rect
        }
        guard let gameWindow = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return }

        let displayIDs = NSScreen.screens.compactMap { screen -> (NSScreen, CGDirectDisplayID)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (screen, CGDirectDisplayID(number.uint32Value))
        }
        guard let match = displayIDs.max(by: {
            intersectionArea(gameWindow, CGDisplayBounds($0.1)) < intersectionArea(gameWindow, CGDisplayBounds($1.1))
        }), intersectionArea(gameWindow, CGDisplayBounds(match.1)) > 0 else { return }

        preferredGameScreen = match.0
        let displayBounds = CGDisplayBounds(match.1)
        let coverage = intersectionArea(gameWindow, displayBounds) / max(1, displayBounds.width * displayBounds.height)
        gameUsesFullScreenFrame = coverage >= 0.90
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private var configuredDetailLevel: GameOverlayDetailLevel {
        if let raw = UserDefaults.standard.string(forKey: "gameOverlayDetailLevel"), let value = GameOverlayDetailLevel(rawValue: raw) { return value }
        return UserDefaults.standard.bool(forKey: "gameOverlayCompact") ? .minimal : .standard
    }

    private static let processorName = hardwareString("machdep.cpu.brand_string") ?? hardwareString("hw.model") ?? "Apple Silicon"
    private static func hardwareString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }

    private func startSampling() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await sampler.sample(
                    frameRateLogURL: activeGames.first?.performanceLogURL,
                    gameID: activeGames.first?.id
                )
                model.record(snapshot)
                restoreOverlayVisibility()
                try? await Task.sleep(for: .seconds(max(UserDefaults.standard.double(forKey: "gameOverlayRefreshInterval"), 0.5)))
            }
        }
    }
}

private struct GameOverlayView: View {
    let model: GameOverlayViewModel
    var body: some View {
        switch model.detailLevel {
        case .minimal:
            VStack(spacing: 8) { sessionInfo; performance; memoryWarning; hideShortcut }
                .padding(16)
                .card()
        case .standard: standard
        case .diagnostic: diagnostic
        }
    }

    private func bytes(_ value: UInt64?) -> String {
        value.map { String(format: "%.1f GB", Double($0) / 1_073_741_824) } ?? "—"
    }

    @ViewBuilder private var memoryWarning: some View {
        if model.snapshot.hasMemoryPressure {
            VStack(alignment: .leading, spacing: 4) {
                Label("Memory pressure detected", systemImage: "exclamationmark.triangle.fill")
                Text("Close memory-heavy applications")
            }
            .font(.caption)
            .foregroundStyle(model.snapshot.memoryPressure == .critical ? .red : .orange)
            .accessibilityElement(children: .combine)
        }
    }

    private var standard: some View {
        VStack(spacing: 12) {
            sessionInfo; divider; performance; divider
            row("GPU", percent(model.snapshot.gpuUsage), .green)
            row("CPU", percent(model.snapshot.cpuUsage), .cyan)
            row("Memory", "\(memory) / \(totalMemory)", .green)
            row("Swap", bytes(model.snapshot.swapUsedBytes), .purple)
            row("GPU mapped", bytes(model.snapshot.gpuAllocatedBytes), .purple)
            row("Pressure", model.snapshot.memoryPressure?.rawValue ?? "—", .orange)
            memoryWarning
            divider; info("display", model.displayResolution); info("square.3.layers.3d", "Metal")
            divider; hideShortcut
        }.padding(16).card()
    }

    private var diagnostic: some View {
        VStack(spacing: 14) {
            sessionInfo; divider
            title("chart.xyaxis.line", "PERFORMANCE", .cyan); performance; divider
            HStack(alignment: .top, spacing: 16) {
                column("GPU", "display", .green, [("GPU", percent(model.snapshot.gpuUsage)), ("Temperature", temperature(model.snapshot.gpuTemperatureCelsius))])
                divider
                column("CPU", "cpu", .cyan, [("CPU", percent(model.snapshot.cpuUsage)), ("Temperature", temperature(model.snapshot.cpuTemperatureCelsius))])
            }
            divider
            HStack(alignment: .top, spacing: 16) {
                column("MEMORY", "memorychip", .purple, [("Memory", memory), ("Total", totalMemory), ("Swap", bytes(model.snapshot.swapUsedBytes)), ("GPU mapped", bytes(model.snapshot.gpuAllocatedBytes)), ("Pressure", model.snapshot.memoryPressure?.rawValue ?? "—")])
                divider
                column("THERMAL", "thermometer.medium", .orange, [("State", model.snapshot.thermalState ?? "—")])
            }
            divider
            memoryWarning
            title("waveform.path.ecg", "LIVE HISTORY", .cyan)
            liveChart(
                title: "FPS",
                color: .green,
                points: model.chartPoints(for: \.framesPerSecond, series: "FPS"),
                domain: nil
            )
            liveUtilizationChart
            divider; title("gearshape", "SYSTEM", .cyan)
            info("display", model.displayResolution); info("square.3.layers.3d", "API", "Metal")
            info("arrow.left.arrow.right", "Translation", model.translationLayer); info("apple.logo", model.processorName)
            divider; hideShortcut
        }.padding(16).card()
    }

    private var liveUtilizationChart: some View {
        let cpu = model.chartPoints(for: \.cpuUsage, series: "CPU")
        let gpu = model.chartPoints(for: \.gpuUsage, series: "GPU")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                chartLegend("CPU", color: .cyan)
                chartLegend("GPU", color: .green)
            }
            Chart {
                ForEach(cpu) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("CPU", point.value),
                        series: .value("CPU segment", point.series)
                    )
                    .foregroundStyle(.cyan)
                    .lineStyle(.init(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(gpu) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("GPU", point.value),
                        series: .value("GPU segment", point.series)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(.init(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXScale(domain: chartTimeDomain)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis { compactYAxis(suffix: "%") }
            .chartLegend(.hidden)
            .frame(height: 72)
        }
    }

    private func liveChart(
        title: String,
        color: Color,
        points: [GamePerformanceChartPoint],
        domain: ClosedRange<Double>?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            chartLegend(title, color: color)
            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value(title, point.value),
                    series: .value("Segment", point.series)
                )
                .foregroundStyle(color)
                .lineStyle(.init(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: chartTimeDomain)
            .chartYScale(domain: domain ?? automaticFPSDomain(points))
            .chartXAxis(.hidden)
            .chartYAxis { compactYAxis(suffix: "") }
            .chartLegend(.hidden)
            .frame(height: 72)
        }
    }

    private var chartTimeDomain: ClosedRange<Date> {
        let end = model.samples.last?.timestamp ?? .now
        let interval = max(UserDefaults.standard.double(forKey: "gameOverlayRefreshInterval"), 0.5)
        return end.addingTimeInterval(-interval * 59)...end
    }

    private func automaticFPSDomain(_ points: [GamePerformanceChartPoint]) -> ClosedRange<Double> {
        let maximum = points.map(\.value).max() ?? 60
        return 0...max(30, ceil(maximum / 30) * 30)
    }

    @AxisContentBuilder
    private func compactYAxis(suffix: String) -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(.white.opacity(0.12))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text("\(Int(number.rounded()))\(suffix)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chartLegend(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private var hideShortcut: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.slash")
            Text("Hide overlay")
            Spacer()
            Text("⌘⌥O")
                .foregroundStyle(.white)
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .accessibilityLabel("Hide overlay with Command Option O")
    }

    private var performance: some View {
        VStack(spacing: 8) {
            row("FPS", number(model.snapshot.framesPerSecond), .green)
            row("Frametime", milliseconds(model.snapshot.frameTimeMilliseconds), .green)
            row("1% Low", fps(model.snapshot.onePercentLowFPS), .green)
        }
    }
    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.cyan)
                Text(model.gameName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            }
            .font(.system(size: 14, weight: .semibold, design: .monospaced))

            HStack(spacing: 7) {
                Image(systemName: "clock")
                    .frame(width: 16)
                    .foregroundStyle(.orange)
                Text("Session")
                Spacer()
                Text(sessionDuration)
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Game \(model.gameName), session duration \(sessionDuration)")
    }
    private var sessionDuration: String {
        guard let startedAt = model.sessionStartedAt else { return "—" }
        let elapsed = max(0, Int(Date.now.timeIntervalSince(startedAt)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
    private var divider: some View { Divider().overlay(.white.opacity(0.16)) }
    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(value == "—" ? Color.secondary : color).contentTransition(.numericText()) }
            .font(.system(size: 15, weight: .medium, design: .monospaced))
    }
    private func title(_ symbol: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func column(_ text: String, _ symbol: String, _ color: Color, _ rows: [(String, String)]) -> some View {
        VStack(spacing: 8) { title(symbol, text, color); ForEach(Array(rows.enumerated()), id: \.offset) { _, item in row(item.0, item.1, color) } }.frame(maxWidth: .infinity)
    }
    private func info(_ symbol: String, _ text: String, _ trailing: String? = nil) -> some View {
        HStack { Image(systemName: symbol).frame(width: 20); Text(text); Spacer(); if let trailing { Text(trailing) } }.font(.system(size: 14, weight: .medium, design: .monospaced))
    }
    private func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "—" }
    private func number(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))" } ?? "—" }
    private func temperature(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))°C" } ?? "—" }
    private func milliseconds(_ value: Double?) -> String { value.map { String(format: "%.1f ms", $0) } ?? "—" }
    private func fps(_ value: Double?) -> String {
        value.map { $0 < 10 ? String(format: "%.1f FPS", $0) : "\(Int($0.rounded())) FPS" } ?? "—"
    }
    private var memory: String { model.snapshot.memoryUsedBytes.map { String(format: "%.1f GB", Double($0) / 1_073_741_824) } ?? "—" }
    private var totalMemory: String { model.snapshot.memoryTotalBytes.map { String(format: "%.0f GB", Double($0) / 1_073_741_824) } ?? "—" }
}

private extension View {
    func card() -> some View {
        foregroundStyle(.white).background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.25)))
    }
}
