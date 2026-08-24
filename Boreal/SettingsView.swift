import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("showAppsInDock") private var showAppsInDock = true
    @AppStorage("detectIcons") private var detectIcons = true
    @AppStorage("isolatedApps") private var isolatedApps = true

    var body: some View {
        Form {
            Section("Applications") {
                Toggle("Show running apps in the Dock", isOn: $showAppsInDock)
                Toggle("Automatically detect application icons", isOn: $detectIcons)
                Toggle("Keep applications isolated", isOn: $isolatedApps)
            }
            Section("Opening Windows files") {
                LabeledContent("When opening an .exe") { Text("Ask what to do").foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped).frame(width: 520, height: 320).navigationTitle("General")
    }
}

struct GraphicsSettingsView: View {
    @AppStorage("preferMetal") private var preferMetal = true
    @AppStorage("performanceOptimizations") private var performanceOptimizations = true
    var body: some View {
        Form {
            Section("Rendering") {
                LabeledContent("Graphics") { Text("Automatic").foregroundStyle(.secondary) }
                Toggle("Prefer Metal", isOn: $preferMetal)
                Toggle("Performance optimizations", isOn: $performanceOptimizations)
            }
            Section { Text("Boreal selects the most reliable renderer separately for each app.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 520, height: 300).navigationTitle("Graphics")
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("experimentalRuntimes") private var experimentalRuntimes = false
    @AppStorage("runtimeLogs") private var runtimeLogs = false
    var body: some View {
        Form {
            Section("Advanced") {
                Toggle("Developer Mode", isOn: $developerMode)
                Toggle("Allow experimental runtimes", isOn: $experimentalRuntimes)
                Toggle("Enable runtime logs", isOn: $runtimeLogs)
            }
            Section { Text("Developer Mode reveals runtime internals, raw logs and environment variables.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 520, height: 300).navigationTitle("Advanced")
    }
}

