import AppKit
import SwiftUI

private enum CompatibilityPreset: CaseIterable, Identifiable {
    case recommended, olderGames, performance, custom
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .recommended: "Recommended"
        case .olderGames: "Older games"
        case .performance: "Performance"
        case .custom: "Custom"
        }
    }
    var symbol: String {
        switch self {
        case .recommended: "wand.and.stars"
        case .olderGames: "clock.arrow.circlepath"
        case .performance: "gauge.with.dots.needle.67percent"
        case .custom: "gearshape"
        }
    }
}

struct WineCompatibilityConfigurator: View {
    private struct DisplayChoice: Identifiable { let id: UInt32; let label: String }

    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let application: WindowsApplication
    @State private var profile: WineCompatibilityProfile
    @State private var detectedGraphicsAPI: GraphicsAPI?
    @State private var controllerManager = ControllerManager.shared
    @State private var showsControllerMapping = false

    init(application: WindowsApplication) {
        self.application = application
        _profile = State(initialValue: GameGraphicsProfiles.effectiveCompatibilityProfile(application.resolvedCompatibilityProfile, for: application))
        _detectedGraphicsAPI = State(initialValue: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            CompatibilityHeader(title: application.name, artwork: artwork) { dismiss() }
            Divider()
            CompatibilityPresetSelector(selected: selectedPreset, action: applyPreset)
            Divider()
            GeometryReader { geometry in
                if geometry.size.width >= 760 {
                    HStack(alignment: .top, spacing: 14) {
                        ScrollView { settingsContent }.frame(maxWidth: .infinity)
                        resultCard.frame(width: 260)
                    }
                    .padding(16)
                } else {
                    ScrollView {
                        VStack(spacing: 14) { settingsContent; resultCard }
                            .padding(16)
                    }
                }
            }
            Divider()
            CompatibilitySettingsFooter(
                restore: { profile = .default }, cancel: { dismiss() }, save: save,
                saveDisabled: application.status == .running || application.status.isBusy || graphicsBackendIssue != nil
            )
        }
        .frame(minWidth: 680, idealWidth: 840, maxWidth: 900, minHeight: 620, idealHeight: 760, maxHeight: 860)
        .onAppear { profile = store.compatibilityProfile(for: application); controllerManager.start() }
        .sheet(isPresented: $showsControllerMapping) { NavigationStack { ControllerSettingsView() } }
        .task(id: application.executablePath) {
            guard graphicsProfile == nil, FileManager.default.fileExists(atPath: application.executablePath) else { return }
            let executable = URL(fileURLWithPath: application.executablePath)
            let detected = await Task.detached(priority: .utility) { GraphicsAPIDetector.detect(executable: executable) }.value
            guard !Task.isCancelled else { return }
            detectedGraphicsAPI = detected
            if profile.graphicsAPI == nil { profile.graphicsAPI = detected }
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 12) {
            graphicsSection
            displaySection
            overlaySection
            controllerSection
            advancedSection
        }
    }

    private var graphicsSection: some View {
        CompatibilitySettingsSection(title: "Graphics", subtitle: "Configure how the game runs using Wine and graphics settings.", symbol: "gearshape.2", tint: .blue) {
            CompatibilityPickerRow(title: "DirectX version", detail: graphicsAPIExplanation) {
                Picker("DirectX version", selection: graphicsAPIBinding) {
                    ForEach(GraphicsAPI.allCases) { api in Text(graphicsAPILabel(for: api)).tag(api) }
                }.labelsHidden()
            }
            CompatibilityPickerRow(title: "Graphics renderer", detail: graphicsBackendExplanation) {
                Picker("Graphics renderer", selection: $profile.graphicsBackend) {
                    ForEach(WineGraphicsBackend.allCases) { backend in Text(backendLabel(backend)).tag(backend) }
                }
                .labelsHidden()
                .disabled(usesSharedSteamEnvironment || graphicsProfile?.enforcedBackend != nil)
            }
            if let issue = graphicsBackendIssue {
                CompatibilityCallout(text: issue, symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            if usesSharedSteamEnvironment {
                CompatibilityCallout(text: String(localized: "Steam shares its Windows environment across games. Architecture, graphics renderer and older-game fixes are managed there."), symbol: "person.2.fill", tint: .blue)
            }
        }
    }

    private var displaySection: some View {
        CompatibilitySettingsSection(title: "Display", subtitle: "Configure display resolution, scaling, and window behavior.", symbol: "display", tint: .blue) {
            CompatibilityToggleRow(title: "High-resolution rendering (Retina)", detail: "Render the game at higher resolution for a sharper image.", isOn: $profile.retinaModeEnabled)
            CompatibilityToggleRow(title: "Fullscreen upscaling (FSR)", detail: "Improve performance when playing fullscreen at a lower resolution.", isOn: $profile.fullscreenFSREnabled, disabled: runtimeFeatures?.fullscreenFSR != true)
            if runtimeFeatures?.fullscreenFSR != true {
                CompatibilityCallout(text: String(localized: "The selected runtime does not implement WINE_FULLSCREEN_FSR."), symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            CompatibilityPickerRow(title: "Game display", detail: String(localized: "Choose which screen the borderless game window uses.")) {
                Picker("Game display", selection: $profile.overlayDisplayID) {
                    Text("Automatic (main display)").tag(Optional<UInt32>.none)
                    ForEach(availableDisplays) { display in Text(display.label).tag(Optional(display.id)) }
                }.labelsHidden().disabled(!profile.overlayCompatibleFullscreen)
            }
        }
    }

    private var overlaySection: some View {
        CompatibilitySettingsSection(title: "Overlay", subtitle: "Control Boreal's in-game overlay behavior.", symbol: "rectangle.on.rectangle", tint: .cyan) {
            CompatibilityToggleRow(title: "Keep Boreal overlay visible", detail: "Uses a borderless fullscreen window so the game does not cover the overlay.", isOn: $profile.overlayCompatibleFullscreen)
        }
    }

    private var controllerSection: some View {
        CompatibilitySettingsSection(title: "Controller", subtitle: "Configure how Boreal presents controllers to the game.", symbol: "gamecontroller", tint: .purple) {
            if let controller = controllerManager.controllers.first {
                HStack(spacing: 10) {
                    Image(systemName: controller.supportsExtendedProfile ? "gamecontroller.fill" : "gamecontroller")
                        .foregroundStyle(controller.supportsExtendedProfile ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(controller.name).fontWeight(.medium)
                        Text("Connected").font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    Text(profile.forceXInput ? "Xbox 360 Controller" : "Native Wine controller").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Label("No controller detected", systemImage: "gamecontroller").foregroundStyle(.secondary)
            }
            CompatibilityToggleRow(title: "Disable keyboard mapping", detail: "Stops Boreal from turning controller buttons into keyboard presses. Steam Input is unchanged.", isOn: $profile.disableSteamInputEquivalent)
            CompatibilityToggleRow(title: "Xbox controller compatibility", detail: "Presents the controller as an Xbox 360 controller. Restart the entire Wine session after changing this.", isOn: $profile.forceXInput, disabled: runtimeFeatures?.wineBusControllerMapping != true)
            Button("Controller mapping", systemImage: "gamecontroller") { showsControllerMapping = true }
        }
    }

    private var advancedSection: some View {
        CompatibilitySettingsSection(title: "Advanced", subtitle: "Change these only to solve a specific problem with this game.", symbol: "wrench.and.screwdriver", tint: .orange) {
            DisclosureGroup("Windows environment") {
                VStack(spacing: 10) {
                    CompatibilityPickerRow(title: "Windows version", detail: nil) {
                        Picker("Windows version", selection: $profile.windowsVersion) { ForEach(WineWindowsVersion.allCases) { Text($0.displayName).tag($0) } }.labelsHidden()
                    }
                    CompatibilityPickerRow(title: "Architecture", detail: String(localized: "Changing architecture rebuilds the Windows environment. Your game files stay in place.")) {
                        Picker("Architecture", selection: $profile.architecture) { ForEach(WinePrefixArchitecture.allCases) { Text($0.displayName).tag($0) } }.labelsHidden().disabled(usesSharedSteamEnvironment)
                    }
                }.padding(.top, 8)
            }
            DisclosureGroup("Older games") {
                VStack(spacing: 10) {
                    CompatibilityPickerRow(title: "Compatibility fix", detail: nil) {
                        Picker("Compatibility fix", selection: $profile.legacyWrapper) { ForEach(LegacyGraphicsWrapper.allCases) { Text($0.displayName).tag($0) } }.labelsHidden().disabled(usesSharedSteamEnvironment || runtimeFeatures?.dgVoodoo2 != true)
                    }
                    if runtimeFeatures?.dgVoodoo2 != true {
                        CompatibilityCallout(text: String(localized: "dgVoodoo2 is unavailable because the selected runtime does not contain a valid component package."), symbol: "exclamationmark.triangle.fill", tint: .orange)
                    }
                    if profile.legacyWrapper == .dgVoodoo2 {
                        CompatibilityPickerRow(title: "Older graphics API", detail: String(localized: "Uses dgVoodoo2 for the selected graphics API. Requires a runtime that includes dgVoodoo2.")) {
                            Picker("Older graphics API", selection: $profile.legacyGraphicsAPI) { ForEach(LegacyGraphicsAPI.allCases) { Text($0.displayName).tag($0) } }.labelsHidden()
                        }
                    } else {
                        Text("For older games that use DirectDraw or early Direct3D. Leave disabled unless needed.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.top, 8)
            }
            DisclosureGroup("Performance") {
                VStack(spacing: 10) {
                    CompatibilityToggleRow(title: "ESync", detail: nil, isOn: $profile.esyncEnabled, disabled: runtimeFeatures?.esync != true)
                    CompatibilityToggleRow(title: "MSync", detail: "These options can reduce CPU overhead. Support depends on the Wine runtime.", isOn: $profile.msyncEnabled, disabled: runtimeFeatures?.msync != true)
                    if runtimeFeatures?.esync != true || runtimeFeatures?.msync != true {
                        CompatibilityCallout(text: String(localized: "Unavailable switches are not exported to Wine."), symbol: "exclamationmark.triangle.fill", tint: .orange)
                    }
                }.padding(.top, 8)
            }
            DisclosureGroup("Launch and diagnostics") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Launch arguments", text: $profile.launchArguments, prompt: Text("e.g. -windowed -novsync")).textFieldStyle(.roundedBorder)
                    CompatibilityToggleRow(title: "Verbose Wine logging", detail: "Verbose logging can create large log files. Enable it only while diagnosing a problem.", isOn: $profile.debugLoggingEnabled)
                }.padding(.top, 8)
            }
        }
    }

    private var resultCard: some View {
        CompatibilityResultCard(
            application: application, profile: profile,
            directXLabel: graphicsAPIBinding.wrappedValue == .automatic ? String(localized: "Automatic") : graphicsAPIBinding.wrappedValue.displayName,
            displayLabel: selectedDisplayLabel,
            communityURL: communityURL,
            openCommunityReports: { if let communityURL { openURL(communityURL) } }
        )
    }

    private var selectedPreset: CompatibilityPreset {
        if profile == recommendedProfile { return .recommended }
        if profile == olderGameProfile { return .olderGames }
        if profile == performanceProfile { return .performance }
        return .custom
    }

    private func applyPreset(_ preset: CompatibilityPreset) {
        switch preset {
        case .recommended: profile = recommendedProfile
        case .olderGames: profile = olderGameProfile
        case .performance: profile = performanceProfile
        case .custom: break
        }
    }

    private func save() { store.updateCompatibilityProfile(for: application.id, profile: profile); dismiss() }

    private var artwork: StoreLibraryGame? {
        guard let reference = application.storeReference else { return nil }
        return store.storeGames.first { $0.storeReference == reference }
    }
    private var communityURL: URL? {
        guard let value = application.communityCompatibility?.sourceURL else { return nil }
        return URL(string: value)
    }
    private var selectedDisplayLabel: String {
        guard let id = profile.overlayDisplayID, let display = availableDisplays.first(where: { $0.id == id }) else { return String(localized: "Automatic (main display)") }
        return display.label
    }
    private var olderGameProfile: WineCompatibilityProfile { WineCompatibilityProfile(windowsVersion: .windows7, architecture: .win32, graphicsBackend: .wineD3D, esyncEnabled: true, msyncEnabled: false, retinaModeEnabled: false) }
    private var performanceProfile: WineCompatibilityProfile { WineCompatibilityProfile(windowsVersion: .windows10, architecture: .win64, graphicsBackend: .d3dMetal, esyncEnabled: true, msyncEnabled: true, retinaModeEnabled: false, fullscreenFSREnabled: true) }
    private var recommendedProfile: WineCompatibilityProfile {
        var value = WineCompatibilityProfile.default
        guard let graphicsProfile else { return value }
        value.graphicsAPI = graphicsProfile.defaultAPI
        if let backend = graphicsProfile.preferredBackend { value.graphicsBackend = backend }
        if let overlay = graphicsProfile.overlayCompatibleFullscreen { value.overlayCompatibleFullscreen = overlay }
        return value
    }
    private var usesSharedSteamEnvironment: Bool { application.usesSharedSteamEnvironment }
    private var availableDisplays: [DisplayChoice] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let size = screen.convertRectToBacking(screen.frame).size
            return DisplayChoice(id: number.uint32Value, label: "Display \(index + 1) — \(Int(size.width))×\(Int(size.height))")
        }
    }
    private var graphicsProfile: GameGraphicsProfile? { GameGraphicsProfiles.profile(for: application) }
    private var graphicsBackendIssue: String? { store.graphicsBackendIssue(profile.graphicsBackend, for: application) }
    private var runtimeFeatures: RuntimeFeatures? { store.compatibilityRuntimeFeatures(for: application, backend: profile.graphicsBackend) }
    private func backendLabel(_ backend: WineGraphicsBackend) -> String { store.graphicsBackendIssue(backend, for: application) == nil ? backend.displayName : backend.displayName + " · " + String(localized: "Unavailable") }
    private var graphicsAPIBinding: Binding<GraphicsAPI> { Binding(get: { profile.graphicsAPI ?? graphicsProfile?.defaultAPI ?? .automatic }, set: { profile.graphicsAPI = $0 }) }
    private func graphicsAPILabel(for api: GraphicsAPI) -> String {
        if let graphicsProfile, api == graphicsProfile.defaultAPI { return api.displayName + " · " + String(localized: "Recommended") }
        if graphicsProfile == nil, api == detectedGraphicsAPI { return api.displayName + " · " + String(localized: "Detected") }
        if let graphicsProfile, api != .automatic, !graphicsProfile.availableAPIs.contains(api) { return api.displayName + " · " + String(localized: "Manual") }
        return api.displayName
    }
    private var graphicsBackendExplanation: String {
        if graphicsProfile?.enforcedBackend != nil { return String(localized: "WineD3D is enforced for this game because D9VK cannot initialize its Direct3D device on this runtime.") }
        return switch profile.graphicsBackend {
        case .automatic: String(localized: "Chooses an available renderer for this game.")
        case .d3dMetal: String(localized: "For DirectX 11 and 12. Requires Game Porting Toolkit.")
        case .dxmt: String(localized: "Runs DirectX 11 using Metal. Requires DXMT support.")
        case .dxvk: String(localized: "Runs DirectX 10 and 11 using Vulkan. DirectX 9 uses WineD3D.")
        case .d9vk: String(localized: "Runs DirectX 9 using Vulkan. Requires the D9VK component.")
        case .vkd3d: String(localized: "Runs DirectX 12 using Vulkan. Requires VKD3D-Proton.")
        case .wineD3D: String(localized: "A fallback to try if other renderers cause graphics problems.")
        }
    }
    private var graphicsAPIExplanation: String {
        let api = graphicsAPIBinding.wrappedValue
        if api == .automatic { return String(localized: "Uses the detected DirectX version. Choose a specific version only if the game supports it.") }
        if graphicsProfile?.launchOption(for: api) != nil { return String(localized: "Boreal will request \(api.displayName) when this game starts.") }
        return String(localized: "This preference alone cannot switch the game to \(api.displayName). Set it in the game or add its documented launch argument under Advanced → Launch and diagnostics.")
    }
}

private struct CompatibilityHeader: View {
    let title: String; let artwork: StoreLibraryGame?; let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let artwork { GameArtworkView(game: artwork, width: 64, height: 64) }
                else { Image(systemName: "gamecontroller.fill").font(.title2).foregroundStyle(.cyan).frame(width: 64, height: 64).background(.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 11)) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Compatibility").font(.title2.weight(.semibold))
                Text(title).font(.headline).foregroundStyle(.secondary)
                Text("Choose a profile and tune graphics, display, and launch behavior.").font(.callout).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").frame(width: 28, height: 28) }
                .buttonStyle(.plain).background(.quaternary, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Close").keyboardShortcut(.cancelAction)
        }.padding(18)
    }
}

private struct CompatibilityPresetSelector: View {
    let selected: CompatibilityPreset; let action: (CompatibilityPreset) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(CompatibilityPreset.allCases) { preset in
                Button { action(preset) } label: { Label(preset.title, systemImage: preset.symbol).frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(selected == preset ? Color.white : Color.primary)
                    .background(selected == preset ? Color.accentColor : Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(selected == preset ? Color.accentColor : Color.secondary.opacity(0.14)) }
                    .allowsHitTesting(preset != .custom)
            }
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }
}

private struct CompatibilitySettingsSection<Content: View>: View {
    let title: LocalizedStringResource; let subtitle: LocalizedStringResource; let symbol: String; let tint: Color; @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 30, height: 30).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Divider(); content
        }
        .padding(14).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.55)) }
    }
}

private struct CompatibilityPickerRow<Control: View>: View {
    let title: LocalizedStringResource; let detail: String?; @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.medium); if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading)
            control.frame(width: 205)
        }
    }
}

private struct CompatibilityToggleRow: View {
    let title: LocalizedStringResource; let detail: LocalizedStringResource?; @Binding var isOn: Bool; var disabled = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.medium); if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn).labelsHidden().disabled(disabled)
        }
    }
}

private struct CompatibilityCallout: View {
    let text: String; let symbol: String; let tint: Color
    var body: some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(tint).frame(maxWidth: .infinity, alignment: .leading).padding(9)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.22)) }
    }
}

private struct CompatibilityResultCard: View {
    let application: WindowsApplication; let profile: WineCompatibilityProfile; let directXLabel: String; let displayLabel: String; let communityURL: URL?; let openCommunityReports: () -> Void
    private var rating: CompatibilityRating { application.communityCompatibility?.tier.rating ?? application.compatibility }
    private var tint: Color { switch rating { case .excellent: .green; case .good: .teal; case .limited: .orange; case .unsupported: .red; case .unknown: .secondary } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compatibility result").font(.headline)
            HStack(spacing: 12) {
                Image(systemName: rating.symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(tint).frame(width: 48, height: 48).background(tint.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 3) { Text(rating.localizedTitle).font(.title3.weight(.semibold)).foregroundStyle(tint); Text(statusDescription).font(.caption).foregroundStyle(.secondary) }
            }
            Divider(); Text("Resulting configuration").font(.subheadline.weight(.semibold))
            row("Renderer", profile.graphicsBackend.displayName, "gearshape.2")
            row("DirectX version", directXLabel, "square.3.layers.3d")
            row("Windows version", profile.windowsVersion.displayName, "window.ceiling")
            row("Game display", displayLabel, "display")
            row("Overlay compatible", profile.overlayCompatibleFullscreen ? String(localized: "Yes") : String(localized: "No"), "rectangle.on.rectangle")
            if let compatibility = application.communityCompatibility {
                row("Community reports", compatibility.reportCount.formatted(), "person.2.fill")
                Divider(); Label("Based on available community reports.", systemImage: "info.circle.fill").font(.caption).foregroundStyle(.secondary)
            }
            if communityURL != nil { Button("View community reports", systemImage: "arrow.up.right.square", action: openCommunityReports).frame(maxWidth: .infinity) }
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.55)) }
    }
    private func row(_ title: LocalizedStringResource, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) { Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 14); Text(title).font(.caption).foregroundStyle(.secondary); Spacer(minLength: 6); Text(value).font(.caption.weight(.medium)).multilineTextAlignment(.trailing) }
    }
    private var statusDescription: LocalizedStringResource {
        switch rating {
        case .excellent: "These settings should work great with this game."
        case .good: "These settings should work well with this game."
        case .limited: "This game may need additional compatibility adjustments."
        case .unsupported: "This game is currently reported as unsupported."
        case .unknown: "No compatibility rating is available for this game."
        }
    }
}

private struct CompatibilitySettingsFooter: View {
    let restore: () -> Void; let cancel: () -> Void; let save: () -> Void; let saveDisabled: Bool
    var body: some View {
        HStack { Button("Restore defaults", systemImage: "arrow.counterclockwise", action: restore); Spacer(); Button("Cancel", action: cancel); Button("Save changes", action: save).buttonStyle(.borderedProminent).disabled(saveDisabled) }.padding(16)
    }
}
