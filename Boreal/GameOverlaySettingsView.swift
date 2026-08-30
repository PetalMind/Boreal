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
                    Text("Minimal — essential frame data").tag(GameOverlayDetailLevel.minimal.rawValue)
                    Text("Standard — everyday overview").tag(GameOverlayDetailLevel.standard.rawValue)
                    Text("Diagnostic — system details").tag(GameOverlayDetailLevel.diagnostic.rawValue)
                }
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
                Text("Minimal shows frame data, Standard adds system load, and Diagnostic adds sensors and runtime details. Values stay unavailable when macOS or the active runtime does not expose them.")
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
