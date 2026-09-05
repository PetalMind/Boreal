import SwiftUI

struct BorealSettingsView: View {
    @State private var selection = SettingsCategory.general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "mountain.2.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.cyan.gradient, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BOREAL").font(.headline).tracking(1)
                        Text("One library. Every world.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 22)

                VStack(spacing: 4) {
                    ForEach(SettingsCategory.allCases) { category in
                        Button { selection = category } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.symbol)
                                    .font(.body.weight(.medium))
                                    .frame(width: 34, height: 34)
                                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.title).fontWeight(.medium)
                                    Text(category.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selection == category ? Color.accentColor.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)

                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "mountain.2.fill")
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("About Boreal")
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                .padding(18)
            }
            .frame(width: 300)
            .background(.ultraThinMaterial)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.largeTitle.bold())
                    Text("Customize Boreal to fit your workflow.")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 30)
                .padding(.bottom, 18)

                settingsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(BorealGlassBackdrop())
        }
        .frame(minWidth: 980, idealWidth: 1220, minHeight: 680, idealHeight: 780)
    }

    @ViewBuilder private var settingsContent: some View {
        switch selection {
        case .general: GeneralSettingsView()
        case .runtime: RuntimeSettingsView()
        case .controllers: ControllerSettingsView()
        case .fullscreen: ConsoleModeSettingsView()
        case .overlay: GameOverlaySettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let content: Content

    init(_ title: String, subtitle: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(width: 300, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07)))
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 20)
            content
        }
        .padding(.vertical, 8)
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, runtime, controllers, fullscreen, overlay, advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .runtime: "Runtime"
        case .controllers: "Controllers"
        case .fullscreen: "Fullscreen"
        case .overlay: "Overlay"
        case .advanced: "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Updates, sound, discovery prices"
        case .runtime: "Wine and graphics components"
        case .controllers: "Mapping and input behavior"
        case .fullscreen: "Controller-first interface"
        case .overlay: "In-game performance display"
        case .advanced: "Developer settings"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .runtime: "gearshape.2.fill"
        case .controllers: "gamecontroller.fill"
        case .fullscreen: "rectangle.inset.filled"
        case .overlay: "gauge.with.dots.needle.67percent"
        case .advanced: "wrench.and.screwdriver.fill"
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
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard("Updates & Installers", subtitle: "Control automatic updates and downloaded files.", symbol: "arrow.triangle.2.circlepath") {
                    SettingsRow("Check for updates automatically") { Toggle("", isOn: $automaticUpdates).labelsHidden() }
                    Divider()
                    SettingsRow("Keep downloaded installers") { Toggle("", isOn: $keepInstallers).labelsHidden() }
                }

                SettingsCard("Sound", subtitle: "Choose when Boreal plays interface sounds.", symbol: "speaker.wave.2.fill") {
                    SettingsRow("Interface sounds") { Toggle("", isOn: $interfaceSoundsEnabled).labelsHidden() }
                    Divider()
                    SettingsRow("Sound volume") {
                        Slider(value: $interfaceSoundVolume, in: 0...1).frame(width: 180)
                        Text(interfaceSoundVolume, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    }
                    .disabled(!interfaceSoundsEnabled)
                    Divider()
                    SettingsRow("Completed downloads") { Toggle("", isOn: $soundsForCompletedDownloads).labelsHidden() }
                    Divider()
                    SettingsRow("Installations") { Toggle("", isOn: $soundsForInstallations).labelsHidden() }
                    Divider()
                    SettingsRow("Errors and warnings") { Toggle("", isOn: $soundsForErrorsAndWarnings).labelsHidden() }
                }

                SettingsCard("Discovery Prices", subtitle: "Connect IsThereAnyDeal price data.", symbol: "tag.fill") {
                    SettingsRow("API key") { SecureField("IsThereAnyDeal API key", text: $itadAPIKey).frame(width: 260) }
                    Divider()
                    SettingsRow("Store country") { TextField("ISO code", text: $itadCountryCode).frame(width: 260) }
                    Divider()
                    SettingsRow("Authentication") { Text("API Key").foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow("ITAD app page") { Link("Register an API key ↗", destination: URL(string: "https://isthereanydeal.com/apps/")!) }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: itadAPIKey) { _, _ in store.invalidateDiscoveryPrices() }
        .onChange(of: itadCountryCode) { _, _ in store.invalidateDiscoveryPrices() }
    }
}

struct RuntimeSettingsView: View {
    @AppStorage("automaticRuntimeUpdates") private var automaticRuntimeUpdates = true
    @AppStorage("automaticDXVKUpdates") private var automaticDXVKUpdates = true
    @AppStorage("automaticVKD3DUpdates") private var automaticVKD3DUpdates = true
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard("Boreal Runtime", subtitle: "Manage the Windows compatibility runtime.", symbol: "gearshape.2.fill") {
                    SettingsRow("Update runtimes automatically") { Toggle("", isOn: $automaticRuntimeUpdates).labelsHidden() }
                }
                SettingsCard("Graphics Components", subtitle: "Keep installed translation layers current.", symbol: "display") {
                    SettingsRow("Update DXVK automatically") { Toggle("", isOn: $automaticDXVKUpdates).labelsHidden() }
                    Divider()
                    SettingsRow("Update VKD3D-Proton automatically") { Toggle("", isOn: $automaticVKD3DUpdates).labelsHidden() }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConsoleModeSettingsView: View {
    @AppStorage("consoleModeEnabled") private var consoleModeEnabled = false
    @AppStorage("consoleModeAutoEnter") private var consoleModeAutoEnter = true
    @AppStorage("consoleModeReturnAfterGame") private var returnAfterGame = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard("Controller-first Interface", subtitle: "Configure Boreal's fullscreen experience.", symbol: "rectangle.inset.filled") {
                    SettingsRow("Use Boreal Fullscreen / TV mode") { Toggle("", isOn: $consoleModeEnabled).labelsHidden() }
                    Divider()
                    SettingsRow("Ask when a controller connects") { Toggle("", isOn: $consoleModeAutoEnter).labelsHidden() }
                    Divider()
                    SettingsRow("Return after a game exits") { Toggle("", isOn: $returnAfterGame).labelsHidden() }
                }
                SettingsCard("Controls", subtitle: "Controller shortcuts used in fullscreen mode.", symbol: "gamecontroller.fill") {
                    SettingsRow("Navigate") { Text("D-pad / left stick").foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow("Select / Back") { Text("A / B").foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow("Game menu") { Text("Y").foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("developerMode") private var developerMode = false
    var body: some View {
        ScrollView {
            SettingsCard("Developer Settings", subtitle: "Reveal runtime internals, logs and environment variables.", symbol: "wrench.and.screwdriver.fill") {
                SettingsRow("Developer Mode") { Toggle("", isOn: $developerMode).labelsHidden() }
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
