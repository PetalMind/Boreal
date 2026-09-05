import SwiftUI

struct BorealSettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("Runtime", systemImage: "gearshape.2") { RuntimeSettingsView() }
            Tab("Controllers", systemImage: "gamecontroller") { ControllerSettingsView() }
            Tab("Fullscreen", systemImage: "rectangle.inset.filled") { ConsoleModeSettingsView() }
            Tab("Overlay", systemImage: "gauge.with.dots.needle.67percent") { GameOverlaySettingsView() }
            Tab("Advanced", systemImage: "wrench.and.screwdriver") { AdvancedSettingsView() }
        }
    }
}

struct GeneralSettingsView: View {
    @Environment(BorealStore.self) private var store
    @AppStorage("automaticUpdates") private var automaticUpdates = true
    @AppStorage("keepInstallers") private var keepInstallers = false
    @AppStorage(BorealSoundSettings.enabled) private var interfaceSoundsEnabled = true
    @AppStorage(BorealSoundSettings.volume) private var interfaceSoundVolume = 0.35
    @AppStorage(BorealSoundSettings.completedDownloads) private var soundsForCompletedDownloads = true
    @AppStorage(BorealSoundSettings.installations) private var soundsForInstallations = true
    @AppStorage(BorealSoundSettings.errorsAndWarnings) private var soundsForErrorsAndWarnings = true
    @AppStorage(ITADPriceService.apiKeyDefaultsKey) private var itadAPIKey = ""
    @AppStorage(ITADPriceService.countryCodeDefaultsKey) private var itadCountryCode = "PL"

    var body: some View {
        Form {
            Section("Updates and installers") {
                Toggle("Check for updates automatically", isOn: $automaticUpdates)
                Toggle("Keep downloaded installers", isOn: $keepInstallers)
            }
            Section("Sound") {
                Toggle("Interface sounds", isOn: $interfaceSoundsEnabled)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Sound volume")
                        Spacer()
                        Text(interfaceSoundVolume, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $interfaceSoundVolume, in: 0...1)
                }
                .disabled(!interfaceSoundsEnabled)
            }
            Section("Play sounds for") {
                Toggle("Completed downloads", isOn: $soundsForCompletedDownloads)
                Toggle("Installations", isOn: $soundsForInstallations)
                Toggle("Errors and warnings", isOn: $soundsForErrorsAndWarnings)
            }
            Section("Discovery prices") {
                SecureField("IsThereAnyDeal API key", text: $itadAPIKey)
                TextField("Store country (ISO code)", text: $itadCountryCode)
                LabeledContent("Authentication", value: "API Key")
                Link("Register an API key ↗", destination: URL(string: "https://isthereanydeal.com/apps/")!)
                Text("Use the API Key from the ITAD app page. OAuth Client ID, Client Secret and Redirect URI are not needed for game prices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
        .navigationTitle("General")
        .onChange(of: itadAPIKey) { _, _ in store.invalidateDiscoveryPrices() }
        .onChange(of: itadCountryCode) { _, _ in store.invalidateDiscoveryPrices() }
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
                Toggle("Ask to enter fullscreen when a controller connects", isOn: $consoleModeAutoEnter)
                Toggle("Return to fullscreen after a game exits while a controller is connected", isOn: $returnAfterGame)
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
