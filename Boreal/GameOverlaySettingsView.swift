import SwiftUI

struct GameOverlaySettingsView: View {
    @AppStorage("gameOverlayEnabled") private var isEnabled = true
    @AppStorage("gameOverlayDetailLevel") private var detailLevel = GameOverlayDetailLevel.standard.rawValue
    @AppStorage("gameOverlayPosition") private var position = "topRight"
    @AppStorage("gameOverlayRefreshInterval") private var refreshInterval = 1.0

    var body: some View {
        Form {
            Section("In-game performance overlay") {
                Toggle("Show overlay while a game is running", isOn: $isEnabled)
                Picker("Information level", selection: $detailLevel) {
                    Text("Minimal").tag(GameOverlayDetailLevel.minimal.rawValue)
                    Text("Standard").tag(GameOverlayDetailLevel.standard.rawValue)
                    Text("Diagnostic").tag(GameOverlayDetailLevel.diagnostic.rawValue)
                }
                .pickerStyle(.segmented)
                Picker("Screen position", selection: $position) {
                    Text("Top left").tag("topLeft")
                    Text("Top right").tag("topRight")
                    Text("Bottom left").tag("bottomLeft")
                    Text("Bottom right").tag("bottomRight")
                }
                Picker("Refresh rate", selection: $refreshInterval) {
                    Text("Every second").tag(1.0)
                    Text("Every 2 seconds").tag(2.0)
                    Text("Every 5 seconds").tag(5.0)
                }
            }
            Section {
                Text("Hide or show the overlay with ⌘⌥O. Switch while playing with ⌘⌥I, or select Minimal, Standard and Diagnostic directly with ⌘⌥1, ⌘⌥2 and ⌘⌥3. Diagnostic view charts keep the latest 60 live samples. Values stay unavailable when macOS or the active runtime does not expose them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 350)
        .navigationTitle("Overlay")
        .onChange(of: isEnabled) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: detailLevel) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: position) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: refreshInterval) { GameOverlayController.shared.settingsChanged() }
    }
}
