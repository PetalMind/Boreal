import AppKit
import SwiftUI
import UniformTypeIdentifiers

private func compatibilityLocalizedBackendName(_ backend: WineGraphicsBackend) -> String {
    backend == .automatic ? String(localized: "Automatic") : backend.displayName
}

private func compatibilityLocalizedGraphicsAPIName(_ api: GraphicsAPI) -> String {
    api == .automatic ? String(localized: "Automatic") : api.displayName
}

private func compatibilityLocalizedPrefixModeName(_ mode: WinePrefixMode) -> String {
    switch mode {
    case .wow64: String(localized: "WoW64")
    case .legacyWin32: String(localized: "Legacy Win32")
    case .legacyWin64: String(localized: "Legacy Win64")
    }
}

private func compatibilityLocalizedFSRModeName(_ mode: FullscreenFSRMode) -> String {
    switch mode {
    case .ultra: String(localized: "Ultra Quality")
    case .quality: String(localized: "Quality")
    case .balanced: String(localized: "Balanced")
    case .performance: String(localized: "Performance")
    }
}

private func compatibilityLocalizedLegacyWrapperName(_ wrapper: LegacyGraphicsWrapper) -> String {
    wrapper == .none ? String(localized: "Disabled") : wrapper.displayName
}

private func compatibilityLocalizedTemporalBridgeName(_ bridge: TemporalUpscalingBridge) -> String {
    switch bridge {
    case .none: String(localized: "Disabled")
    case .ngxToMetalFX: String(localized: "NGX → MetalFX")
    }
}

private func compatibilityLocalizedCapabilityTitle(_ capability: UpscalingCapability) -> String {
    switch capability.id {
    case "wine-fsr1": String(localized: "Wine FSR 1")
    case "temporal-fsr-replacement": String(localized: "FSR replacement")
    case "cyberfsr": String(localized: "GTA SA DLSS Unlocker")
    case "optiscaler": String(localized: "Bridge")
    default: capability.title
    }
}

private func compatibilityLocalizedCapabilityDetail(_ capability: UpscalingCapability) -> String {
    switch capability.detail {
    case "Requires compatible Vulkan graphics path": String(localized: "Requires compatible Vulkan graphics path")
    case "Verified for the selected runtime and graphics path": String(localized: "Verified for the selected runtime and graphics path")
    case "Detected, but not verified on this macOS graphics path": String(localized: "Detected, but not verified on this macOS graphics path")
    case "Game interface detected": String(localized: "Game interface detected")
    case "GTA SA DLSS Unlocker detected; compatibility is not verified": String(localized: "GTA SA DLSS Unlocker detected; compatibility is not verified")
    case "GTA SA DLSS Unlocker detected; output and compatibility are not verified": String(localized: "GTA SA DLSS Unlocker detected; output and compatibility are not verified")
    case "Experimental temporal replacement through OptiScaler": String(localized: "Experimental temporal replacement through OptiScaler")
    case "No temporal replacement bridge detected": String(localized: "No temporal replacement bridge detected")
    case "OptiScaler detected; output and compatibility are not verified": String(localized: "OptiScaler detected; output and compatibility are not verified")
    case "OptiScaler is not installed for this game": String(localized: "OptiScaler is not installed for this game")
    case "NVIDIA NGX forwarder detected; the MetalFX bridge is not verified": String(localized: "NVIDIA NGX forwarder detected; the MetalFX bridge is not verified")
    case "Runtime reports an upscaling path; the NVIDIA NGX bridge is not verified": String(localized: "Runtime reports an upscaling path; the NVIDIA NGX bridge is not verified")
    case "No verified NVIDIA NGX to MetalFX bridge detected": String(localized: "No verified NVIDIA NGX to MetalFX bridge detected")
    case "Bridge installed from GPTK; compatibility is not verified": String(localized: "Bridge installed from GPTK; compatibility is not verified")
    default: capability.detail
    }
}

private enum CompatibilityPreset: CaseIterable, Identifiable {
    case recommended, legacy, performance, custom
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .recommended: "Recommended"
        case .legacy: "Legacy"
        case .performance: "Performance"
        case .custom: "Custom"
        }
    }
    var symbol: String {
        switch self {
        case .recommended: "wand.and.stars"
        case .legacy: "clock.arrow.circlepath"
        case .performance: "gauge.with.dots.needle.67percent"
        case .custom: "gearshape"
        }
    }
}

struct WineCompatibilityConfigurator: View {
    private struct DisplayChoice: Identifiable { let id: UInt32; let label: String }
    private enum GameLaunchMode: String, CaseIterable, Identifiable {
        case virtualDesktop
        case direct

        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .virtualDesktop: "Virtual desktop"
            case .direct: "Directly"
            }
        }
    }

    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let application: WindowsApplication
    @State private var profile: WineCompatibilityProfile
    @State private var detectedGraphicsAPI: GraphicsAPI?
    @State private var controllerManager = ControllerManager.shared
    @State private var showsComponentsPatches = false
    @State private var showsControllerSettings = false
    @State private var showsRuntimeOverride = false
    @State private var temporalInspector: TemporalUpscalingInspectorSnapshot?

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
                restore: { profile = .default; showsRuntimeOverride = false }, cancel: { dismiss() }, save: save,
                saveDisabled: application.status == .running || application.status.isBusy || graphicsBackendIssue != nil || prefixModeIssue != nil || selectedRuntimeIssue != nil,
                saveTitle: requiresEnvironmentRebuild ? "Apply & Rebuild" : "Save changes",
                showsRebuildNotice: requiresEnvironmentRebuild
            )
        }
        .frame(minWidth: 680, idealWidth: 840, maxWidth: 900, minHeight: 620, idealHeight: 760, maxHeight: 860)
        .onAppear {
            profile = store.compatibilityProfile(for: application)
            showsRuntimeOverride = profile.runtimeIDOverride != nil
            controllerManager.start()
        }
        .sheet(isPresented: $showsControllerSettings) { NavigationStack { ControllerSettingsView() } }
        .sheet(isPresented: $showsComponentsPatches, onDismiss: {
            Task { temporalInspector = await store.temporalUpscalingInspector(for: application.id) }
        }) {
            ComponentsAndPatchesView(application: application, profile: $profile)
        }
        .onReceive(NotificationCenter.default.publisher(for: .borealRuntimeImportCompleted)) { _ in
            Task { temporalInspector = await store.temporalUpscalingInspector(for: application.id) }
        }
        .task(id: application.executablePath) {
            guard graphicsProfile == nil, FileManager.default.fileExists(atPath: application.executablePath) else { return }
            let executable = URL(fileURLWithPath: application.executablePath)
            let detected = await Task.detached(priority: .utility) { GraphicsAPIDetector.detect(executable: executable) }.value
            guard !Task.isCancelled else { return }
            detectedGraphicsAPI = detected
            if profile.graphicsAPI == nil { profile.graphicsAPI = detected }
        }
        .task(id: application.environmentID) {
            temporalInspector = await store.temporalUpscalingInspector(for: application.id)
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 12) {
            graphicsSection
            upscalingSection
            displaySection
            overlaySection
            controllerSection
            advancedSection
        }
    }

    private var graphicsSection: some View {
        CompatibilitySettingsSection(title: "Graphics", subtitle: "Configure how the game runs using Wine and graphics settings.", symbol: "gearshape.2", tint: .blue) {
            CompatibilityPickerRow(title: "Runtime", detail: String(localized: "Boreal selects a compatible runtime automatically. Override it only when you need a specific runtime.")) {
                HStack(spacing: 8) {
                    if showsRuntimeOverride {
                        Picker("Runtime", selection: $profile.runtimeIDOverride) {
                            Text("Automatic").tag(Optional<String>.none)
                            ForEach(availableRuntimes) { runtime in
                                Text(runtimeLabel(runtime))
                                    .tag(Optional(runtime.id))
                                    .disabled(store.runtimeSelectionIssue(runtime.id, profile: profile) != nil)
                            }
                        }
                        .labelsHidden()
                    } else {
                        Text("Automatic").foregroundStyle(.secondary)
                    }
                    Button(showsRuntimeOverride ? "Automatic" : "Override") {
                        showsRuntimeOverride.toggle()
                        if !showsRuntimeOverride { profile.runtimeIDOverride = nil }
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(usesSharedSteamEnvironment)
            }
            if showsRuntimeOverride, profile.runtimeIDOverride != nil {
                Label("Pinned by user", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let runtimeLabel = automaticallySelectedRuntimeLabel {
                Text("Selected automatically: \(runtimeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let selectedRuntimeIssue {
                CompatibilityCallout(text: selectedRuntimeIssue, symbol: "exclamationmark.triangle.fill", tint: .orange)
                Button("Use automatic runtime", systemImage: "wand.and.stars") {
                    showsRuntimeOverride = false
                    profile.runtimeIDOverride = nil
                }
                .buttonStyle(.bordered)
            }
            CompatibilityPickerRow(title: "Game API", detail: graphicsAPIExplanation) {
                Picker("Game API", selection: graphicsAPIBinding) {
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
                if profile.graphicsBackend != .automatic {
                    Button("Use automatic renderer", systemImage: "wand.and.stars") {
                        profile.graphicsBackend = .automatic
                    }
                    .buttonStyle(.bordered)
                }
                if profile.graphicsBackend == .d3dMetal {
                    Button("Manage runtimes…", systemImage: "shippingbox") { openRuntimeManager() }
                        .buttonStyle(.bordered)
                }
            }
            if let event = application.compatibilityFallbackEvents?.last {
                CompatibilityCallout(
                    text: String(localized: "Boreal switched from \(compatibilityLocalizedBackendName(event.failedBackend)) to \(compatibilityLocalizedBackendName(event.fallbackBackend)) after a Direct3D device initialization failure."),
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .orange
                )
            }
            if usesSharedSteamEnvironment {
                CompatibilityCallout(text: String(localized: "Steam shares its Windows environment across games. Architecture, graphics renderer and older-game fixes are managed there."), symbol: "person.2.fill", tint: .blue)
            }
        }
    }

    private var displaySection: some View {
        CompatibilitySettingsSection(title: "Display", subtitle: "Configure display resolution, scaling, and window behavior.", symbol: "display", tint: .blue) {
            CompatibilityToggleRow(title: "High-resolution rendering (Retina)", detail: "Render the game at higher resolution for a sharper image.", isOn: $profile.retinaModeEnabled, disabled: usesSharedSteamEnvironment)
            CompatibilityPickerRow(title: "Game display", detail: String(localized: "Choose which screen the borderless game window uses.")) {
                Picker("Game display", selection: $profile.overlayDisplayID) {
                    Text("Automatic (main display)").tag(Optional<UInt32>.none)
                    ForEach(availableDisplays) { display in Text(display.label).tag(Optional(display.id)) }
                }.labelsHidden().disabled(!profile.overlayCompatibleFullscreen)
            }
        }
    }

    private var upscalingSection: some View {
        let spatialCapability = spatialUpscalingCapability
        return CompatibilitySettingsSection(title: "Upscaling", subtitle: "Boreal chooses compatible spatial and temporal paths from real capability data.", symbol: "arrow.up.left.and.arrow.down.right", tint: .orange) {
            let game = temporalInspector?.game
            let plan = temporalInspector?.temporalPlan
            CompatibilityPickerRow(title: "Upscaling mode", detail: String(localized: "Automatic follows detected game capabilities. Detailed components and bridges are managed separately.")) {
                Picker("Upscaling mode", selection: temporalModeBinding) {
                    ForEach(TemporalUpscalingMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                }
                .labelsHidden()
            }
            CompatibilityUpscalingRow(
                title: "Wine Fullscreen FSR 1",
                detail: compatibilityLocalizedCapabilityTitle(spatialCapability),
                status: spatialCapability.status,
                explanation: compatibilityLocalizedCapabilityDetail(spatialCapability)
            )
            CompatibilityToggleRow(
                title: "Enable spatial upscaling",
                detail: "Requested preference for Wine's fullscreen FSR path. It becomes active only with a verified compatible Vulkan path and no active temporal path.",
                isOn: $profile.fullscreenFSREnabled
            )
            CompatibilityUpscalingRow(
                title: "Effective path",
                detail: plan?.effective.displayName ?? String(localized: "Unavailable"),
                status: temporalStatus(plan?.compatibility),
                explanation: plan?.reason ?? String(localized: "The selected runtime or game capability is unavailable.")
            )
            if let game {
                Text("Detected: \(detectedTemporalInterfaceLabel(game))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Label(componentSummary, systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Components & Patches…", systemImage: "arrow.right") { showsComponentsPatches = true }
                    .buttonStyle(.bordered)
            }
            if let reason = fullscreenFSRUnavailableReason {
                VStack(alignment: .leading, spacing: 8) {
                    CompatibilityCallout(text: reason, symbol: "exclamationmark.triangle.fill", tint: .orange)
                    if fullscreenFSRBlockedByOverlay {
                        Button("Switch to Direct launch", systemImage: "arrow.right") {
                            profile.overlayCompatibleFullscreen = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var overlaySection: some View {
        CompatibilitySettingsSection(title: "Launch mode", subtitle: "Choose how Wine creates the game window.", symbol: "rectangle.on.rectangle", tint: .cyan) {
            CompatibilityPickerRow(title: "Start game", detail: launchModeExplanation) {
                Picker("Start game", selection: gameLaunchModeBinding) {
                    ForEach(GameLaunchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if profile.overlayCompatibleFullscreen {
                CompatibilityCallout(
                    text: String(localized: "The virtual desktop keeps Boreal's overlay above the game, but some games may require direct launch to locate their files correctly."),
                    symbol: "rectangle.on.rectangle",
                    tint: .blue
                )
            }
        }
    }

    private var controllerSection: some View {
        CompatibilitySettingsSection(title: "Controller compatibility", subtitle: "Choose how Boreal exposes the controller to this game.", symbol: "gamecontroller", tint: .purple) {
            HStack(spacing: 10) {
                Image(systemName: controllerManager.controllers.first?.supportsExtendedProfile == true ? "gamecontroller.fill" : "gamecontroller")
                    .foregroundStyle(controllerManager.controllers.first?.supportsExtendedProfile == true ? .green : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Present as Xbox 360 Controller").fontWeight(.medium)
                    Text(controllerManager.controllers.first?.name ?? "No controller detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Present as Xbox 360 Controller", isOn: $profile.forceXInput)
                    .labelsHidden()
                    .disabled(usesSharedSteamEnvironment || runtimeFeatures?.wineBusControllerMapping != true)
            }
            Text("Restart the entire Wine session after changing this setting.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Configure controller…", systemImage: "arrow.right") { showsControllerSettings = true }
                .buttonStyle(.bordered)
        }
    }

    private var advancedSection: some View {
        CompatibilitySettingsSection(title: "Advanced", subtitle: "Change these only to solve a specific problem with this game.", symbol: "wrench.and.screwdriver", tint: .orange) {
            DisclosureGroup("Windows environment") {
                VStack(spacing: 10) {
                    CompatibilityPickerRow(title: "Windows version", detail: nil) {
                        Picker("Windows version", selection: $profile.windowsVersion) { ForEach(WineWindowsVersion.allCases) { Text($0.displayName).tag($0) } }.labelsHidden().disabled(usesSharedSteamEnvironment)
                    }
                    CompatibilityPickerRow(title: "Windows executable architecture", detail: String(localized: "This describes the selected Windows executable. It is separate from the Wine prefix mode.")) {
                        Picker("Windows executable architecture", selection: $profile.architecture) { ForEach(WinePrefixArchitecture.allCases) { Text(executableArchitectureLabel($0)).tag($0) } }.labelsHidden().disabled(usesSharedSteamEnvironment)
                    }
                    CompatibilityPickerRow(title: "Wine prefix", detail: prefixModeExplanation) {
                        Picker("Wine prefix", selection: prefixModeBinding) {
                            ForEach(WinePrefixMode.allCases) { mode in
                                Text(prefixModeLabel(mode)).tag(mode).disabled(store.prefixModeIssue(mode, for: application) != nil)
                            }
                        }
                        .labelsHidden()
                        .disabled(usesSharedSteamEnvironment)
                    }
                    if let prefixModeIssue {
                        CompatibilityCallout(text: prefixModeIssue, symbol: "exclamationmark.triangle.fill", tint: .orange)
                    }
                }.padding(.top, 8)
            }
            DisclosureGroup("Legacy compatibility") {
                VStack(spacing: 10) {
                    CompatibilityPickerRow(title: "Compatibility fix", detail: nil) {
                        Picker("Compatibility fix", selection: $profile.legacyWrapper) { ForEach(LegacyGraphicsWrapper.allCases) { Text(compatibilityLocalizedLegacyWrapperName($0)).tag($0) } }.labelsHidden().disabled(usesSharedSteamEnvironment || runtimeFeatures?.dgVoodoo2 != true)
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
        VStack(spacing: 12) {
            CompatibilityLaunchPlanCard(
                application: application,
                profile: profile,
                gameAPILabel: compatibilityLocalizedGraphicsAPIName(graphicsAPIBinding.wrappedValue),
                runtimeLabel: profile.runtimeIDOverride.flatMap { id in availableRuntimes.first(where: { $0.id == id }).map { runtimeLabel($0) } }
                    ?? automaticallySelectedRuntimeLabel,
                displayLabel: selectedDisplayLabel,
                temporalPath: temporalInspector?.temporalPlan.effective.displayName,
                configurationIssue: launchPlanIssue
            )
            CompatibilityCommunityCard(
                application: application,
                communityURL: communityURL,
                openCommunityReports: { if let communityURL { openURL(communityURL) } }
            )
        }
    }

    private var selectedPreset: CompatibilityPreset {
        if profile == recommendedProfile { return .recommended }
        if profile == legacyProfile { return .legacy }
        if profile == performanceProfile { return .performance }
        return .custom
    }

    private func applyPreset(_ preset: CompatibilityPreset) {
        let pinnedRuntimeID = showsRuntimeOverride ? profile.runtimeIDOverride : nil
        switch preset {
        case .recommended: profile = recommendedProfile
        case .legacy: profile = legacyProfile
        case .performance: profile = performanceProfile
        case .custom: break
        }
        if preset != .custom, showsRuntimeOverride { profile.runtimeIDOverride = pinnedRuntimeID }
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
    private var automaticallySelectedRuntimeLabel: String? {
        guard profile.runtimeIDOverride == nil,
              let runtimeID = store.environment(id: application.environmentID)?.runtimeID,
              let runtime = store.runtimeStatuses.first(where: { $0.id == runtimeID && $0.source == .installed }) else { return nil }
        return runtimeLabel(runtime)
    }
    private var componentSummary: String {
        guard let inspector = temporalInspector else { return String(localized: "Analyzing components…") }
        let installed = [inspector.dlsstweaks, inspector.optiScaler, inspector.managedDLSSRuntime].filter(\.installed).count
        guard installed > 0 else { return String(localized: "No optional components installed") }
        return "\(installed) \(installed == 1 ? "component" : "components") installed"
    }
    private var requiresEnvironmentRebuild: Bool {
        let original = store.compatibilityProfile(for: application)
        return original.architecture != profile.architecture
            || original.prefixMode != profile.prefixMode
            || original.runtimeIDOverride != profile.runtimeIDOverride
            || original.graphicsBackend != profile.graphicsBackend
    }
    private var launchPlanIssue: String? {
        if let issue = graphicsBackendIssue ?? prefixModeIssue ?? selectedRuntimeIssue { return issue }
        if let plan = temporalInspector?.temporalPlan,
           case .unsupported = plan.compatibility {
            return plan.reason
        }
        return fullscreenFSRUnavailableReason
    }
    private func openRuntimeManager() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .borealOpenRuntimeSettings, object: nil)
        }
    }
    private var prefixModeBinding: Binding<WinePrefixMode> {
        Binding(
            get: { profile.prefixMode ?? .wow64 },
            set: { profile.prefixMode = $0 }
        )
    }
    private func executableArchitectureLabel(_ architecture: WinePrefixArchitecture) -> String {
        architecture == .win32 ? "32-bit (x86)" : "64-bit (x64)"
    }
    private func prefixModeLabel(_ mode: WinePrefixMode) -> String {
        guard store.prefixModeIssue(mode, for: application) == nil else {
            return compatibilityLocalizedPrefixModeName(mode) + " · " + String(localized: "Unavailable")
        }
        return compatibilityLocalizedPrefixModeName(mode)
    }
    private var prefixModeExplanation: String {
        let mode = profile.prefixMode ?? .wow64
        return switch mode {
        case .wow64:
            String(localized: "Modern combined prefix. WINEARCH is left unset and both 32-bit and 64-bit processes can run in one environment.")
        case .legacyWin32:
            String(localized: "Classic 32-bit prefix. Uses WINEARCH=win32 and requires a runtime that supports legacy prefixes.")
        case .legacyWin64:
            String(localized: "Classic 64-bit prefix. Uses WINEARCH=win64 and requires a runtime that supports legacy prefixes.")
        }
    }
    private var legacyProfile: WineCompatibilityProfile {
        var value = profile
        value.architecture = detectedExecutableArchitecture
        value.graphicsAPI = detectedGameAPI
        value.graphicsBackend = .wineD3D
        value.graphicsFallback = .none
        value.legacyWrapper = .none
        value.esyncEnabled = true
        value.msyncEnabled = false
        value.retinaModeEnabled = false
        value.fullscreenFSREnabled = false
        value.temporalUpscaling.mode = .automatic
        value.upscalingBridge = .none
        return value
    }
    private var performanceProfile: WineCompatibilityProfile {
        var value = profile
        value.graphicsBackend = .d3dMetal
        value.esyncEnabled = true
        value.msyncEnabled = true
        value.retinaModeEnabled = false
        value.fullscreenFSREnabled = false
        value.temporalUpscaling.mode = .automatic
        value.upscalingBridge = .none
        return value
    }
    private var recommendedProfile: WineCompatibilityProfile {
        var value = WineCompatibilityProfile.default
        guard let graphicsProfile else { return value }
        value.graphicsAPI = graphicsProfile.defaultAPI
        if let backend = graphicsProfile.preferredBackend { value.graphicsBackend = backend }
        if let overlay = graphicsProfile.overlayCompatibleFullscreen { value.overlayCompatibleFullscreen = overlay }
        return value
    }
    private var usesSharedSteamEnvironment: Bool { application.usesSharedSteamEnvironment }
    private var detectedExecutableArchitecture: WinePrefixArchitecture {
        switch WindowsExecutableArchitecture.inspect(URL(fileURLWithPath: application.executablePath)) {
        case .x86: .win32
        case .x86_64: .win64
        case .unknown: profile.architecture
        }
    }
    private var detectedGameAPI: GraphicsAPI {
        if let graphicsProfile { return graphicsProfile.defaultAPI }
        return detectedGraphicsAPI ?? profile.graphicsAPI ?? .automatic
    }
    private var availableDisplays: [DisplayChoice] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            guard let displayID = UInt32(exactly: number.int64Value) else { return nil }
            let size = screen.convertRectToBacking(screen.frame).size
            guard let width = Self.displayDimension(size.width),
                  let height = Self.displayDimension(size.height) else { return nil }
            return DisplayChoice(id: displayID, label: "\(String(localized: "Display")) \(index + 1) — \(width)×\(height)")
        }
    }

    private static func displayDimension(_ value: CGFloat) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: Double(value.rounded()))
    }
    private var graphicsProfile: GameGraphicsProfile? { GameGraphicsProfiles.profile(for: application) }
    private var availableRuntimes: [RuntimeStatus] { store.installedRuntimeStatusesForGameConfiguration() }
    private var selectedRuntimeIssue: String? {
        guard let runtimeID = profile.runtimeIDOverride else { return nil }
        return store.runtimeSelectionIssue(runtimeID, profile: profile)
    }
    private func runtimeLabel(_ runtime: RuntimeStatus) -> String {
        "\(runtime.name) · \(runtime.engine.displayName) \(runtime.wineVersion)"
    }
    private var graphicsBackendIssue: String? { store.graphicsBackendIssue(profile.graphicsBackend, for: application) }
    private var prefixModeIssue: String? {
        profile.runtimeIDOverride == nil
            ? store.prefixModeIssue(profile.prefixMode ?? .wow64, for: application)
            : nil
    }
    private var runtimeFeatures: RuntimeFeatures? {
        if let runtimeID = profile.runtimeIDOverride,
           let selected = availableRuntimes.first(where: { $0.id == runtimeID }) {
            return selected.features
        }
        return store.compatibilityRuntimeFeatures(for: application, backend: profile.graphicsBackend)
    }
    private var fullscreenFSRCapabilities: FullscreenFSRCapabilities {
        runtimeFeatures?.fullscreenFSRCapabilities
            ?? FullscreenFSRCapabilities(available: runtimeFeatures?.fullscreenFSR == true, source: .payloadInspection)
    }
    private var spatialUpscalingCapability: UpscalingCapability {
        SpatialUpscalingResolver.resolve(
            runtimeFeatures: runtimeFeatures,
            backend: fullscreenFSRResolvedBackend
        )
    }

    private var temporalModeBinding: Binding<TemporalUpscalingMode> {
        Binding(
            get: {
                if profile.temporalUpscaling.mode == .automatic, profile.upscalingBridge == .ngxToMetalFX {
                    return .metalFXBridge
                }
                return profile.temporalUpscaling.mode
            },
            set: {
                profile.temporalUpscaling.mode = $0
                profile.upscalingBridge = $0 == .metalFXBridge ? .ngxToMetalFX : .none
            }
        )
    }

    private func detectedTemporalInterfaceLabel(_ game: GameUpscalingCapabilities) -> String {
        guard !game.detectedTemporalInterfaces.isEmpty else { return String(localized: "None detected") }
        return game.detectedTemporalInterfaces.map { capability in
            "\(capability.kind.displayName) · \(capability.version ?? String(localized: "Unknown version"))"
        }.joined(separator: ", ")
    }

    private func temporalInterfaceExplanation(_ game: GameUpscalingCapabilities) -> String {
        guard !game.detectedTemporalInterfaces.isEmpty else {
            return String(localized: "No DLSS, FSR 2+ or XeSS interface was detected in the game files.")
        }
        return game.detectedTemporalInterfaces.map { capability in
            "\(capability.kind.displayName): \(capability.confidence.rawValue) confidence; runtime operation is not proven."
        }.joined(separator: " ")
    }

    private func temporalStatus(_ compatibility: TemporalBridgeCompatibility?) -> UpscalingDetectionStatus {
        guard let compatibility else { return .candidate }
        switch compatibility {
        case .unsupported: return .unavailable
        case .candidate, .experimental: return .candidate
        case .verified: return .verified
        }
    }

    private var fullscreenFSRResolvedBackend: GraphicsBackend {
        switch profile.graphicsBackend {
        case .automatic:
            let api = graphicsAPIBinding.wrappedValue
            if runtimeFeatures?.d3dmetal == true, (api == .directX11 || api == .directX12) { return .d3dMetal }
            if runtimeFeatures?.dxvk == true, api != .directX12 { return .dxvk }
            if runtimeFeatures?.vkd3d == true, api == .directX12 { return .vkd3d }
            if runtimeFeatures?.dxmt == true { return .dxmt }
            return .wineD3D
        default: return profile.graphicsBackend
        }
    }
    private var fullscreenFSRStackSupportLevel: FullscreenFSRSupportLevel {
        runtimeFeatures?.graphicsCapabilities?[fullscreenFSRResolvedBackend.rawValue]?.fullscreenFSRSupport
            ?? GraphicsStackCatalog.stack(for: fullscreenFSRResolvedBackend)?.fullscreenFSRSupportLevel
            ?? .unsupported
    }
    private var uiSharpening: Int { 5 - min(max(profile.fullscreenFSRStrength, 0), 5) }
    private var sharpeningBinding: Binding<Double> {
        Binding(
            get: { Double(uiSharpening) },
            set: { profile.fullscreenFSRStrength = 5 - Int($0.rounded()) }
        )
    }
    private var gameLaunchModeBinding: Binding<GameLaunchMode> {
        Binding(
            get: { profile.overlayCompatibleFullscreen ? .virtualDesktop : .direct },
            set: { profile.overlayCompatibleFullscreen = $0 == .virtualDesktop }
        )
    }
    private var launchModeExplanation: String {
        profile.overlayCompatibleFullscreen
            ? String(localized: "Runs the game inside Boreal's virtual desktop and keeps the overlay available.")
            : String(localized: "Runs the executable directly in its game directory without a virtual desktop.")
    }
    private var fullscreenFSRUnavailableReason: String? {
        guard profile.fullscreenFSREnabled else { return nil }
        if !fullscreenFSRCapabilities.available {
            return String(localized: "Unavailable with the selected runtime. Your preference will be restored when a compatible runtime is selected.")
        }
        if fullscreenFSRCapabilities.confidence != .verified {
            return String(localized: "Detected in the selected runtime, but not verified by a macOS fullscreen smoke test.")
        }
        if fullscreenFSRStackSupportLevel == .unsupported {
            return String(localized: "Unavailable with the current renderer. Wine fullscreen FSR requires a Vulkan-based DXVK or VKD3D-Proton stack.")
        }
        if fullscreenFSRStackSupportLevel != .verified {
            return String(localized: "The current renderer is a candidate for Wine fullscreen FSR, but this runtime graphics path is not verified on macOS.")
        }
        if profile.overlayCompatibleFullscreen {
            return String(localized: "Unavailable while Boreal overlay fullscreen is enabled. Disable the overlay-compatible fullscreen mode to use Wine fullscreen FSR.")
        }
        return nil
    }
    private var fullscreenFSRBlockedByOverlay: Bool {
        profile.fullscreenFSREnabled
            && profile.overlayCompatibleFullscreen
            && fullscreenFSRCapabilities.available
            && fullscreenFSRCapabilities.confidence == .verified
            && fullscreenFSRStackSupportLevel == .verified
    }
    private func backendLabel(_ backend: WineGraphicsBackend) -> String { store.graphicsBackendIssue(backend, for: application) == nil ? compatibilityLocalizedBackendName(backend) : compatibilityLocalizedBackendName(backend) + " · " + String(localized: "Unavailable") }
    private var graphicsAPIBinding: Binding<GraphicsAPI> { Binding(get: { profile.graphicsAPI ?? graphicsProfile?.defaultAPI ?? .automatic }, set: { profile.graphicsAPI = $0 }) }
    private func graphicsAPILabel(for api: GraphicsAPI) -> String {
        if let graphicsProfile, api == graphicsProfile.defaultAPI { return compatibilityLocalizedGraphicsAPIName(api) + " · " + String(localized: "Recommended") }
        if graphicsProfile == nil, api == detectedGraphicsAPI { return compatibilityLocalizedGraphicsAPIName(api) + " · " + String(localized: "Detected") }
        if let graphicsProfile, api != .automatic, !graphicsProfile.availableAPIs.contains(api) { return compatibilityLocalizedGraphicsAPIName(api) + " · " + String(localized: "Manual") }
        return compatibilityLocalizedGraphicsAPIName(api)
    }
    private var graphicsBackendExplanation: String {
        if let enforcedBackend = graphicsProfile?.enforcedBackend {
            return enforcedBackendExplanation(for: enforcedBackend)
        }
        return switch profile.graphicsBackend {
        case .automatic: String(localized: "Chooses an available renderer for this game.")
        case .d3dMetal: String(localized: "For DirectX 11 and 12. Requires Game Porting Toolkit.")
        case .dxmt: String(localized: "Runs DirectX 11 using Metal. Requires DXMT support.")
        case .dxvk: String(localized: "Runs DirectX 9, 10, and 11 when the managed Vulkan component supplies the required DLLs.")
        case .vkd3d: String(localized: "Runs DirectX 12 using Vulkan. Requires VKD3D-Proton.")
        case .wineD3D: String(localized: "A fallback to try if other renderers cause graphics problems.")
        }
    }
    private func enforcedBackendExplanation(for backend: WineGraphicsBackend) -> String {
        switch backend {
        case .automatic:
            return String(localized: "Automatic renderer selection is enforced for this game by its compatibility profile.")
        case .d3dMetal:
            return String(localized: "D3DMetal is enforced for this game by its compatibility profile.")
        case .dxmt:
            return String(localized: "DXMT is enforced for this game by its compatibility profile.")
        case .dxvk:
            return String(localized: "DXVK is enforced for this game by its compatibility profile.")
        case .vkd3d:
            return String(localized: "VKD3D-Proton is enforced for this game by its compatibility profile.")
        case .wineD3D:
            return String(localized: "WineD3D is enforced for this game by its compatibility profile.")
        }
    }
    private var graphicsAPIExplanation: String {
        let api = graphicsAPIBinding.wrappedValue
        if api == .automatic { return String(localized: "Uses the detected DirectX API. Choose a specific API only if the game supports it.") }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach([CompatibilityPreset.recommended, .legacy, .performance]) { preset in
                    Button { action(preset) } label: { Label(preset.title, systemImage: preset.symbol).frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle()) }
                        .buttonStyle(.plain).foregroundStyle(selected == preset ? Color.white : Color.primary)
                        .background(selected == preset ? Color.accentColor : Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(selected == preset ? Color.accentColor : Color.secondary.opacity(0.14)) }
                }
            }
            if selected == .custom {
                Label("Current profile: Custom", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
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

private struct CompatibilityUpscalingRow: View {
    let title: LocalizedStringResource
    let detail: String
    let status: UpscalingDetectionStatus
    let explanation: String

    private var tint: Color {
        switch status {
        case .verified: .green
        case .detected: .blue
        case .candidate: .orange
        case .unavailable: .red
        case .notDetected: .secondary
        }
    }

    private var statusLabel: String {
        switch status {
        case .verified: String(localized: "Verified")
        case .detected: String(localized: "Detected")
        case .candidate: String(localized: "Experimental")
        case .unavailable: String(localized: "Unavailable")
        case .notDetected: String(localized: "Not detected")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text(explanation).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(statusLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
        }
    }
}

private struct InspectorValueRow: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.medium))
                .fontDesign(monospaced ? .monospaced : .default)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct CompatibilityTextFieldRow: View {
    let title: LocalizedStringResource
    let detail: String?
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField(String(localized: title), text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 205)
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

private struct CompatibilityLaunchPlanCard: View {
    let application: WindowsApplication
    let profile: WineCompatibilityProfile
    let gameAPILabel: String
    let runtimeLabel: String?
    let displayLabel: String
    let temporalPath: String?
    let configurationIssue: String?

    private var statusTitle: String {
        if configurationIssue != nil { return String(localized: "Needs attention") }
        if application.status == .running || application.status.isBusy { return String(localized: "Busy") }
        return String(localized: "Ready")
    }

    private var statusTint: Color {
        if configurationIssue != nil { return .orange }
        if application.status == .running || application.status.isBusy { return .blue }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Launch plan").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: configurationIssue == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(statusTint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Configuration status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusTint)
                }
            }
            Divider()
            planRow("Renderer", compatibilityLocalizedBackendName(profile.graphicsBackend), "gearshape.2")
            planRow("Game API", gameAPILabel, "square.3.layers.3d")
            planRow("Runtime", runtimeLabel ?? String(localized: "Automatic"), "shippingbox")
            planRow("Windows", profile.windowsVersion.displayName, "window.ceiling")
            planRow("Prefix", compatibilityLocalizedPrefixModeName(profile.prefixMode ?? .wow64), "externaldrive")
            planRow("Display", displayLabel, "display")
            planRow("Launch", profile.overlayCompatibleFullscreen ? String(localized: "Virtual desktop") : String(localized: "Directly"), "rectangle.on.rectangle")
            if let temporalPath {
                planRow("Upscaling", temporalPath, "arrow.up.left.and.arrow.down.right")
            }
            if let configurationIssue {
                Text(configurationIssue).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.55)) }
    }

    private func planRow(_ title: LocalizedStringResource, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 14)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.caption.weight(.medium)).multilineTextAlignment(.trailing)
        }
    }
}

private struct CompatibilityCommunityCard: View {
    let application: WindowsApplication
    let communityURL: URL?
    let openCommunityReports: () -> Void

    private var rating: CompatibilityRating { application.communityCompatibility?.tier.rating ?? application.compatibility }
    private var tint: Color {
        switch rating {
        case .excellent: .green
        case .good: .teal
        case .limited: .orange
        case .unsupported: .red
        case .unknown: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Community compatibility").font(.headline)
            HStack(spacing: 9) {
                Image(systemName: rating.symbol).foregroundStyle(tint)
                Text(rating.localizedTitle).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            }
            if let compatibility = application.communityCompatibility {
                Text(reportCountLabel(compatibility.reportCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Based on available community reports.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No community compatibility data is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if communityURL != nil {
                Button("View community reports", systemImage: "arrow.up.right.square", action: openCommunityReports)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.55)) }
    }

    private func reportCountLabel(_ count: Int) -> String {
        let noun = count == 1 ? String(localized: "report") : String(localized: "reports")
        return "\(count.formatted()) \(noun)"
    }
}

private struct CompatibilitySettingsFooter: View {
    let restore: () -> Void; let cancel: () -> Void; let save: () -> Void; let saveDisabled: Bool
    let saveTitle: LocalizedStringResource
    let showsRebuildNotice: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsRebuildNotice {
                Label("Environment will be rebuilt. Game files will not be modified.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Restore defaults", systemImage: "arrow.counterclockwise", action: restore)
                Spacer()
                Button("Cancel", action: cancel)
                Button(saveTitle, action: save).buttonStyle(.borderedProminent).disabled(saveDisabled)
            }
        }
        .padding(16)
    }
}

/// Expert-only workspace for temporal upscaling components and injection tools.
/// The compatibility sheet keeps only the requested/effective summary and
/// delegates package operations here so the main launch-plan UI stays focused.
private struct ComponentsAndPatchesView: View {
    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let application: WindowsApplication
    @Binding var profile: WineCompatibilityProfile
    @State private var installedUpscalingBridgeVersion: String?
    @State private var temporalInspector: TemporalUpscalingInspectorSnapshot?
    @State private var isImportingTemporalComponent = false
    @State private var temporalComponentToImport: TemporalComponentID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "shippingbox.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 42, height: 42)
                    .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Components & Patches").font(.title2.weight(.semibold))
                    Text(application.name).foregroundStyle(.secondary)
                    Text("Manage optional upscaling components and game patches.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    spatialUpscalingSection
                    temporalUpscalingSection
                }
                .padding(16)
            }
            Divider()
            HStack {
                Text("Changes to the selected mode are applied when the main compatibility profile is saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 700, idealWidth: 820, maxWidth: 920, minHeight: 620, idealHeight: 760, maxHeight: 900)
        .onAppear { refreshInspector() }
        .task(id: application.environmentID) { refreshInspector() }
        .fileImporter(
            isPresented: $isImportingTemporalComponent,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard let component = temporalComponentToImport else { return }
            temporalComponentToImport = nil
            guard case .success(let urls) = result, let source = urls.first else { return }
            Task {
                await store.importTemporalComponent(component, from: source, for: application.id)
                refreshInspector()
            }
        }
    }

    private var spatialUpscalingSection: some View {
        let capability = SpatialUpscalingResolver.resolve(
            runtimeFeatures: runtimeFeatures,
            backend: resolvedBackend
        )
        return CompatibilitySettingsSection(
            title: "Spatial upscaling",
            subtitle: "Wine Fullscreen FSR 1 is optional and depends on the selected Vulkan graphics path.",
            symbol: "arrow.up.left.and.arrow.down.right",
            tint: .orange
        ) {
            CompatibilityUpscalingRow(
                title: "Wine Fullscreen FSR 1",
                detail: capability.title,
                status: capability.status,
                explanation: capability.detail
            )
            CompatibilityToggleRow(
                title: "Enable spatial upscaling",
                detail: "The request becomes active only when the runtime and renderer are verified.",
                isOn: $profile.fullscreenFSREnabled
            )
            if fullscreenFSRCapabilities.supportsMode {
                CompatibilityPickerRow(title: "FSR preset", detail: "Controls the render resolution used by the fullscreen FSR patch.") {
                    Picker("FSR preset", selection: $profile.fullscreenFSRMode) {
                        ForEach(FullscreenFSRMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .disabled(!profile.fullscreenFSREnabled)
                }
            }
            if let reason = fullscreenFSRUnavailableReason {
                CompatibilityCallout(text: reason, symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
        }
    }

    private var temporalUpscalingSection: some View {
        let game = temporalInspector?.game
        let plan = temporalInspector?.temporalPlan
        return CompatibilitySettingsSection(
            title: "Temporal upscaling",
            subtitle: "Components are immutable, versioned, and validated before injection.",
            symbol: "waveform.path.ecg",
            tint: .purple
        ) {
            CompatibilityUpscalingRow(
                title: "Detected game interface",
                detail: game.map { detectedTemporalInterfaceLabel($0) } ?? String(localized: "Analyzing game files…"),
                status: game.map { $0.hasTemporalInterface ? .detected : .notDetected } ?? .candidate,
                explanation: game.map { temporalInterfaceExplanation($0) } ?? String(localized: "No game files have been analyzed yet.")
            )
            CompatibilityPickerRow(
                title: "Temporal upscaling mode",
                detail: "Automatic follows real detection data. Manual bridges remain experimental until a live smoke test verifies them."
            ) {
                Picker("Temporal upscaling mode", selection: temporalModeBinding) {
                    ForEach(TemporalUpscalingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
            }
            CompatibilityUpscalingRow(
                title: "Effective temporal path",
                detail: plan?.effective.displayName ?? String(localized: "Unavailable"),
                status: temporalStatus(plan?.compatibility),
                explanation: plan?.reason ?? String(localized: "The selected runtime or game capability is unavailable.")
            )
            CompatibilityUpscalingRow(
                title: "NGX → MetalFX bridge",
                detail: bridgeDetail,
                status: bridgeStatus,
                explanation: bridgeExplanation
            )
            if temporalInspector?.metalFX.available == true {
                HStack {
                    Text(installedUpscalingBridgeVersion == nil ? String(localized: "Bridge component not installed") : String(localized: "Bridge component installed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(installedUpscalingBridgeVersion == nil ? String(localized: "Install bridge") : String(localized: "Refresh bridge"), systemImage: "arrow.down.circle") {
                        Task {
                            await store.installUpscalingBridge(.ngxToMetalFX, for: application.id)
                            refreshInspector()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.runtimeOperationDetail != nil || application.status == .running || application.status.isBusy || resolvedBackend != .d3dMetal)
                }
            }
            temporalComponentRow(title: "DLSSTweaks", status: temporalInspector?.dlsstweaks, component: .dlsstweaks)
            temporalComponentRow(title: "OptiScaler", status: temporalInspector?.optiScaler, component: .optiScaler)
            temporalComponentRow(title: "DLSS Runtime", status: temporalInspector?.managedDLSSRuntime, component: .dlssRuntime)
            if let inspector = temporalInspector {
                HStack(spacing: 8) {
                    Text(inspector.dlssRuntime?.source == .borealManaged
                        ? String(localized: "Managed DLSS runtime is active")
                        : (inspector.dlssRuntime == nil
                            ? String(localized: "No active DLSS runtime detected")
                            : String(localized: "Game-original DLSS runtime is active")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use managed") {
                        Task {
                            await store.installManagedDLSSRuntime(for: application.id)
                            refreshInspector()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!inspector.managedDLSSRuntime.installed || inspector.dlssRuntime?.source == .borealManaged || application.status == .running || application.status.isBusy)
                    Button("Restore original") {
                        Task {
                            await store.restoreManagedDLSSRuntime(for: application.id)
                            refreshInspector()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(inspector.dlssRuntime?.source != .borealManaged || application.status == .running || application.status.isBusy)
                }
            }
            if let plan, plan.injectionSafety != .allowed {
                CompatibilityCallout(
                    text: plan.injectionSafety == .blockedAntiCheat
                        ? String(localized: "External DLL injection is disabled for this game because anti-cheat or integrity protection may be active.")
                        : String(localized: "External DLL injection requires an explicit user action because this game's policy is unknown."),
                    symbol: "shield.lefthalf.filled",
                    tint: .orange
                )
            }
            if application.usesSharedSteamEnvironment {
                CompatibilityCallout(text: String(localized: "Steam uses a shared Windows environment. Registry and injected DLL changes can affect more than one game."), symbol: "person.2.fill", tint: .blue)
            }
            if let inspector = temporalInspector {
                DisclosureGroup("DLSS / NGX Inspector") { inspectorContent(inspector) }
            }
        }
    }

    private var runtimeFeatures: RuntimeFeatures? {
        if let runtimeID = profile.runtimeIDOverride,
           let runtime = store.runtimeStatuses.first(where: { $0.id == runtimeID && $0.source == .installed }) {
            return runtime.features
        }
        return store.compatibilityRuntimeFeatures(for: application, backend: profile.graphicsBackend)
    }

    private var fullscreenFSRCapabilities: FullscreenFSRCapabilities {
        runtimeFeatures?.fullscreenFSRCapabilities
            ?? FullscreenFSRCapabilities(available: runtimeFeatures?.fullscreenFSR == true, source: .payloadInspection)
    }

    private var resolvedBackend: GraphicsBackend {
        switch profile.graphicsBackend {
        case .automatic:
            let api = profile.graphicsAPI ?? .automatic
            if runtimeFeatures?.d3dmetal == true, (api == .directX11 || api == .directX12) { return .d3dMetal }
            if runtimeFeatures?.dxvk == true, api != .directX12 { return .dxvk }
            if runtimeFeatures?.vkd3d == true, api == .directX12 { return .vkd3d }
            if runtimeFeatures?.dxmt == true { return .dxmt }
            return .wineD3D
        default: return profile.graphicsBackend
        }
    }

    private var fullscreenFSRStackSupportLevel: FullscreenFSRSupportLevel {
        runtimeFeatures?.graphicsCapabilities?[resolvedBackend.rawValue]?.fullscreenFSRSupport
            ?? GraphicsStackCatalog.stack(for: resolvedBackend)?.fullscreenFSRSupportLevel
            ?? .unsupported
    }

    private var fullscreenFSRUnavailableReason: String? {
        guard profile.fullscreenFSREnabled else { return nil }
        if !fullscreenFSRCapabilities.available { return String(localized: "Unavailable with the selected runtime.") }
        if fullscreenFSRCapabilities.confidence != .verified { return String(localized: "Detected in the selected runtime, but not verified by a macOS fullscreen smoke test.") }
        if fullscreenFSRStackSupportLevel == .unsupported { return String(localized: "Unavailable with the current renderer. Wine fullscreen FSR requires a Vulkan-based DXVK or VKD3D-Proton stack.") }
        if fullscreenFSRStackSupportLevel != .verified { return String(localized: "The current renderer is a candidate for Wine fullscreen FSR, but this runtime graphics path is not verified on macOS.") }
        if profile.overlayCompatibleFullscreen { return String(localized: "Unavailable while Boreal overlay fullscreen is enabled. Disable the overlay-compatible fullscreen mode to use Wine fullscreen FSR.") }
        return nil
    }

    private var temporalModeBinding: Binding<TemporalUpscalingMode> {
        Binding(
            get: {
                if profile.temporalUpscaling.mode == .automatic, profile.upscalingBridge == .ngxToMetalFX { return .metalFXBridge }
                return profile.temporalUpscaling.mode
            },
            set: {
                profile.temporalUpscaling.mode = $0
                profile.upscalingBridge = $0 == .metalFXBridge ? .ngxToMetalFX : .none
            }
        )
    }

    private func detectedTemporalInterfaceLabel(_ game: GameUpscalingCapabilities) -> String {
        guard !game.detectedTemporalInterfaces.isEmpty else { return String(localized: "None detected") }
        return game.detectedTemporalInterfaces.map { "\($0.kind.displayName) · \($0.version ?? String(localized: "Unknown version"))" }.joined(separator: ", ")
    }

    private func temporalInterfaceExplanation(_ game: GameUpscalingCapabilities) -> String {
        guard !game.detectedTemporalInterfaces.isEmpty else { return String(localized: "No DLSS, FSR 2+ or XeSS interface was detected in the game files.") }
        return game.detectedTemporalInterfaces.map { "\($0.kind.displayName): \($0.confidence.rawValue) confidence; runtime operation is not proven." }.joined(separator: " ")
    }

    private func temporalStatus(_ compatibility: TemporalBridgeCompatibility?) -> UpscalingDetectionStatus {
        guard let compatibility else { return .candidate }
        switch compatibility {
        case .unsupported: return .unavailable
        case .candidate, .experimental: return .candidate
        case .verified: return .verified
        }
    }

    private var bridgeDetail: String {
        guard let inspector = temporalInspector else { return String(localized: "Analyzing selected runtime…") }
        if inspector.metalFX.installed { return String(localized: "Installed from selected GPTK runtime") }
        if inspector.metalFX.available { return String(localized: "Available in selected GPTK runtime") }
        return String(localized: "Not detected in selected runtime")
    }

    private var bridgeStatus: UpscalingDetectionStatus {
        guard let inspector = temporalInspector else { return .candidate }
        if inspector.metalFX.installed { return .detected }
        return inspector.metalFX.available ? .candidate : .unavailable
    }

    private var bridgeExplanation: String {
        guard let inspector = temporalInspector else { return String(localized: "The selected runtime is still being inspected.") }
        if inspector.metalFX.installed { return String(localized: "Managed ComponentStore copy is available; this macOS game path is not live verified.") }
        if inspector.metalFX.available { return String(localized: "Runtime payload detected; install the managed bridge copy before selecting this path.") }
        return String(localized: "Boreal did not find the bridge payload in this immutable runtime.")
    }

    @ViewBuilder
    private func temporalComponentRow(title: LocalizedStringResource, status: TemporalComponentStatus?, component: TemporalComponentID) -> some View {
        let installed = status?.installed == true
        let explanation: String = if component == .optiScaler {
            installed ? String(localized: "Versioned and hash-validated; selecting a release folder installs it next to the game executable.") : String(localized: "Select a compiled OptiScaler release folder; Boreal copies its payload and installs dxgi.dll next to the game executable.")
        } else {
            installed ? String(localized: "Versioned and hash-validated before a game injection is attempted.") : String(localized: "Import a user-supplied component folder; Boreal will store it immutably and record its SHA-256.")
        }
        let importLabel: String = if component == .optiScaler {
            installed ? String(localized: "Reinstall") : String(localized: "Install")
        } else {
            installed ? String(localized: "Re-import") : String(localized: "Import")
        }
        HStack(alignment: .top, spacing: 10) {
            CompatibilityUpscalingRow(
                title: title,
                detail: installed ? "\(status?.version ?? String(localized: "Unknown version")) · \(String(localized: "managed ComponentStore"))" : String(localized: "Not installed"),
                status: installed ? .detected : .notDetected,
                explanation: explanation
            )
            Spacer(minLength: 4)
            Button(importLabel, systemImage: "square.and.arrow.down") {
                temporalComponentToImport = component
                isImportingTemporalComponent = true
            }
            .buttonStyle(.bordered)
            if component == .dlsstweaks, installed, temporalInspector?.dlsstweaksCapabilities?.injectionFiles.isEmpty == false {
                Button("Inject", systemImage: "arrow.down.to.line") {
                    Task { await store.injectDLSSTweaks(for: application.id); refreshInspector() }
                }
                .buttonStyle(.bordered)
                .disabled(application.status == .running || application.status.isBusy)
            }
            if component == .optiScaler, installed {
                Button("Inject", systemImage: "arrow.down.to.line") {
                    Task { await store.injectOptiScaler(for: application.id); refreshInspector() }
                }
                .buttonStyle(.bordered)
                .disabled(application.status == .running || application.status.isBusy)
            }
        }
    }

    @ViewBuilder
    private func inspectorContent(_ inspector: TemporalUpscalingInspectorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            InspectorValueRow(title: "Game interface", value: detectedTemporalInterfaceLabel(inspector.game))
            InspectorValueRow(title: "Detected DLL", value: inspector.dlssRuntime?.activeFileURL.lastPathComponent ?? String(localized: "Not detected"))
            InspectorValueRow(title: "Version", value: inspector.dlssRuntime?.detectedVersion ?? String(localized: "Unknown"))
            InspectorValueRow(title: "Source", value: inspector.dlssRuntime.map { $0.source == .gameOriginal ? String(localized: "Game installation") : String(localized: "Boreal managed") } ?? String(localized: "Unavailable"))
            InspectorValueRow(title: "Native DLSS availability", value: inspector.game.dlss?.detected == true ? String(localized: "Detected") : String(localized: "Not detected"))
            InspectorValueRow(title: "SHA-256", value: inspector.dlssRuntime?.activeSHA256 ?? String(localized: "Unavailable"), monospaced: true)
            InspectorValueRow(title: "DLSSTweaks", value: inspector.dlsstweaks.version ?? String(localized: "Not installed"))
            InspectorValueRow(title: "DLSSTweaks controls", value: inspector.dlsstweaksCapabilities?.supportedControls.map(\.rawValue).sorted().joined(separator: ", ") ?? String(localized: "Not declared by component"))
            InspectorValueRow(title: "OptiScaler", value: inspector.optiScaler.version ?? String(localized: "Not installed"))
            InspectorValueRow(title: "MetalFX bridge", value: inspector.metalFX.available ? String(localized: "Available in runtime") : String(localized: "Unsupported / not detected"))
            InspectorValueRow(title: "Graphics stack", value: inspector.graphicsStack.backend.displayName)
            InspectorValueRow(title: "Runtime", value: inspector.runtimeDescription)
            InspectorValueRow(title: "Effective temporal path", value: inspector.temporalPlan.effective.displayName)
            InspectorValueRow(title: "Status", value: inspector.temporalPlan.compatibility.label)
            InspectorValueRow(title: "Injection policy", value: inspector.temporalPlan.injectionSafety.rawValue)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DLSS Debug Indicator").fontWeight(.medium)
                    Text("Shows NVIDIA NGX/DLSS diagnostic information when supported by the game/runtime.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("DLSS Debug Indicator", isOn: Binding(
                    get: { inspector.ngxDebugIndicator.enabled == true },
                    set: { enabled in Task { await store.setNGXDebugIndicator(enabled, for: application.id); refreshInspector() } }
                ))
                .labelsHidden()
                .disabled(!inspector.ngxDebugIndicator.available)
            }
            if !inspector.ngxDebugIndicator.available { Text(inspector.ngxDebugIndicator.detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.top, 6)
    }

    private func refreshInspector() {
        Task {
            installedUpscalingBridgeVersion = await store.installedUpscalingBridgeVersion(for: application, bridge: .ngxToMetalFX)
            temporalInspector = await store.temporalUpscalingInspector(for: application.id)
        }
    }
}
