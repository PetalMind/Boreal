import SwiftUI

struct GameOverlaySettingsView: View {
    @AppStorage("gameOverlayEnabled") private var isEnabled = true
    @AppStorage("gameOverlayDetailLevel") private var detailLevel = GameOverlayDetailLevel.standard.rawValue
    @AppStorage("gameOverlayPosition") private var position = "topRight"
    @AppStorage("gameOverlayRefreshInterval") private var refreshInterval = 1.0

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
                            Text("Every second").tag(1.0)
                            Text("Every 2 seconds").tag(2.0)
                            Text("Every 5 seconds").tag(5.0)
                        }
                        .labelsHidden()
                        .frame(width: 260)
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
    }
}
