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
    var body: some View {
        Form {
            Section("Boreal Runtime") {
                Toggle("Update runtimes automatically", isOn: $automaticRuntimeUpdates)
            }
            Section { Text("Application-specific Windows and graphics options are available from that application’s details.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 520, height: 240).navigationTitle("Runtime")
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
