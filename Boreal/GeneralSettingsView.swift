import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @Environment(BorealStore.self) private var store
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
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
                SettingsCard(.Settings.updatesTitle, subtitle: .Settings.updatesSubtitle, symbol: "arrow.triangle.2.circlepath") {
                    SettingsRow(.Settings.automaticUpdatesLabel) { Toggle("", isOn: $automaticUpdates).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.keepInstallersLabel) { Toggle("", isOn: $keepInstallers).labelsHidden() }
                }

                SettingsCard(.Settings.soundTitle, subtitle: .Settings.soundSubtitle, symbol: "speaker.wave.2.fill") {
                    SettingsRow(.Settings.interfaceSoundsLabel) { Toggle("", isOn: $interfaceSoundsEnabled).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.soundVolumeLabel) {
                        Slider(value: $interfaceSoundVolume, in: 0...1).frame(width: 180)
                        Text(interfaceSoundVolume, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    }
                    .disabled(!interfaceSoundsEnabled)
                    Divider()
                    SettingsRow(.Settings.completedDownloadsLabel) { Toggle("", isOn: $soundsForCompletedDownloads).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.installationsLabel) { Toggle("", isOn: $soundsForInstallations).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.errorsAndWarningsLabel) { Toggle("", isOn: $soundsForErrorsAndWarnings).labelsHidden() }
                }

                SettingsCard(.Settings.languageCardTitle, subtitle: .Settings.languageCardSubtitle, symbol: "character.book.closed") {
                    SettingsRow(.Settings.languageTitle) {
                        Picker(selection: $appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title).tag(language.rawValue)
                            }
                        } label: {
                            EmptyView()
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                SettingsCard(.Settings.discoveryPricesTitle, subtitle: .Settings.discoveryPricesSubtitle, symbol: "tag.fill") {
                    SettingsRow(.Settings.apiKeyLabel) {
                        SecureField(.Settings.apiKeyPlaceholder, text: $itadAPIKey, prompt: Text(.Settings.apiKeyPlaceholder))
                            .frame(width: 260)
                    }
                    Divider()
                    SettingsRow(.Settings.storeCountryLabel) {
                        TextField(.Settings.isoCodePlaceholder, text: $itadCountryCode, prompt: Text(.Settings.isoCodePlaceholder))
                            .frame(width: 260)
                    }
                    Divider()
                    SettingsRow(.Settings.authenticationLabel) { Text(.Settings.authenticationValue).foregroundStyle(.secondary) }
                    Divider()
                    SettingsRow(.Settings.itadAppPageLabel) {
                        Link(destination: URL(string: "https://isthereanydeal.com/apps/")!) {
                            Text(.Settings.registerAPIKey)
                        }
                    }
                }

                GameDiscoverySettingsCard()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: itadAPIKey) { _, _ in store.invalidateDiscoveryPrices() }
        .onChange(of: itadCountryCode) { _, _ in store.invalidateDiscoveryPrices() }
    }
}
