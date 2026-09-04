import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("automaticUpdates") private var automaticUpdates = true
    @AppStorage("keepInstallers") private var keepInstallers = false

    var body: some View {
        Form {
            Section("Updates and installers") {
                Toggle("Check for updates automatically", isOn: $automaticUpdates)
                Toggle("Keep downloaded installers", isOn: $keepInstallers)
            }
        }.formStyle(.grouped).frame(width: 520, height: 240).navigationTitle("General")
    }
}

struct RuntimeSettingsView: View {
    @AppStorage("automaticRuntimeUpdates") private var automaticRuntimeUpdates = true
    @AppStorage("automaticDXVKUpdates") private var automaticDXVKUpdates = true
    @AppStorage("automaticVKD3DUpdates") private var automaticVKD3DUpdates = true
    var body: some View {
        Form {
            Section("Boreal Runtime") {
                Toggle("Update runtimes automatically", isOn: $automaticRuntimeUpdates)
            }
            Section("Graphics components") {
                Toggle("Update DXVK automatically", isOn: $automaticDXVKUpdates)
                Toggle("Update VKD3D-Proton automatically", isOn: $automaticVKD3DUpdates)
            }
            Section {
                Text("Runtime, DXVK, and VKD3D updates are checked independently from Boreal app updates.")
                    .foregroundStyle(.secondary)
            }
            Section { Text("Application-specific Windows and graphics options are available from that application’s details.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 520, height: 360).navigationTitle("Runtime")
    }
}

struct ConsoleModeSettingsView: View {
    @AppStorage("consoleModeEnabled") private var consoleModeEnabled = false
    @AppStorage("consoleModeAutoEnter") private var consoleModeAutoEnter = true
    @AppStorage("consoleModeReturnAfterGame") private var returnAfterGame = true

    var body: some View {
        Form {
            Section("Controller-first interface") {
                Toggle("Use Boreal Fullscreen / TV mode", isOn: $consoleModeEnabled)
                Toggle("Enter fullscreen when a controller connects", isOn: $consoleModeAutoEnter)
                Toggle("Return to fullscreen after a game exits", isOn: $returnAfterGame)
            }
            Section("Controls") {
                LabeledContent("Navigate", value: "D-pad / left stick")
                LabeledContent("Select / Back", value: "A / B")
                LabeledContent("Game menu", value: "Y")
                Text("The TV interface keeps the desktop layout available through Exit, so macOS remains recoverable at all times.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 360)
        .navigationTitle("Fullscreen")
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("developerMode") private var developerMode = false
    var body: some View {
        Form {
            Section("Advanced") {
                Toggle("Developer Mode", isOn: $developerMode)
            }
            Section { Text("Developer Mode reveals runtime internals, raw logs and environment variables.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 520, height: 300).navigationTitle("Advanced")
    }
}
