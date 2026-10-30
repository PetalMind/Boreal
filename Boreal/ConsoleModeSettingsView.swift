import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConsoleModeSettingsView: View {
    @AppStorage("consoleModeEnabled") private var consoleModeEnabled = false
    @AppStorage("consoleModeAutoEnter") private var consoleModeAutoEnter = true
    @AppStorage("consoleModeReturnAfterGame") private var returnAfterGame = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(.Settings.controllerFirstTitle, subtitle: .Settings.controllerFirstSubtitle, symbol: "rectangle.inset.filled") {
                    SettingsRow(.Settings.consoleModeLabel) { Toggle("", isOn: $consoleModeEnabled).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.consoleModeAutoEnterLabel) { Toggle("", isOn: $consoleModeAutoEnter).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.consoleModeReturnLabel) { Toggle("", isOn: $returnAfterGame).labelsHidden() }
                }
                SettingsCard(.Settings.controlsTitle, subtitle: .Settings.controlsSubtitle, symbol: "gamecontroller.fill") {
                    SettingsRow(.Settings.navigateLabel) { Text(.Settings.dPadLeftStick).foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow(.Settings.selectBackLabel) { Text(.Settings.aB).foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow(.Settings.gameMenuLabel) { Text(.Settings.yButton).foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
