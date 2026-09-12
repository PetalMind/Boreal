import Foundation
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
        case .storage: StorageSettingsView()
        case .runtime: RuntimeSettingsView()
        case .controllers: ControllerSettingsView()
        case .fullscreen: ConsoleModeSettingsView()
        case .overlay: GameOverlaySettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let symbol: String
    let content: Content

    init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource, symbol: String, @ViewBuilder content: () -> Content) {
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
    let title: LocalizedStringResource
    let content: Content

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
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
    case general, storage, runtime, controllers, fullscreen, overlay, advanced

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general: .Settings.generalTitle
        case .storage: .Settings.storageTitle
        case .runtime: .Settings.runtimeTitle
        case .controllers: .Settings.controllersTitle
        case .fullscreen: .Settings.fullscreenTitle
        case .overlay: .Settings.overlayTitle
        case .advanced: .Settings.advancedTitle
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .general: .Settings.generalSubtitle
        case .storage: .Settings.storageSubtitle
        case .runtime: .Settings.runtimeSubtitle
        case .controllers: .Settings.controllersSubtitle
        case .fullscreen: .Settings.fullscreenSubtitle
        case .overlay: .Settings.overlaySubtitle
        case .advanced: .Settings.advancedSubtitle
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .storage: "internaldrive.fill"
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
    @Environment(BorealStore.self) private var store
    @AppStorage("automaticRuntimeUpdates") private var automaticRuntimeUpdates = true
    @AppStorage("automaticDXVKUpdates") private var automaticDXVKUpdates = true
    @AppStorage("automaticVKD3DUpdates") private var automaticVKD3DUpdates = true
    @State private var runtimeToEdit: RuntimeStatus?
    @State private var runtimeToRemove: RuntimeStatus?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(.Settings.borealRuntimeTitle, subtitle: .Settings.borealRuntimeSubtitle, symbol: "gearshape.2.fill") {
                    SettingsRow(.Settings.automaticRuntimeUpdatesLabel) { Toggle("", isOn: $automaticRuntimeUpdates).labelsHidden() }
                }
                SettingsCard(.Settings.graphicsComponentsTitle, subtitle: .Settings.graphicsComponentsSubtitle, symbol: "display") {
                    SettingsRow(.Settings.automaticDXVKUpdatesLabel) { Toggle("", isOn: $automaticDXVKUpdates).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.automaticVKD3DupdatesLabel) { Toggle("", isOn: $automaticVKD3DUpdates).labelsHidden() }
                }
                installedRuntimesCard
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await store.refreshRuntimeStatuses() }
        .sheet(item: $runtimeToEdit) { runtime in
            RuntimeEditorSheet(runtime: runtime) { name in
                store.renameRuntime(id: runtime.id, to: name)
                runtimeToEdit = nil
            }
        }
        .alert(
            "Remove Runtime?",
            isPresented: Binding(
                get: { runtimeToRemove != nil },
                set: { if !$0 { runtimeToRemove = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                guard let runtime = runtimeToRemove else { return }
                runtimeToRemove = nil
                store.removeRuntime(id: runtime.id)
            }
            Button("Cancel", role: .cancel) { runtimeToRemove = nil }
        } message: {
            Text(runtimeToRemove.map {
                "This removes the immutable \($0.name) snapshot from Boreal. Environments using it must be removed first."
            } ?? "")
        }
    }

    private var installedRuntimesCard: some View {
        SettingsCard(
            "Installed runtimes",
            subtitle: "Rename a runtime or remove an unused snapshot. Runtime files stay immutable.",
            symbol: "shippingbox.fill"
        ) {
            let runtimes = store.runtimeStatuses.filter { $0.source == .installed }
            if let operation = store.runtimeOperationDetail {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            if runtimes.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                    Text("No runtime is installed yet. Import or install one from Downloads.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(runtimes) { runtime in
                    runtimeRow(runtime)
                    if runtime.id != runtimes.last?.id { Divider() }
                }
            }
        }
    }

    private func runtimeRow(_ runtime: RuntimeStatus) -> some View {
        let environmentCount = store.environments.filter { $0.runtimeID == runtime.id }.count
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: runtime.isVerified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(runtime.isVerified ? Color.green : Color.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(runtime.name)
                    .font(.headline)
                Text("\(runtime.engine.displayName) · \(runtime.wineVersion) · \(runtime.architecture.rawValue)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if environmentCount > 0 {
                    Text("Used by \(environmentCount) \(environmentCount == 1 ? "environment" : "environments")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(runtime.isVerified ? "Verified and available" : "Needs attention")
                        .font(.caption)
                        .foregroundStyle(runtime.isVerified ? Color.secondary : Color.orange)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button("Edit") { runtimeToEdit = runtime }
                    .buttonStyle(.bordered)
                Button("Remove", role: .destructive) { runtimeToRemove = runtime }
                    .buttonStyle(.bordered)
                    .disabled(environmentCount > 0 || store.runtimeOperationDetail != nil)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct RuntimeEditorSheet: View {
    let runtime: RuntimeStatus
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(runtime: RuntimeStatus, onSave: @escaping (String) -> Void) {
        self.runtime = runtime
        self.onSave = onSave
        _name = State(initialValue: runtime.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Edit runtime")
                    .font(.title2.bold())
                Text("Only the display label changes. The validated Wine/GPTK payload remains read-only.")
                    .foregroundStyle(.secondary)
            }
            TextField("Runtime name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Text("\(name.trimmingCharacters(in: .whitespacesAndNewlines).count)/80")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidName)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var isValidName: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty
            && value.count <= 80
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private func save() {
        guard isValidName else { return }
        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

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
