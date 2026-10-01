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
    case recommended, compatibility, performance, custom
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .recommended: "Recommended"
        case .compatibility: "Compatibility"
        case .performance: "Performance"
        case .custom: "Custom"
        }
    }
    var symbol: String {
        switch self {
        case .recommended: "wand.and.stars"
        case .compatibility: "checkmark.shield"
        case .performance: "gauge.with.dots.needle.67percent"
        case .custom: "gearshape"
        }
    }
}

private enum LegacyGraphicsTestProfile: String, CaseIterable, Identifiable {
    case wineD3D
    case dd7to9
    case dgVoodooWineD3D
    case dgVoodooDXMT
    case borealLegacyGraphicsDXMT
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .wineD3D: "A · Wine DDraw / WineD3D"
        case .dd7to9: "B · Dd7to9 / WineD3D D3D9"
        case .dgVoodooWineD3D: "C · dgVoodoo2 / WineD3D D3D11"
        case .dgVoodooDXMT: "D · dgVoodoo2 / DXMT Metal D3D11"
        case .borealLegacyGraphicsDXMT: "E · Boreal Legacy Graphics / DXMT Metal D3D11"
        case .manual: "Manual configuration"
        }
    }

    var detail: String {
        switch self {
        case .wineD3D: "Native DirectDraw/Direct3D 7 path with Wine's OpenGL renderer."
        case .dd7to9: "Converts DirectDraw/Direct3D 7 to D3D9 through Dd7to9."
        case .dgVoodooWineD3D: "Converts DirectDraw/Direct3D 7 to D3D11, then uses WineD3D."
        case .dgVoodooDXMT: "Converts DirectDraw/Direct3D 7 to D3D11, then uses DXMT/Metal."
        case .borealLegacyGraphicsDXMT: "Routes Sacred's DirectDraw/Direct3D 7 calls through Boreal's traced D3D11 bridge and DXMT/Metal."
        case .manual: "Keep the current individual compatibility selections."
        }
    }

    func applying(to value: WineCompatibilityProfile) -> WineCompatibilityProfile {
        var result = value
        switch self {
        case .wineD3D:
            result.legacyWrapper = .none
            result.legacyGraphicsAPI = .directDraw
            result.graphicsAPI = .automatic
            result.graphicsBackend = .wineD3D
        case .dd7to9:
            result.legacyWrapper = .dd7to9
            result.legacyGraphicsAPI = .directDraw
            result.graphicsAPI = .directX9
            result.graphicsBackend = .wineD3D
        case .dgVoodooWineD3D:
            result.legacyWrapper = .dgVoodoo2
            result.legacyGraphicsAPI = .directDraw
            result.graphicsAPI = .directX11
            result.graphicsBackend = .wineD3D
        case .dgVoodooDXMT:
            result.legacyWrapper = .dgVoodoo2
            result.legacyGraphicsAPI = .directDraw
            result.graphicsAPI = .directX11
            result.graphicsBackend = .dxmt
        case .borealLegacyGraphicsDXMT:
            result.legacyWrapper = .borealLegacyGraphics
            result.legacyGraphicsAPI = .directDraw
            result.graphicsAPI = .directX11
            result.graphicsBackend = .dxmt
        case .manual:
            break
        }
        return result
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let application: WindowsApplication
    @State private var profile: WineCompatibilityProfile
    @State private var controllerManager = ControllerManager.shared
    @State private var showsComponentsPatches = false
    @State private var showsControllerSettings = false
    @State private var showsAdvancedSettings = false
    @State private var isApplying = false
    @State private var saveError: String?
    @State private var temporalInspector: TemporalUpscalingInspectorSnapshot?
    @State private var environmentPrefixMode: WinePrefixMode?
    @AppStorage("developerMode") private var developerMode = false

    private var motion: BorealMotionEnvironment {
        BorealMotionEnvironment(reduceMotion: reduceMotion)
    }

    init(application: WindowsApplication) {
        self.application = application
        _profile = State(initialValue: application.compatibilityProfile ?? application.resolvedCompatibilityProfile)
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
                saveDisabled: currentApplication.status == .running || currentApplication.status.isBusy || isApplying || prefixModeIssue != nil,
                saveTitle: requiresEnvironmentRebuild ? "Apply & Rebuild" : "Save changes",
                impacts: changeImpacts,
                isApplying: isApplying,
                applyingMessage: currentApplication.lastResult,
                errorMessage: saveError
            )
        }
        .frame(minWidth: 680, idealWidth: 840, maxWidth: 900, minHeight: 620, idealHeight: 760, maxHeight: 860)
        .onAppear {
            profile = store.compatibilityProfile(for: application)
            controllerManager.start()
        }
        .sheet(isPresented: $showsControllerSettings) { NavigationStack { ControllerSettingsView() } }
        .sheet(isPresented: $showsComponentsPatches, onDismiss: {
            Task { temporalInspector = await store.temporalUpscalingInspector(for: application.id) }
        }) {
            ComponentsAndPatchesView(application: application, profile: $profile)
        }
        .sheet(isPresented: $showsAdvancedSettings) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        displaySection
                        upscalingSection
                        frameGenerationSection
                        overlaySection
                        controllerSection
                        advancedSection
                    }
                    .padding(16)
                }
                .navigationTitle("Advanced compatibility")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsAdvancedSettings = false }
                    }
                }
            }
            .frame(minWidth: 620, idealWidth: 720, minHeight: 600, idealHeight: 760)
        }
        .onReceive(NotificationCenter.default.publisher(for: .borealRuntimeImportCompleted)) { _ in
            Task { temporalInspector = await store.temporalUpscalingInspector(for: application.id) }
        }
        .task(id: application.environmentID) {
            environmentPrefixMode = store.configuredPrefixMode(for: currentApplication)
            temporalInspector = await store.temporalUpscalingInspector(for: application.id)
        }
        .onChange(of: currentApplication.status) { _, status in
            guard isApplying, !status.isBusy else { return }
            isApplying = false
            if status == .ready, currentApplication.lastErrorDetail == nil {
                dismiss()
            } else {
                saveError = currentApplication.lastErrorDetail
                    ?? currentApplication.lastResult
                    ?? String(localized: "Boreal could not apply these compatibility changes.")
            }
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 12) {
            graphicsSection
            launchOverviewSection
            graphicsOverviewSection
            compatibilityOverviewSection
            Button("Advanced settings…", systemImage: "slider.horizontal.3") {
                showsAdvancedSettings = true
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var graphicsSection: some View {
        CompatibilitySettingsSection(title: "Graphics", subtitle: "Configure how the game runs using Wine and graphics settings.", symbol: "gearshape.2", tint: .blue) {
            CompatibilityPickerRow(title: "Runtime / environment", detail: String(localized: "Automatic lets Boreal choose a compatible runtime. Select a specific installed environment here to pin it for this game.")) {
                Picker("Runtime / environment", selection: $profile.runtimeIDOverride) {
                    Text("Automatic").tag(Optional<String>.none)
                    ForEach(availableRuntimes) { runtime in
                        Text(runtimeLabel(runtime))
                            .tag(Optional(runtime.id))
                    }
                }
                .labelsHidden()
                .disabled(isSettingManaged(.runtimeSelection))
            }
            if profile.runtimeIDOverride != nil {
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
                    profile.runtimeIDOverride = nil
                }
                .buttonStyle(.bordered)
                .disabled(isSettingManaged(.runtimeSelection))
            }
            CompatibilityPickerRow(title: "Game API", detail: graphicsAPIExplanation) {
                Picker("Game API", selection: graphicsAPIBinding) {
                    Text("Automatic").tag(GraphicsAPI.automatic)
                    ForEach(selectableGraphicsAPIs) { api in
                        Text(compatibilityLocalizedGraphicsAPIName(api)).tag(api)
                    }
                }
                .labelsHidden()
            }
            CompatibilityPickerRow(title: "Graphics renderer", detail: graphicsBackendExplanation) {
                Picker("Graphics renderer", selection: $profile.graphicsBackend) {
                    ForEach(WineGraphicsBackend.allCases) { backend in Text(backendLabel(backend)).tag(backend) }
                }
                .labelsHidden()
                .disabled(isSettingManaged(.graphicsRenderer))
            }
            Group {
                if profile.graphicsBackend == .wineD3D || graphicsBackendIssue != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if profile.graphicsBackend == .wineD3D {
                            CompatibilityPickerRow(
                                title: "WineD3D renderer",
                                detail: String(localized: "OpenGL is the compatibility path for older games. Vulkan can be faster, but requires working MoltenVK features for the selected game.")
                            ) {
                                Picker("WineD3D renderer", selection: $profile.wineD3DRenderer) {
                                    ForEach(WineD3DRenderer.allCases) { renderer in
                                        Text(renderer.displayName).tag(renderer)
                                    }
                                }
                                .labelsHidden()
                                .disabled(isSettingManaged(.wineD3DRenderer))
                            }
                        }
                        if let issue = graphicsBackendIssue {
                            CompatibilityCallout(text: issue, symbol: "exclamationmark.triangle.fill", tint: .orange)
                            if profile.graphicsBackend != .automatic {
                                Button("Use automatic renderer", systemImage: "wand.and.stars") {
                                    profile.graphicsBackend = .automatic
                                }
                                .buttonStyle(.bordered)
                                .disabled(isSettingManaged(.graphicsRenderer))
                            }
                            if profile.graphicsBackend == .d3dMetal {
                                Button("Manage runtimes…", systemImage: "shippingbox") { openRuntimeManager() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(motion.panel, value: profile.graphicsBackend)
            if let event = application.compatibilityFallbackEvents?.last {
                CompatibilityCallout(
                    text: String(localized: "Boreal switched from \(compatibilityLocalizedBackendName(event.failedBackend)) to \(compatibilityLocalizedBackendName(event.fallbackBackend)) after a Direct3D device initialization failure."),
                    symbol: "arrow.triangle.2.circlepath",
                    tint: .orange
                )
            }
            if usesSharedSteamEnvironment {
                CompatibilityCallout(text: String(localized: "Steam shares its Wine environment across games. Runtime, prefix, and environment-wide renderer settings are read-only here; launch and game-file settings remain per game."), symbol: "person.2.fill", tint: .blue)
            }
        }
    }

    private var launchOverviewSection: some View {
        CompatibilitySettingsSection(title: "Launch", subtitle: "Choose how Boreal opens this game.", symbol: "play.rectangle", tint: .cyan) {
            CompatibilityPickerRow(title: "Start game", detail: launchModeExplanation) {
                Picker("Start game", selection: gameLaunchModeBinding) {
                    ForEach(GameLaunchMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if profile.overlayCompatibleFullscreen {
                Text("Runs in Boreal's virtual desktop so the overlay can stay available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var graphicsOverviewSection: some View {
        CompatibilitySettingsSection(title: "Graphics quality", subtitle: "Common visual settings. Unsupported paths stay visibly unavailable.", symbol: "sparkles", tint: .orange) {
            CompatibilityPickerRow(title: "Upscaling mode", detail: nil) {
                Picker("Upscaling mode", selection: temporalModeBinding) {
                    ForEach(TemporalUpscalingMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                }
                .labelsHidden()
            }
            CompatibilityToggleRow(
                title: "High-resolution rendering (Retina)",
                detail: "Render at higher resolution for a sharper image.",
                isOn: $profile.retinaModeEnabled,
                disabled: isSettingManaged(.retinaMode) && !profile.retinaModeEnabled
            )
            CompatibilityToggleRow(
                title: "Wine Fullscreen FSR 1",
                detail: "Uses Wine's spatial upscaler on a verified compatible graphics path.",
                isOn: $profile.fullscreenFSREnabled,
                disabled: isSettingManaged(.spatialUpscaling) && !profile.fullscreenFSREnabled,
                detailText: fullscreenFSRUnavailableReason
            )
            CompatibilityToggleRow(
                title: "Frame generation",
                detail: temporalInspector?.optiScaler.installed == true
                    ? "Uses the installed per-game OptiScaler component."
                    : "Requires a compiled OptiScaler component; manage it in Advanced settings.",
                isOn: optiScalerFrameGenerationBinding,
                disabled: temporalInspector?.optiScaler.installed != true
                    && !profile.temporalUpscaling.optiScaler.frameGenerationEnabled
            )
        }
    }

    private var compatibilityOverviewSection: some View {
        CompatibilitySettingsSection(title: "Compatibility", subtitle: "Boreal resolves dependencies from game evidence and the selected environment.", symbol: "checkmark.shield", tint: .purple) {
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
                    .disabled(
                        !profile.forceXInput
                            && (isSettingManaged(.controllerMapping) || runtimeFeatures?.wineBusControllerMapping != true)
                    )
            }
            Text(dependencySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if usesSharedSteamEnvironment {
                CompatibilityCallout(text: String(localized: "This game uses Steam's shared environment. The controller and dependency details are shown here; environment-wide changes are managed by that shared prefix."), symbol: "person.2.fill", tint: .blue)
            }
        }
    }

    private var displaySection: some View {
        CompatibilitySettingsSection(title: "Display", subtitle: "Configure display resolution, scaling, and window behavior.", symbol: "display", tint: .blue) {
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
            CompatibilityUpscalingRow(
                title: "Wine Fullscreen FSR 1",
                detail: compatibilityLocalizedCapabilityTitle(spatialCapability),
                status: spatialCapability.status,
                explanation: compatibilityLocalizedCapabilityDetail(spatialCapability)
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

    private var frameGenerationSection: some View {
        let plan = temporalInspector?.temporalPlan
        let optiInstalled = temporalInspector?.optiScaler.installed == true
        let optiPatcherInstalled = temporalInspector?.optiScaler.includesOptiPatcher == true
        return CompatibilitySettingsSection(
            title: "Frame generation",
            subtitle: "OptiFG runs inside the game's DirectX 12 process; Boreal does not capture the window or create an overlay.",
            symbol: "sparkles.rectangle.stack",
            tint: .purple
        ) {
            CompatibilityPickerRow(
                title: "Technology",
                detail: "The first managed backend supports OptiFG with FSR Frame Generation."
            ) {
                Text("OptiFG — FSR Frame Generation")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            CompatibilityPickerRow(
                title: "Input",
                detail: "Automatic selects the temporal upscaler input required by OptiFG."
            ) {
                Text(profile.temporalUpscaling.optiScaler.frameGeneration.input.displayName)
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            CompatibilityPickerRow(
                title: "HUD handling",
                detail: "HUD-less resource detection is game-dependent."
            ) {
                Picker("HUD handling", selection: $profile.temporalUpscaling.optiScaler.frameGeneration.hudHandling) {
                    ForEach(OptiScalerHUDHandling.allCases) { handling in
                        Text(handling.displayName).tag(handling)
                    }
                }
                .labelsHidden()
            }
            CompatibilityUpscalingRow(
                title: "Status",
                detail: plan?.compatibility.label ?? String(localized: "Analyzing selected runtime…"),
                status: temporalStatus(plan?.compatibility),
                explanation: plan.map(frameGenerationPlanExplanation) ?? String(localized: "Select and install a compiled OptiScaler component for this game.")
            )
            if !optiInstalled {
                CompatibilityCallout(
                    text: String(localized: "OptiFG requires a compiled OptiScaler.dll component. The OptiScaler project source folder cannot be injected as a runtime component."),
                    symbol: "shippingbox",
                    tint: .orange
                )
            }
            if let game = temporalInspector?.game,
               !game.hasTemporalInterface,
               GameLaunchCompatibility.supportsDLSSUnlocker(for: application),
               !optiPatcherInstalled {
                CompatibilityCallout(
                    text: String(localized: "GTA SA:DE requires the DLSS Unlocker/OptiPatcher input before OptiFG can be used."),
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
            if let plan, case .unsupported = plan.compatibility {
                CompatibilityCallout(
                    text: frameGenerationPlanExplanation(plan),
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
    }

    private var overlaySection: some View {
        CompatibilitySettingsSection(title: "Launch mode", subtitle: "Choose how Wine creates the game window.", symbol: "rectangle.on.rectangle", tint: .cyan) {
            Label(profile.overlayCompatibleFullscreen ? "Virtual desktop" : "Direct launch", systemImage: profile.overlayCompatibleFullscreen ? "rectangle.on.rectangle" : "arrow.up.right.square")
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(profile.forceXInput ? "Enabled" : "Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        Picker("Windows version", selection: $profile.windowsVersion) { ForEach(WineWindowsVersion.allCases) { Text($0.displayName).tag($0) } }.labelsHidden().disabled(isSettingManaged(.windowsVersion))
                    }
                    CompatibilityPickerRow(title: "Windows executable architecture", detail: String(localized: "This describes the selected Windows executable. It is separate from the Wine prefix mode.")) {
                        Picker("Windows executable architecture", selection: $profile.architecture) { ForEach(WinePrefixArchitecture.allCases) { Text(executableArchitectureLabel($0)).tag($0) } }.labelsHidden().disabled(isSettingManaged(.executableArchitecture))
                    }
                    CompatibilityPickerRow(title: "Wine prefix", detail: prefixModeExplanation) {
                        Picker("Wine prefix", selection: prefixModeBinding) {
                            ForEach(WinePrefixMode.allCases) { mode in
                                Text(prefixModeLabel(mode)).tag(mode).disabled(prefixModeIssue(for: mode) != nil)
                            }
                        }
                        .labelsHidden()
                        .disabled(isSettingManaged(.prefixMode))
                    }
                    if let prefixModeIssue {
                        CompatibilityCallout(text: prefixModeIssue, symbol: "exclamationmark.triangle.fill", tint: .orange)
                    }
                }.padding(.top, 8)
            }
            DisclosureGroup("Legacy compatibility") {
                VStack(spacing: 10) {
                    CompatibilityPickerRow(title: "Compatibility fix", detail: nil) {
                        Picker("Compatibility fix", selection: $profile.legacyWrapper) {
                            ForEach(LegacyGraphicsWrapper.allCases) { wrapper in
                                Text(compatibilityLocalizedLegacyWrapperName(wrapper))
                                    .tag(wrapper)
                                    .disabled(wrapper != .none && !legacyWrapperAvailable(wrapper))
                            }
                        }
                        .labelsHidden()
                        .disabled(isSettingManaged(.legacyWrapper))
                    }
                    if let legacyWrapperAvailabilityMessage {
                        CompatibilityCallout(text: legacyWrapperAvailabilityMessage, symbol: "exclamationmark.triangle.fill", tint: .orange)
                    }
                    CompatibilityPickerRow(
                        title: "Legacy graphics test profile",
                        detail: selectedLegacyTestProfile.detail
                    ) {
                        Picker("Legacy graphics test profile", selection: legacyTestProfileBinding) {
                            ForEach(LegacyGraphicsTestProfile.allCases) { testProfile in
                                Text(testProfile.title)
                                    .tag(testProfile)
                                    .disabled(!legacyTestProfileAvailable(testProfile))
                            }
                        }
                        .labelsHidden()
                    }
                    if profile.legacyWrapper != .none {
                        CompatibilityPickerRow(title: "Older graphics API", detail: legacyWrapperDetail) {
                            Picker("Older graphics API", selection: $profile.legacyGraphicsAPI) { ForEach(LegacyGraphicsAPI.allCases) { Text($0.displayName).tag($0) } }.labelsHidden()
                        }
                    } else {
                        Text("For older games that use DirectDraw or early Direct3D. Leave disabled unless needed.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if developerMode {
                        LegacyWrapperDecisionCard(decision: legacyWrapperDecision)
                    }
                }.padding(.top, 8)
            }
            DisclosureGroup("Performance") {
                VStack(spacing: 10) {
                    CompatibilityToggleRow(title: "ESync", detail: "Reduces synchronization overhead when supported by the selected Wine runtime.", isOn: synchronizationBinding(\.esyncEnabled, supported: runtimeFeatures?.esync == true), disabled: isSettingManaged(.synchronization) || runtimeFeatures?.esync != true)
                    CompatibilityToggleRow(title: "MSync", detail: "Uses Mach semaphores on macOS. Takes priority over ESync when both are enabled.", isOn: synchronizationBinding(\.msyncEnabled, supported: runtimeFeatures?.msync == true), disabled: isSettingManaged(.synchronization) || runtimeFeatures?.msync != true)
                    if let synchronizationUnavailableDetail {
                        CompatibilityCallout(text: synchronizationUnavailableDetail, symbol: "info.circle.fill", tint: .secondary)
                    }
                    Text("Synchronization changes apply after all Windows processes in this environment have stopped.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            DisclosureGroup("Launch and diagnostics") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Launch arguments", text: $profile.launchArguments, prompt: Text("e.g. -windowed -novsync")).textFieldStyle(.roundedBorder)
                    CompatibilityPickerRow(title: "Wine logging", detail: String(localized: "Full logs can grow quickly. Errors-only keeps Wine error output without enabling every trace channel.")) {
                        Picker("Wine logging", selection: $profile.wineLoggingLevel) {
                            ForEach(WineLoggingLevel.allCases) { level in Text(level.displayName).tag(level) }
                        }
                        .labelsHidden()
                    }
                }.padding(.top, 8)
            }
        }
    }

    private var resultCard: some View {
        CompatibilityLaunchPlanCard(
            application: currentApplication,
            profile: profile,
            gameAPILabel: compatibilityLocalizedGraphicsAPIName(effectiveGraphicsAPI),
            rendererLabel: resolvedRendererSummary,
            prefixLabel: resolvedPrefixSummary,
            runtimeLabel: profile.runtimeIDOverride.flatMap { id in availableRuntimes.first(where: { $0.id == id }).map { runtimeLabel($0) } }
                ?? automaticallySelectedRuntimeLabel,
            displayLabel: selectedDisplayLabel,
            temporalPath: temporalInspector?.temporalPlan.effective.displayName,
            configurationIssue: launchPlanIssue
        )
    }

    private var selectedPreset: CompatibilityPreset {
        if profile == recommendedProfile { return .recommended }
        if profile == compatibilityGoalProfile { return .compatibility }
        if profile == performanceProfile { return .performance }
        return .custom
    }

    private func applyPreset(_ preset: CompatibilityPreset) {
        let pinnedRuntimeID = profile.runtimeIDOverride
        switch preset {
        case .recommended: profile = recommendedProfile
        case .compatibility: profile = compatibilityGoalProfile
        case .performance: profile = performanceProfile
        case .custom: break
        }
        if preset != .custom { profile.runtimeIDOverride = pinnedRuntimeID }
    }

    private func save() {
        guard !isApplying else { return }
        saveError = nil
        store.updateCompatibilityProfile(for: application.id, profile: profile)
        let updated = store.application(id: application.id) ?? application
        guard updated.status.isBusy else {
            dismiss()
            return
        }
        isApplying = true
    }

    private var currentApplication: WindowsApplication {
        store.application(id: application.id) ?? application
    }

    private var artwork: StoreLibraryGame? {
        guard let reference = application.storeReference else { return nil }
        return store.storeGames.first { $0.storeReference == reference }
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
        if !inspector.optiScaler.installed {
            return installed > 0
                ? "\(installed) \(installed == 1 ? "component" : "components") installed · OptiScaler missing"
                : String(localized: "OptiScaler component not installed")
        }
        guard installed > 0 else { return String(localized: "No optional components installed") }
        return "\(installed) \(installed == 1 ? "component" : "components") installed"
    }
    private var dependencySummary: String {
        let overrides = profile.dependencyOverrides.count
        if overrides == 0 {
            return String(localized: "Game dependencies are detected automatically; there are no manual dependency overrides.")
        }
        return String(localized: "\(overrides) explicit dependency override(s). Detected requirements are kept separate from this preference.")
    }
    private func isSettingManaged(_ setting: WineCompatibilitySetting) -> Bool {
        guard currentApplication.usesSharedSteamEnvironment else { return false }
        return setting.scope == .environment || setting.scope == .runtime
    }
    private var changeImpacts: [CompatibilityChangeImpact] {
        let original = store.compatibilityProfile(for: application)
        var impacts: [CompatibilityChangeImpact] = []
        if original.launchArguments != profile.launchArguments
            || original.overlayCompatibleFullscreen != profile.overlayCompatibleFullscreen
            || original.overlayDisplayID != profile.overlayDisplayID
            || original.wineLoggingLevel != profile.wineLoggingLevel
            || original.wineD3DRenderer != profile.wineD3DRenderer {
            impacts.append(.launchOnly)
        }
        if original.forceXInput != profile.forceXInput
            || original.disableSteamInputEquivalent != profile.disableSteamInputEquivalent {
            impacts.append(.sessionRestart)
        }
        if original.windowsVersion != profile.windowsVersion
            || original.graphicsBackend != profile.graphicsBackend
            || original.graphicsAPI != profile.graphicsAPI
            || original.graphicsFallback != profile.graphicsFallback
            || original.esyncEnabled != profile.esyncEnabled
            || original.msyncEnabled != profile.msyncEnabled
            || original.retinaModeEnabled != profile.retinaModeEnabled
            || original.fullscreenFSREnabled != profile.fullscreenFSREnabled
            || original.fullscreenFSRMode != profile.fullscreenFSRMode
            || original.fullscreenFSRStrength != profile.fullscreenFSRStrength
            || original.fullscreenFSRCustomMode != profile.fullscreenFSRCustomMode
            || original.upscalingBridge != profile.upscalingBridge
            || original.temporalUpscaling != profile.temporalUpscaling
            || original.dependencyOverrides != profile.dependencyOverrides
            || original.forceXInput != profile.forceXInput {
            impacts.append(.environmentConfiguration)
        }
        if requiresEnvironmentRebuild { impacts.append(.environmentRebuild) }
        if original.legacyWrapper != profile.legacyWrapper
            || original.legacyGraphicsAPI != profile.legacyGraphicsAPI
            || original.temporalUpscaling != profile.temporalUpscaling {
            impacts.append(.gameFilesModification)
        }
        return impacts
    }
    private var requiresEnvironmentRebuild: Bool {
        let original = store.compatibilityProfile(for: application)
        return original.architecture != profile.architecture
            || original.prefixMode != profile.prefixMode
            || original.runtimeIDOverride != profile.runtimeIDOverride
            || (original.graphicsBackend != profile.graphicsBackend && graphicsBackendIssue != nil)
    }
    private var launchPlanIssue: String? {
        if let issue = graphicsBackendIssue ?? prefixModeIssue ?? selectedRuntimeIssue { return issue }
        if let plan = temporalInspector?.temporalPlan,
           case .unsupported = plan.compatibility {
            return plan.reason
        }
        return fullscreenFSRUnavailableReason
    }
    private var resolvedRendererSummary: String {
        if profile.graphicsBackend != .automatic {
            return compatibilityLocalizedBackendName(profile.graphicsBackend)
        }
        if let preferred = graphicsProfile?.enforcedBackend ?? graphicsProfile?.preferredBackend {
            return "Automatic · \(compatibilityLocalizedBackendName(preferred))"
        }
        let actual = currentApplication.graphics
        return actual.isEmpty ? String(localized: "Automatic") : "Automatic · \(actual)"
    }
    private var resolvedPrefixSummary: String {
        if let selected = profile.prefixMode { return compatibilityLocalizedPrefixModeName(selected) }
        guard let environmentPrefixMode else { return String(localized: "Automatic") }
        return "Automatic · \(compatibilityLocalizedPrefixModeName(environmentPrefixMode))"
    }
    private func openRuntimeManager() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .borealOpenRuntimeSettings, object: nil)
        }
    }
    private var prefixModeBinding: Binding<WinePrefixMode> {
        Binding(
            get: { profile.prefixMode ?? environmentPrefixMode ?? .wow64 },
            set: { profile.prefixMode = $0 }
        )
    }
    private func executableArchitectureLabel(_ architecture: WinePrefixArchitecture) -> String {
        architecture == .win32 ? "32-bit (x86)" : "64-bit (x64)"
    }
    private func prefixModeLabel(_ mode: WinePrefixMode) -> String {
        guard prefixModeIssue(for: mode) == nil else {
            return compatibilityLocalizedPrefixModeName(mode) + " · " + String(localized: "Unavailable")
        }
        return compatibilityLocalizedPrefixModeName(mode)
    }
    private func prefixModeIssue(for mode: WinePrefixMode) -> String? {
        if let runtimeID = profile.runtimeIDOverride {
            var candidate = profile
            candidate.prefixMode = mode
            return store.runtimeSelectionIssue(runtimeID, profile: candidate, for: currentApplication)
        }
        return store.prefixModeIssue(mode, for: currentApplication)
    }
    private var prefixModeExplanation: String {
        let mode = profile.prefixMode ?? environmentPrefixMode ?? .wow64
        return switch mode {
        case .wow64:
            String(localized: "Modern combined prefix. WINEARCH is left unset and both 32-bit and 64-bit processes can run in one environment.")
        case .legacyWin32:
            String(localized: "Classic 32-bit prefix. Uses WINEARCH=win32 and requires a runtime that supports legacy prefixes.")
        case .legacyWin64:
            String(localized: "Classic 64-bit prefix. Uses WINEARCH=win64 and requires a runtime that supports legacy prefixes.")
        }
    }
    private var compatibilityGoalProfile: WineCompatibilityProfile {
        var value = profile
        value.graphicsAPI = nil
        value.graphicsBackend = .automatic
        value.graphicsFallback = .none
        value.wineD3DRenderer = .automatic
        value.esyncEnabled = true
        value.msyncEnabled = false
        value.fullscreenFSREnabled = false
        value.temporalUpscaling.mode = .automatic
        value.upscalingBridge = .none
        return value
    }
    private var performanceProfile: WineCompatibilityProfile {
        var value = profile
        value.graphicsAPI = nil
        value.graphicsBackend = .automatic
        value.esyncEnabled = true
        value.msyncEnabled = runtimeFeatures?.msync == true
        value.retinaModeEnabled = false
        value.fullscreenFSREnabled = false
        value.temporalUpscaling.mode = .automatic
        value.upscalingBridge = .none
        return value
    }
    private var recommendedProfile: WineCompatibilityProfile {
        WineCompatibilityProfile.default
    }
    private var usesSharedSteamEnvironment: Bool { currentApplication.usesSharedSteamEnvironment }
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
    private func synchronizationBinding(_ keyPath: WritableKeyPath<WineCompatibilityProfile, Bool>, supported: Bool) -> Binding<Bool> {
        Binding(
            get: { supported && profile[keyPath: keyPath] },
            set: { if supported { profile[keyPath: keyPath] = $0 } }
        )
    }

    private var synchronizationUnavailableDetail: String? {
        guard let features = runtimeFeatures else {
            return String(localized: "Select an installed Wine runtime to check synchronization support.")
        }
        if !features.esync && !features.msync {
            return String(localized: "This Wine runtime does not contain ESync or MSync. Import a Wine build with these features and select it in Runtime. Unavailable options are not passed to Wine.")
        }
        if !features.msync {
            return String(localized: "This Wine runtime does not contain MSync. To use it, import a Wine build with MSync and select it in Runtime.")
        }
        if !features.esync {
            return String(localized: "This Wine runtime does not contain ESync. MSync can be used independently.")
        }
        return nil
    }

    private var legacyWrapperDecision: LegacyWrapperDecision {
        GameGraphicsProfiles.legacyWrapperDecision(for: application, requested: profile)
    }
    private var availableRuntimes: [RuntimeStatus] { store.installedRuntimeStatusesForGameConfiguration() }
    private var selectedRuntimeIssue: String? {
        guard let runtimeID = profile.runtimeIDOverride else { return nil }
        return store.runtimeSelectionIssue(runtimeID, profile: profile, for: currentApplication)
    }
    private func runtimeLabel(_ runtime: RuntimeStatus) -> String {
        "\(runtime.name) · \(runtime.engine.displayName) \(runtime.wineVersion)"
    }
    private var graphicsBackendIssue: String? {
        var requestedApplication = currentApplication
        requestedApplication.compatibilityProfile = profile
        return store.graphicsBackendIssue(effectiveRequestedBackend, for: requestedApplication)
            ?? store.graphicsConfigurationIssue(profile: profile, for: currentApplication)
    }
    private var prefixModeIssue: String? {
        guard profile.runtimeIDOverride == nil, let requestedMode = profile.prefixMode else { return nil }
        return store.prefixModeIssue(requestedMode, for: currentApplication)
    }
    private var runtimeFeatures: RuntimeFeatures? {
        if let runtimeID = profile.runtimeIDOverride,
           let selected = availableRuntimes.first(where: { $0.id == runtimeID }) {
            return selected.features
        }
        return store.compatibilityRuntimeFeatures(for: currentApplication, backend: effectiveRequestedBackend)
    }
    private func legacyWrapperAvailable(_ wrapper: LegacyGraphicsWrapper) -> Bool {
        switch wrapper {
        case .none: true
        case .dd7to9: runtimeFeatures?.dd7to9 == true
        case .dgVoodoo2: runtimeFeatures?.dgVoodoo2 == true
        case .borealLegacyGraphics: runtimeFeatures?.borealLegacyGraphics == true
        }
    }
    private var legacyWrapperAvailabilityMessage: String? {
        guard profile.legacyWrapper != .none, !legacyWrapperAvailable(profile.legacyWrapper) else { return nil }
        return switch profile.legacyWrapper {
        case .none: nil
        case .dd7to9: String(localized: "Dd7to9 is unavailable because the selected runtime has no verified Dd7to9 component. Install it from Settings → Runtime.")
        case .dgVoodoo2: String(localized: "dgVoodoo2 is unavailable because the selected runtime has no verified component package.")
        case .borealLegacyGraphics: String(localized: "Boreal Legacy Graphics is unavailable because this app build does not contain its x86 ddraw.dll component.")
        }
    }
    private var legacyWrapperDetail: String {
        switch profile.legacyWrapper {
        case .none: ""
        case .dd7to9: String(localized: "Uses Dd7to9 to convert DirectDraw / Direct3D 1–7 calls to D3D9. Requires the verified Dd7to9 component and a D3D9-capable backend.")
        case .dgVoodoo2: String(localized: "Uses dgVoodoo2 for DirectDraw/Direct3D 7. Boreal writes a per-game config and forces the D3D11 FL 11.0 path for this test profile.")
        case .borealLegacyGraphics: String(localized: "Uses Boreal's x86 ddraw.dll proxy with COM tracing and a D3D11 first-draw path through DXMT. The bridge currently targets Sacred's DirectDraw/Direct3D 7 surface and texture path.")
        }
    }
    private var selectedLegacyTestProfile: LegacyGraphicsTestProfile {
        switch (profile.legacyWrapper, profile.graphicsBackend, profile.graphicsAPI ?? .automatic) {
        case (.none, .wineD3D, .automatic): .wineD3D
        case (.dd7to9, .wineD3D, .directX9): .dd7to9
        case (.dgVoodoo2, .wineD3D, .directX11): .dgVoodooWineD3D
        case (.dgVoodoo2, .dxmt, .directX11): .dgVoodooDXMT
        case (.borealLegacyGraphics, .dxmt, .directX11): .borealLegacyGraphicsDXMT
        default: .manual
        }
    }
    private var legacyTestProfileBinding: Binding<LegacyGraphicsTestProfile> {
        Binding(
            get: { selectedLegacyTestProfile },
            set: { profile = $0.applying(to: profile) }
        )
    }
    private func legacyTestProfileAvailable(_ testProfile: LegacyGraphicsTestProfile) -> Bool {
        switch testProfile {
        case .wineD3D, .manual: true
        case .dd7to9: runtimeFeatures?.dd7to9 == true
        case .dgVoodooWineD3D: runtimeFeatures?.dgVoodoo2 == true
        case .dgVoodooDXMT:
            runtimeFeatures?.dgVoodoo2 == true
                && runtimeFeatures?.dxmt == true
                && runtimeFeatures?.d3d11Verified == true
        case .borealLegacyGraphicsDXMT:
            runtimeFeatures?.borealLegacyGraphics == true
                && runtimeFeatures?.dxmt == true
                && runtimeFeatures?.d3d11Verified == true
        }
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

    private var optiScalerFrameGenerationEnabled: Bool {
        profile.temporalUpscaling.optiScaler.frameGenerationEnabled
    }

    private var optiScalerFrameGenerationBinding: Binding<Bool> {
        Binding(
            get: { optiScalerFrameGenerationEnabled },
            set: { enabled in
                profile.temporalUpscaling.optiScaler.enabled = enabled || profile.temporalUpscaling.optiScaler.enabled
                profile.temporalUpscaling.optiScaler.frameGeneration.mode = enabled ? .optiFG : .disabled
                if enabled {
                    profile.temporalUpscaling.mode = .optiScaler
                } else if profile.temporalUpscaling.mode == .optiScaler {
                    profile.temporalUpscaling.mode = .automatic
                }
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
            if GameLaunchCompatibility.supportsDLSSUnlocker(for: application) {
                if temporalInspector?.optiScaler.includesOptiPatcher == true {
                    return String(localized: "OptiPatcher is bundled with the managed OptiScaler component and will expose the DLSS input during injection.")
                }
                return String(localized: "GTA SA:DE requires the DLSS Unlocker/OptiPatcher input before OptiFG can be used.")
            }
            return String(localized: "No DLSS, FSR 2+ or XeSS interface was detected in the game files.")
        }
        return game.detectedTemporalInterfaces.map { capability in
            "\(capability.kind.displayName): \(capability.confidence.rawValue) confidence; runtime operation is not proven."
        }.joined(separator: " ")
    }

    private func frameGenerationPlanExplanation(_ plan: TemporalUpscalingPlan) -> String {
        if temporalInspector?.game.hasTemporalInterface == false,
           GameLaunchCompatibility.supportsDLSSUnlocker(for: application) {
            if temporalInspector?.optiScaler.includesOptiPatcher == true {
                return String(localized: "OptiPatcher is bundled and will expose the DLSS input during OptiScaler injection; live operation remains unverified.")
            }
            return String(localized: "GTA SA:DE has no detected temporal input. Install the DLSS Unlocker/OptiPatcher input before enabling OptiFG.")
        }
        if temporalInspector?.optiScaler.installed != true {
            return String(localized: "A compiled OptiScaler.dll component must be installed before OptiFG can be injected.")
        }
        return plan.reason
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
        switch effectiveRequestedBackend {
        case .automatic:
            let api = effectiveGraphicsAPI
            if runtimeFeatures?.hasVerifiedD3DMetal == true, (api == .directX11 || api == .directX12) { return .d3dMetal }
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
    private var selectableGraphicsAPIs: [GraphicsAPI] {
        return GraphicsAPI.allCases.filter { $0 != .automatic }
    }
    private var graphicsAPIBinding: Binding<GraphicsAPI> {
        Binding(
            get: {
                guard let selected = profile.graphicsAPI,
                      selected != .automatic,
                      selectableGraphicsAPIs.contains(selected) else { return .automatic }
                return selected
            },
            set: { profile.graphicsAPI = $0 }
        )
    }
    private var effectiveGraphicsAPI: GraphicsAPI {
        CompatibilityPreparationResolver.directXAPI(
            executable: URL(fileURLWithPath: application.executablePath),
            userProfile: profile,
            gameProfile: graphicsProfile
        )
    }
    private var graphicsBackendExplanation: String {
        if profile.graphicsBackend == .automatic,
           let preferredBackend = graphicsProfile?.enforcedBackend ?? graphicsProfile?.preferredBackend {
            return "Automatic uses the game profile's \(compatibilityLocalizedBackendName(preferredBackend)) preference. Choose another renderer to override it."
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
    private var graphicsAPIExplanation: String {
        return String(localized: "Choose the DirectX version Boreal should prepare the renderer for. A game changes its own API only when a verified game-specific launch option exists; otherwise change it in the game itself.")
    }
    private var effectiveRequestedBackend: WineGraphicsBackend {
        GameGraphicsProfiles.requestedBackend(profile.graphicsBackend, for: graphicsProfile)
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
                ForEach([CompatibilityPreset.recommended, .compatibility, .performance]) { preset in
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
    var detailText: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                if let detailText {
                    Text(detailText).font(.caption).foregroundStyle(.secondary)
                } else if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct LegacyWrapperDecisionCard: View {
    let decision: LegacyWrapperDecision

    private func wrapperName(_ wrapper: LegacyGraphicsWrapper?) -> String {
        wrapper?.displayName ?? String(localized: "Not set")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Wrapper decision (Developer Mode)", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.weight(.semibold))
            InspectorValueRow(title: "Requested wrapper", value: decision.requested.displayName, monospaced: true)
            InspectorValueRow(title: "Profile preference", value: wrapperName(decision.profilePreference), monospaced: true)
            InspectorValueRow(title: "Profile enforcement", value: wrapperName(decision.profileEnforcement), monospaced: true)
            InspectorValueRow(title: "Effective wrapper", value: decision.effective.displayName, monospaced: true)
            InspectorValueRow(title: "Source of decision", value: decision.source.displayName, monospaced: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.blue.opacity(0.18)) }
    }
}

private struct CompatibilityLaunchPlanCard: View {
    let application: WindowsApplication
    let profile: WineCompatibilityProfile
    let gameAPILabel: String
    let rendererLabel: String
    let prefixLabel: String
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
            planRow("Renderer", rendererLabel, "gearshape.2")
            planRow("Game API", gameAPILabel, "square.3.layers.3d")
            planRow("Runtime", runtimeLabel ?? String(localized: "Automatic"), "shippingbox")
            planRow("Windows", profile.windowsVersion.displayName, "window.ceiling")
            planRow("Prefix", prefixLabel, "externaldrive")
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

private struct CompatibilitySettingsFooter: View {
    let restore: () -> Void; let cancel: () -> Void; let save: () -> Void; let saveDisabled: Bool
    let saveTitle: LocalizedStringResource
    let impacts: [CompatibilityChangeImpact]
    let isApplying: Bool
    let applyingMessage: String?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(impacts) { impact in
                Label(impact.displayName, systemImage: impact.symbol)
                    .font(.caption)
                    .foregroundStyle(impact == .environmentRebuild || impact == .gameFilesModification ? .orange : .secondary)
            }
            if isApplying {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(applyingMessage ?? String(localized: "Applying compatibility changes…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                CompatibilityCallout(text: errorMessage, symbol: "exclamationmark.triangle.fill", tint: .red)
            }
            HStack {
                Button("Restore defaults", systemImage: "arrow.counterclockwise", action: restore)
                    .disabled(isApplying)
                Spacer()
                Button("Cancel", action: cancel).disabled(isApplying)
                Button {
                    save()
                } label: {
                    if isApplying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(saveTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveDisabled)
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
            if GameLaunchCompatibility.supportsDLSSUnlocker(for: application) {
                let optiPatcherInstalled = temporalInspector?.optiScaler.includesOptiPatcher == true
                let unlockerInstalled = store.dlssUnlockerInstalled(for: application)
                let inputAvailable = optiPatcherInstalled || unlockerInstalled
                HStack(alignment: .top, spacing: 10) {
                    CompatibilityUpscalingRow(
                        title: "GTA SA DLSS input",
                        detail: optiPatcherInstalled
                            ? String(localized: "OptiPatcher bundled in OptiScaler")
                            : (unlockerInstalled ? String(localized: "DLSS Unlocker installed") : String(localized: "Required for OptiFG input")),
                        status: inputAvailable ? .detected : .notDetected,
                        explanation: inputAvailable
                            ? String(localized: "The OptiPatcher/Unlocker path provides the input that OptiScaler needs; live compatibility is still unverified.")
                            : String(localized: "Import the validated DLSS Unlocker ZIP to expose a DLSS input in GTA SA:DE.")
                    )
                    Spacer(minLength: 4)
                    Button(inputAvailable ? String(localized: "Ready") : String(localized: "Install…"), systemImage: inputAvailable ? "checkmark" : "arrow.down.app") {
                        if !inputAvailable { selectDLSSUnlockerArchive() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(inputAvailable || application.status == .running || application.status.isBusy)
                }
            }
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
            if runtimeFeatures?.hasVerifiedD3DMetal == true, (api == .directX11 || api == .directX12) { return .d3dMetal }
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
        guard !game.detectedTemporalInterfaces.isEmpty else {
            if GameLaunchCompatibility.supportsDLSSUnlocker(for: application) {
                if temporalInspector?.optiScaler.includesOptiPatcher == true {
                    return String(localized: "OptiPatcher is bundled with the managed OptiScaler component and will expose the DLSS input during injection.")
                }
                return String(localized: "GTA SA:DE requires the DLSS Unlocker/OptiPatcher input before OptiFG can be used.")
            }
            return String(localized: "No DLSS, FSR 2+ or XeSS interface was detected in the game files.")
        }
        return game.detectedTemporalInterfaces.map { "\($0.kind.displayName): \($0.confidence.rawValue) confidence; runtime operation is not proven." }.joined(separator: " ")
    }

    private func selectDLSSUnlockerArchive() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Install GTA SA DLSS Unlocker")
        panel.message = String(localized: "Choose the ZIP downloaded from the linked mod page. Boreal will validate and install only the unlocker files.")
        panel.prompt = String(localized: "Install Unlocker")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let archive = panel.url else { return }
        store.installDLSSUnlocker(archive, for: application.id)
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
            installed ? String(localized: "Versioned and hash-validated; the release payload and supported plugins are installed next to the game executable.") : String(localized: "Select a compiled OptiScaler release folder; Boreal copies its declared payload and plugins, then uses the game profile's safe proxy DLL.")
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
                Button("Remove", systemImage: "trash") {
                    Task { await store.removeOptiScalerFromGame(for: application.id); refreshInspector() }
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
            InspectorValueRow(title: "OptiScaler proxy", value: inspector.optiScalerProxy.selectedName ?? String(localized: "Unavailable"))
            ForEach(inspector.optiScalerProxy.candidates, id: \.name) { candidate in
                if !candidate.isAvailable {
                    Text("\(candidate.name): \(candidate.detail)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
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
