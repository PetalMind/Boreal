import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @AppStorage("developerMode") private var developerMode = false
    var body: some View {
        ScrollView {
            SettingsCard(.Settings.developerSettingsTitle, subtitle: .Settings.developerSettingsSubtitle, symbol: "wrench.and.screwdriver.fill") {
                SettingsRow(.Settings.developerModeLabel) { Toggle("", isOn: $developerMode).labelsHidden() }
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
