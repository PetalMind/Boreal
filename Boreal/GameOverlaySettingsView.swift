import SwiftUI

struct GameOverlaySettingsView: View {
    @AppStorage("gameOverlayEnabled") private var isEnabled = true
    @AppStorage("gameOverlayCompact") private var isCompact = false
    @AppStorage("gameOverlayPosition") private var position = "topRight"
    @AppStorage("gameOverlayRefreshInterval") private var refreshInterval = 1.0

    var body: some View {
        Form {
            Section("In-game performance overlay") {
                Toggle("Show overlay while a game is running", isOn: $isEnabled)
                Toggle("Compact layout", isOn: $isCompact)
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
                Text("CPU, memory and supported GPU sensors are read locally. FPS and temperature stay unavailable when the active runtime or Mac does not expose them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 350)
        .navigationTitle("Overlay")
        .onChange(of: isEnabled) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: isCompact) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: position) { GameOverlayController.shared.settingsChanged() }
        .onChange(of: refreshInterval) { GameOverlayController.shared.settingsChanged() }
    }
}
