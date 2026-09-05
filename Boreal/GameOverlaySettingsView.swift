import SwiftUI

struct GameOverlaySettingsView: View {
    @AppStorage("gameOverlayEnabled") private var isEnabled = true
    @AppStorage("gameOverlayDetailLevel") private var detailLevel = GameOverlayDetailLevel.standard.rawValue
    @AppStorage("gameOverlayPosition") private var position = "topRight"
    @AppStorage("gameOverlayRefreshInterval") private var refreshInterval = 1.0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard("Performance Overlay", subtitle: "Choose what Boreal shows over a running game.", symbol: "gauge.with.dots.needle.67percent") {
                    SettingsRow("Show overlay while a game is running") { Toggle("", isOn: $isEnabled).labelsHidden() }
                    Divider()
                    SettingsRow("Information level") {
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
                    SettingsRow("Screen position") {
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
                    SettingsRow("Refresh rate") {
                        Picker("", selection: $refreshInterval) {
                            Text("Every second").tag(1.0)
                            Text("Every 2 seconds").tag(2.0)
                            Text("Every 5 seconds").tag(5.0)
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                }
                SettingsCard("Shortcuts", subtitle: "Existing keyboard shortcuts for the overlay.", symbol: "command") {
                    SettingsRow("Show or hide") { Text("⌘⌥O").foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow("Cycle information level") { Text("⌘⌥I").foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isEnabled) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: detailLevel) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: position) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: refreshInterval) { GameOverlayController.shared.settingsChanged() }
    }
}
