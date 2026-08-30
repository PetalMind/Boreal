import AppKit
import Observation
import SwiftUI

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

    static let unavailable = GamePerformanceSnapshot()
}

@MainActor @Observable
private final class GameOverlayViewModel {
    var snapshot = GamePerformanceSnapshot.unavailable
    var detailLevel = GameOverlayDetailLevel.standard
    var displayResolution = "—"
    var translationLayer = "—"
    var processorName = "Apple Silicon"
}

@MainActor
final class GameOverlayController {
    static let shared = GameOverlayController()
    private let model = GameOverlayViewModel()
    private let sampler = GameMetricsSampler()
    private var panel: NSPanel?
    private var samplingTask: Task<Void, Never>?
    private var activeGames: [OverlayGame] = []
    private var isTemporarilyHidden = false
    private var activeSpaceObserver: NSObjectProtocol?
    private var applicationActivationObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var visibilityRefreshTasks: [Task<Void, Never>] = []

    private init() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.restoreOverlayVisibility(preferPointerScreen: true) } }
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleFullscreenVisibilityRefresh() } }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleFullscreenVisibilityRefresh() } }
    }

    func synchronize(games: [OverlayGame]) {
        activeGames = games.sorted { $0.launchedAt > $1.launchedAt }
        if activeGames.isEmpty { isTemporarilyHidden = false }
        guard UserDefaults.standard.object(forKey: "gameOverlayEnabled") as? Bool ?? true,
              let game = activeGames.first, !isTemporarilyHidden else { hide(); return }
        model.detailLevel = configuredDetailLevel
        model.translationLayer = game.graphics
        model.processorName = Self.processorName
        show()
    }

    func settingsChanged() { synchronize(games: activeGames); if let panel { position(panel) } }
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

    private func restoreOverlayVisibility(preferPointerScreen: Bool = false) {
        guard !activeGames.isEmpty, !isTemporarilyHidden,
              UserDefaults.standard.object(forKey: "gameOverlayEnabled") as? Bool ?? true,
              let panel else { return }
        position(panel, preferPointerScreen: preferPointerScreen)
        panel.orderFrontRegardless()
    }

    private func scheduleFullscreenVisibilityRefresh() {
        visibilityRefreshTasks.forEach { $0.cancel() }
        visibilityRefreshTasks = [0.0, 0.25, 0.75, 1.5].map { delay in
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
        panel.canBecomeVisibleWithoutLogin = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.setAccessibilityLabel("Boreal game performance overlay")
        return panel
    }

    private func position(_ panel: NSPanel, preferPointerScreen: Bool = false) {
        let size: NSSize = switch configuredDetailLevel {
        case .minimal: .init(width: 228, height: 116)
        case .standard: .init(width: 286, height: 286)
        case .diagnostic: .init(width: 430, height: 474)
        }
        panel.setContentSize(size)
        let pointer = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard let screen = (preferPointerScreen ? pointer : nil) ?? NSScreen.main ?? pointer ?? NSScreen.screens.first else { return }
        model.displayResolution = "\(Int(screen.frame.width * screen.backingScaleFactor))×\(Int(screen.frame.height * screen.backingScaleFactor))"
        let frame = screen.visibleFrame, margin: CGFloat = 18
        let origin: NSPoint = switch UserDefaults.standard.string(forKey: "gameOverlayPosition") ?? "topRight" {
        case "topLeft": .init(x: frame.minX + margin, y: frame.maxY - size.height - margin)
        case "bottomLeft": .init(x: frame.minX + margin, y: frame.minY + margin)
        case "bottomRight": .init(x: frame.maxX - size.width - margin, y: frame.minY + margin)
        default: .init(x: frame.maxX - size.width - margin, y: frame.maxY - size.height - margin)
        }
        panel.setFrameOrigin(origin)
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
                model.snapshot = await sampler.sample(
                    frameRateLogURL: activeGames.first?.performanceLogURL,
                    gameID: activeGames.first?.id
                )
                try? await Task.sleep(for: .seconds(max(UserDefaults.standard.double(forKey: "gameOverlayRefreshInterval"), 0.5)))
            }
        }
    }
}

private struct GameOverlayView: View {
    let model: GameOverlayViewModel
    var body: some View {
        switch model.detailLevel {
        case .minimal: performance.padding(16).card()
        case .standard: standard
        case .diagnostic: diagnostic
        }
    }

    private var standard: some View {
        VStack(spacing: 12) {
            performance; divider
            row("GPU", percent(model.snapshot.gpuUsage), .green)
            row("CPU", percent(model.snapshot.cpuUsage), .cyan)
            row("Memory", memory, .green)
            divider; info("display", model.displayResolution); info("square.3.layers.3d", "Metal")
        }.padding(16).card()
    }

    private var diagnostic: some View {
        VStack(spacing: 14) {
            title("chart.xyaxis.line", "PERFORMANCE", .cyan); performance; divider
            HStack(alignment: .top, spacing: 16) {
                column("GPU", "display", .green, [("GPU", percent(model.snapshot.gpuUsage)), ("Temperature", temperature(model.snapshot.gpuTemperatureCelsius))])
                divider
                column("CPU", "cpu", .cyan, [("CPU", percent(model.snapshot.cpuUsage)), ("Temperature", temperature(model.snapshot.cpuTemperatureCelsius))])
            }
            divider
            HStack(alignment: .top, spacing: 16) {
                column("MEMORY", "memorychip", .purple, [("Memory", memory), ("Total", totalMemory)])
                divider
                column("THERMAL", "thermometer.medium", .orange, [("State", model.snapshot.thermalState ?? "—")])
            }
            divider; title("gearshape", "SYSTEM", .cyan)
            info("display", model.displayResolution); info("square.3.layers.3d", "API", "Metal")
            info("arrow.left.arrow.right", "Translation", model.translationLayer); info("apple.logo", model.processorName)
        }.padding(16).card()
    }

    private var performance: some View {
        VStack(spacing: 8) {
            row("FPS", number(model.snapshot.framesPerSecond), .green)
            row("Frametime", milliseconds(model.snapshot.frameTimeMilliseconds), .green)
            row("1% Low", fps(model.snapshot.onePercentLowFPS), .green)
        }
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
