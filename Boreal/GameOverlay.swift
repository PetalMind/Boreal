import AppKit
import Observation
import SwiftUI

nonisolated struct OverlayGame: Hashable, Sendable {
    let id: UUID
    let name: String
    let launchedAt: Date
    let performanceLogURL: URL?
}

nonisolated struct GamePerformanceSnapshot: Equatable, Sendable {
    var framesPerSecond: Double?
    var cpuUsage: Double?
    var gpuUsage: Double?
    var memoryUsedBytes: UInt64?
    var memoryTotalBytes: UInt64?
    var cpuTemperatureCelsius: Double?
    var gpuTemperatureCelsius: Double?

    static let unavailable = GamePerformanceSnapshot()
}

@MainActor
@Observable
private final class GameOverlayViewModel {
    var gameName = "Game"
    var snapshot = GamePerformanceSnapshot.unavailable
    var isCompact = false
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

    private init() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.activeSpaceDidChange() }
        }
    }

    func synchronize(games: [OverlayGame]) {
        activeGames = games.sorted { $0.launchedAt > $1.launchedAt }
        if activeGames.isEmpty { isTemporarilyHidden = false }
        guard UserDefaults.standard.object(forKey: "gameOverlayEnabled") as? Bool ?? true,
              !activeGames.isEmpty,
              !isTemporarilyHidden else {
            hide()
            return
        }

        model.gameName = activeGames[0].name
        model.isCompact = UserDefaults.standard.bool(forKey: "gameOverlayCompact")
        show()
    }

    func settingsChanged() {
        synchronize(games: activeGames)
        if let panel { position(panel) }
    }

    func toggleVisibility() {
        guard !activeGames.isEmpty else { return }
        isTemporarilyHidden.toggle()
        synchronize(games: activeGames)
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: GameOverlayView(model: model))
        position(panel)
        panel.orderFrontRegardless()
        startSampling()
    }

    private func hide() {
        samplingTask?.cancel()
        samplingTask = nil
        panel?.orderOut(nil)
        model.snapshot = .unavailable
    }

    private func activeSpaceDidChange() {
        guard !activeGames.isEmpty,
              !isTemporarilyHidden,
              UserDefaults.standard.object(forKey: "gameOverlayEnabled") as? Bool ?? true,
              let panel else { return }
        position(panel, preferPointerScreen: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.setAccessibilityLabel("Boreal game performance overlay")
        return panel
    }

    private func position(_ panel: NSPanel, preferPointerScreen: Bool = false) {
        let compact = UserDefaults.standard.bool(forKey: "gameOverlayCompact")
        let size = compact ? NSSize(width: 280, height: 58) : NSSize(width: 388, height: 108)
        panel.setContentSize(size)
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard let screen = (preferPointerScreen ? pointerScreen : nil) ?? NSScreen.main ?? pointerScreen ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let margin: CGFloat = 18
        let position = UserDefaults.standard.string(forKey: "gameOverlayPosition") ?? "topRight"
        let origin: NSPoint
        switch position {
        case "topLeft": origin = NSPoint(x: frame.minX + margin, y: frame.maxY - size.height - margin)
        case "bottomLeft": origin = NSPoint(x: frame.minX + margin, y: frame.minY + margin)
        case "bottomRight": origin = NSPoint(x: frame.maxX - size.width - margin, y: frame.minY + margin)
        default: origin = NSPoint(x: frame.maxX - size.width - margin, y: frame.maxY - size.height - margin)
        }
        panel.setFrameOrigin(origin)
    }

    private func startSampling() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                model.snapshot = await sampler.sample(frameRateLogURL: activeGames.first?.performanceLogURL)
                let interval = max(UserDefaults.standard.double(forKey: "gameOverlayRefreshInterval"), 0.5)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}

private struct GameOverlayView: View {
    let model: GameOverlayViewModel

    var body: some View {
        if model.isCompact {
            compactBody
        } else {
            fullBody
        }
    }

    private var compactBody: some View {
        HStack(spacing: 12) {
            Label(model.gameName, systemImage: "gamecontroller.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            compactMetric("FPS", value: number(model.snapshot.framesPerSecond))
            compactMetric("CPU", value: percent(model.snapshot.cpuUsage))
            compactMetric("GPU", value: percent(model.snapshot.gpuUsage))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.16)))
    }

    private var fullBody: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill").foregroundStyle(.cyan)
                Text(model.gameName).font(.system(.caption, design: .rounded, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("LIVE").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                metric("FPS", number(model.snapshot.framesPerSecond), "rectangle.stack.badge.play")
                metric("CPU", percent(model.snapshot.cpuUsage), "cpu")
                metric("GPU", percent(model.snapshot.gpuUsage), "display")
                metric("RAM", memory(model.snapshot), "memorychip")
                metric("CPU °C", temperature(model.snapshot.cpuTemperatureCelsius), "thermometer.medium")
                metric("GPU °C", temperature(model.snapshot.gpuTemperatureCelsius), "thermometer.medium")
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.16)))
    }

    private func compactMetric(_ label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(.caption, design: .monospaced, weight: .bold))
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Label(label, systemImage: symbol)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "—" }
    private func number(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))" } ?? "—" }
    private func temperature(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))°" } ?? "—" }
    private func memory(_ snapshot: GamePerformanceSnapshot) -> String {
        guard let used = snapshot.memoryUsedBytes else { return "—" }
        return String(format: "%.1fG", Double(used) / 1_073_741_824)
    }
}
