import SwiftUI

struct GameOverlaySettingsView: View {
    @AppStorage("gameOverlayEnabled") private var isEnabled = true
    @AppStorage("gameOverlayDetailLevel") private var detailLevel = GameOverlayDetailLevel.standard.rawValue
    @AppStorage("gameOverlayPosition") private var position = "topRight"
    @AppStorage("gameOverlayRefreshInterval") private var refreshInterval = 0.25
    @AppStorage("gameOverlayMetrics") private var metricsRaw = OverlayMetric.defaultSerialized
    @AppStorage("gameOverlayRecordingEnabled") private var recordingEnabled = false
    @State private var latestSession: PerformanceSessionDocument?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(.Settings.performanceOverlayTitle, subtitle: .Settings.performanceOverlaySubtitle, symbol: "gauge.with.dots.needle.67percent") {
                    SettingsRow(.Settings.showOverlayLabel) { Toggle("", isOn: $isEnabled).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.informationLevelLabel) {
                        Picker("", selection: $detailLevel) {
                            Text("Minimal").tag(GameOverlayDetailLevel.minimal.rawValue)
                            Text("Standard").tag(GameOverlayDetailLevel.standard.rawValue)
                            Text("Diagnostic").tag(GameOverlayDetailLevel.diagnostic.rawValue)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                    Divider()
                    SettingsRow(.Settings.screenPositionLabel) {
                        Picker("", selection: $position) {
                            Text("Top left").tag("topLeft")
                            Text("Top right").tag("topRight")
                            Text("Bottom left").tag("bottomLeft")
                            Text("Bottom right").tag("bottomRight")
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                    Divider()
                    SettingsRow(.Settings.refreshRateLabel) {
                        Picker("", selection: $refreshInterval) {
                            Text("4 Hz").tag(0.25)
                            Text("2 Hz").tag(0.5)
                            Text("1 Hz").tag(1.0)
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                }
                SettingsCard("Overlay metrics", subtitle: "Choose which supported values are shown in the overlay.", symbol: "checklist") {
                    ForEach(Array(OverlayMetric.allCases.filter { $0 != .cpuTemperature }.enumerated()), id: \.element) { index, metric in
                        if index > 0 { Divider() }
                        Toggle(metric.displayName, isOn: metricBinding(metric))
                            .toggleStyle(.switch)
                    }
                }
                SettingsCard("Performance recording", subtitle: "Save a session summary and detailed telemetry for later comparison.", symbol: "record.circle") {
                    Toggle("Record while a game is running", isOn: $recordingEnabled)
                    Divider()
                    HStack {
                        Text("Sessions are saved in Application Support/Boreal/Performance Sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    HStack {
                        Button("Export latest JSON") { GameOverlayController.shared.exportLastPerformanceSession(format: "json") }
                        Button("Export latest CSV") { GameOverlayController.shared.exportLastPerformanceSession(format: "csv") }
                    }
                    .buttonStyle(.bordered)
                    Divider()
                    if let summary = latestSession?.summary {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Latest session: \(latestSession?.gameName ?? "—")")
                                .font(.headline)
                            summaryRow("Duration", duration(summary.durationSeconds))
                            summaryRow("Average FPS", fps(summary.averageFPS))
                            summaryRow("1% / 0.1% Low", "\(fps(summary.onePercentLowFPS)) / \(fps(summary.zeroPointOnePercentLowFPS))")
                            summaryRow("P95 / P99 frametime", "\(milliseconds(summary.p95FrameTimeMilliseconds)) / \(milliseconds(summary.p99FrameTimeMilliseconds))")
                            summaryRow("Peak game memory", bytes(summary.peakMemoryBytes))
                            summaryRow("Serious/Critical", duration(summary.seriousThermalDurationSeconds))
                        }
                        .font(.system(.body, design: .monospaced))
                    } else {
                        Text("No saved performance session yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsCard(.Settings.shortcutsTitle, subtitle: .Settings.shortcutsSubtitle, symbol: "command") {
                    SettingsRow(.Settings.showOrHideLabel) { Text("⌘⌥O").foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow(.Settings.cycleInformationLevelLabel) { Text("⌘⌥I").foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isEnabled) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: detailLevel) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: position) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: refreshInterval) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: metricsRaw) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: recordingEnabled) {
            GameOverlayController.shared.settingsChanged()
            reloadSession()
        }
        .task { reloadSession() }
        .onAppear {
            if refreshInterval != 0.25 && refreshInterval != 0.5 && refreshInterval != 1.0 {
                refreshInterval = 0.25
            }
            if metricsRaw.isEmpty { metricsRaw = OverlayMetric.defaultSerialized }
        }
    }

    private func metricBinding(_ metric: OverlayMetric) -> Binding<Bool> {
        Binding(
            get: { OverlayMetric.deserialize(metricsRaw).contains(metric) },
            set: { enabled in
                var selected = OverlayMetric.deserialize(metricsRaw)
                if enabled { selected.insert(metric) } else { selected.remove(metric) }
                metricsRaw = OverlayMetric.serialize(selected)
            }
        )
    }

    private func reloadSession() {
        Task { latestSession = await GameOverlayController.shared.latestPerformanceSession() }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
    }

    private func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
    }

    private func fps(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
    private func milliseconds(_ value: Double?) -> String { value.map { String(format: "%.2f ms", $0) } ?? "—" }
    private func bytes(_ value: UInt64?) -> String { value.map { String(format: "%.1f GB", Double($0) / 1_073_741_824) } ?? "—" }
}
