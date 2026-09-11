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
    @State private var installedUpscalingBridgeVersion: String?
    @State private var temporalInspector: TemporalUpscalingInspectorSnapshot?
    @State private var isImportingTemporalComponent = false
    @State private var temporalComponentToImport: TemporalComponentID?

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
                saveDisabled: application.status == .running || application.status.isBusy || graphicsBackendIssue != nil || prefixModeIssue != nil
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
        .task(id: application.environmentID) {
            installedUpscalingBridgeVersion = await store.installedUpscalingBridgeVersion(
                for: application,
                bridge: .ngxToMetalFX
            )
            temporalInspector = await store.temporalUpscalingInspector(for: application.id)
        }
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
                temporalInspector = await store.temporalUpscalingInspector(for: application.id)
            }
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
        return VStack(spacing: 12) {
            CompatibilitySettingsSection(title: "Spatial upscaling", subtitle: "Wine Fullscreen FSR1 is a separate spatial mechanism.", symbol: "arrow.up.left.and.arrow.down.right", tint: .orange) {
                CompatibilityUpscalingRow(title: "Wine Fullscreen FSR 1", detail: compatibilityLocalizedCapabilityTitle(spatialCapability), status: spatialCapability.status, explanation: compatibilityLocalizedCapabilityDetail(spatialCapability))
                CompatibilityToggleRow(title: "Enable spatial upscaling", detail: "Requested preference for Wine's fullscreen FSR path. It becomes active only with a verified compatible Vulkan path and no active temporal path.", isOn: $profile.fullscreenFSREnabled)
                if fullscreenFSRCapabilities.supportsMode {
                    CompatibilityPickerRow(title: "FSR preset", detail: String(localized: "Controls the render resolution used by the fullscreen FSR patch.")) {
                        Picker("FSR preset", selection: $profile.fullscreenFSRMode) {
                            ForEach(FullscreenFSRMode.allCases) { mode in Text(compatibilityLocalizedFSRModeName(mode)).tag(mode) }
                        }.labelsHidden().disabled(!profile.fullscreenFSREnabled)
                    }
                }
                if let reason = fullscreenFSRUnavailableReason {
                    CompatibilityCallout(text: reason, symbol: "exclamationmark.triangle.fill", tint: .orange)
                }
            }

            CompatibilitySettingsSection(title: "Temporal upscaling", subtitle: "The game interface, bridge, and effective launch path are resolved independently from Wine FSR1.", symbol: "waveform.path.ecg", tint: .purple) {
                let game = temporalInspector?.game
                let plan = temporalInspector?.temporalPlan
                CompatibilityUpscalingRow(
                    title: "Detected game interface",
                    detail: game.map { detectedTemporalInterfaceLabel($0) } ?? String(localized: "Analyzing game files…"),
                    status: game.map { $0.hasTemporalInterface ? .detected : .notDetected } ?? .candidate,
                    explanation: game.map { temporalInterfaceExplanation($0) } ?? String(localized: "No game files have been analyzed yet.")
                )
                CompatibilityPickerRow(title: "Temporal upscaling mode", detail: String(localized: "Automatic recommends only from real detection data. Manual bridge paths remain experimental until a live smoke test verifies them.")) {
                    Picker("Temporal upscaling mode", selection: temporalModeBinding) {
                        ForEach(TemporalUpscalingMode.allCases) { mode in Text(mode.displayName).tag(mode) }
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
                    detail: temporalInspector?.metalFX.installed == true
                        ? String(localized: "Installed from selected GPTK runtime")
                        : (temporalInspector?.metalFX.available == true
                            ? String(localized: "Available in selected GPTK runtime")
                            : String(localized: "Not detected in selected runtime")),
                    status: temporalInspector?.metalFX.installed == true
                        ? .detected
                        : (temporalInspector?.metalFX.available == true ? .candidate : .unavailable),
                    explanation: temporalInspector?.metalFX.installed == true
                        ? String(localized: "Managed ComponentStore copy is available; this macOS game path is not live verified.")
                        : (temporalInspector?.metalFX.available == true
                            ? String(localized: "Runtime payload detected; install the managed bridge copy before selecting this path.")
                            : String(localized: "Boreal did not find the bridge payload in this immutable runtime."))
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
                                installedUpscalingBridgeVersion = await store.installedUpscalingBridgeVersion(for: application, bridge: .ngxToMetalFX)
                                temporalInspector = await store.temporalUpscalingInspector(for: application.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.runtimeOperationDetail != nil || application.status == .running || application.status.isBusy || fullscreenFSRResolvedBackend != .d3dMetal)
                    }
                }
                temporalComponentRow(
                    title: "DLSSTweaks",
                    status: temporalInspector?.dlsstweaks,
                    component: .dlsstweaks
                )
                temporalComponentRow(
                    title: "OptiScaler",
                    status: temporalInspector?.optiScaler,
                    component: .optiScaler
                )
                temporalComponentRow(
                    title: "DLSS Runtime",
                    status: temporalInspector?.managedDLSSRuntime,
                    component: .dlssRuntime
                )
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
                                temporalInspector = await store.temporalUpscalingInspector(for: application.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!inspector.managedDLSSRuntime.installed || inspector.dlssRuntime?.source == .borealManaged || application.status == .running || application.status.isBusy)
                        Button("Restore original") {
                            Task {
                                await store.restoreManagedDLSSRuntime(for: application.id)
                                temporalInspector = await store.temporalUpscalingInspector(for: application.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(inspector.dlssRuntime?.source != .borealManaged || application.status == .running || application.status.isBusy)
                    }
                }
                if let plan, plan.injectionSafety != .allowed {
                    CompatibilityCallout(text: plan.injectionSafety == .blockedAntiCheat
                        ? String(localized: "External DLL injection is disabled for this game because anti-cheat or integrity protection may be active.")
                        : String(localized: "External DLL injection requires an explicit user action because this game's policy is unknown."), symbol: "shield.lefthalf.filled", tint: .orange)
                }
                if application.usesSharedSteamEnvironment {
                    CompatibilityCallout(text: String(localized: "Steam uses a shared Windows environment. Registry and injected DLL changes can affect more than one game."), symbol: "person.2.fill", tint: .blue)
                }
                if let inspector = temporalInspector {
                    DisclosureGroup("DLSS / NGX Inspector") {
                        inspectorContent(inspector)
                    }
                }
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
                    Text(profile.forceXInput ? String(localized: "Xbox 360 Controller") : String(localized: "Native Wine controller")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Label("No controller detected", systemImage: "gamecontroller").foregroundStyle(.secondary)
            }
            CompatibilityToggleRow(title: "Disable keyboard mapping", detail: "Stops Boreal from turning controller buttons into keyboard presses. Steam Input is unchanged.", isOn: $profile.disableSteamInputEquivalent)
            CompatibilityToggleRow(title: "Xbox controller compatibility", detail: "Presents the controller as an Xbox 360 controller. Restart the entire Wine session after changing this.", isOn: $profile.forceXInput, disabled: usesSharedSteamEnvironment || runtimeFeatures?.wineBusControllerMapping != true)
            Button("Controller mapping", systemImage: "gamecontroller") { showsControllerMapping = true }
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
            DisclosureGroup("Older games") {
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
        CompatibilityResultCard(
            application: application, profile: profile,
            directXLabel: compatibilityLocalizedGraphicsAPIName(graphicsAPIBinding.wrappedValue),
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
    private var graphicsBackendIssue: String? { store.graphicsBackendIssue(profile.graphicsBackend, for: application) }
    private var prefixModeIssue: String? { store.prefixModeIssue(profile.prefixMode ?? .wow64, for: application) }
    private var runtimeFeatures: RuntimeFeatures? { store.compatibilityRuntimeFeatures(for: application, backend: profile.graphicsBackend) }
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

    @ViewBuilder
    private func temporalComponentRow(
        title: LocalizedStringResource,
        status: TemporalComponentStatus?,
        component: TemporalComponentID
    ) -> some View {
        let installed = status?.installed == true
        let explanation: String = if component == .optiScaler {
            installed
                ? String(localized: "Versioned and hash-validated; selecting a release folder installs it next to the game executable.")
                : String(localized: "Select a compiled OptiScaler release folder; Boreal copies its payload and installs dxgi.dll next to the game executable.")
        } else {
            installed
                ? String(localized: "Versioned and hash-validated before a game injection is attempted.")
                : String(localized: "Import a user-supplied component folder; Boreal will store it immutably and record its SHA-256.")
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
            if component == .dlsstweaks,
               installed,
               temporalInspector?.dlsstweaksCapabilities?.injectionFiles.isEmpty == false {
                Button("Inject", systemImage: "arrow.down.to.line") {
                    Task {
                        await store.injectDLSSTweaks(for: application.id)
                        temporalInspector = await store.temporalUpscalingInspector(for: application.id)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(application.status == .running || application.status.isBusy)
            }
            if component == .optiScaler, installed {
                Button("Inject", systemImage: "arrow.down.to.line") {
                    Task {
                        await store.injectOptiScaler(for: application.id)
                        temporalInspector = await store.temporalUpscalingInspector(for: application.id)
                    }
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
            InspectorValueRow(
                title: "Source",
                value: inspector.dlssRuntime.map { $0.source == .gameOriginal ? String(localized: "Game installation") : String(localized: "Boreal managed") }
                    ?? String(localized: "Unavailable")
            )
            InspectorValueRow(title: "Native DLSS availability", value: inspector.game.dlss?.detected == true ? String(localized: "Detected") : String(localized: "Not detected"))
            InspectorValueRow(title: "SHA-256", value: inspector.dlssRuntime?.activeSHA256 ?? String(localized: "Unavailable"), monospaced: true)
            InspectorValueRow(title: "DLSSTweaks", value: inspector.dlsstweaks.version ?? String(localized: "Not installed"))
            InspectorValueRow(
                title: "DLSSTweaks controls",
                value: inspector.dlsstweaksCapabilities?.supportedControls.map(\.rawValue).sorted().joined(separator: ", ")
                    ?? String(localized: "Not declared by component")
            )
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
                    set: { enabled in
                        Task {
                            await store.setNGXDebugIndicator(enabled, for: application.id)
                            temporalInspector = await store.temporalUpscalingInspector(for: application.id)
                        }
                    }
                ))
                .labelsHidden()
                .disabled(!inspector.ngxDebugIndicator.available)
            }
            if !inspector.ngxDebugIndicator.available {
                Text(inspector.ngxDebugIndicator.detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
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
    private func backendLabel(_ backend: WineGraphicsBackend) -> String { store.graphicsBackendIssue(backend, for: application) == nil ? compatibilityLocalizedBackendName(backend) : compatibilityLocalizedBackendName(backend) + " · " + String(localized: "Unavailable") }
    private var graphicsAPIBinding: Binding<GraphicsAPI> { Binding(get: { profile.graphicsAPI ?? graphicsProfile?.defaultAPI ?? .automatic }, set: { profile.graphicsAPI = $0 }) }
    private func graphicsAPILabel(for api: GraphicsAPI) -> String {
        if let graphicsProfile, api == graphicsProfile.defaultAPI { return compatibilityLocalizedGraphicsAPIName(api) + " · " + String(localized: "Recommended") }
        if graphicsProfile == nil, api == detectedGraphicsAPI { return compatibilityLocalizedGraphicsAPIName(api) + " · " + String(localized: "Detected") }
        if let graphicsProfile, api != .automatic, !graphicsProfile.availableAPIs.contains(api) { return compatibilityLocalizedGraphicsAPIName(api) + " · " + String(localized: "Manual") }
        return compatibilityLocalizedGraphicsAPIName(api)
    }
    private var graphicsBackendExplanation: String {
        if graphicsProfile?.enforcedBackend != nil { return String(localized: "WineD3D is enforced for this game because the Vulkan renderer cannot initialize its Direct3D device on this runtime.") }
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
            row("Renderer", compatibilityLocalizedBackendName(profile.graphicsBackend), "gearshape.2")
            row("DirectX version", directXLabel, "square.3.layers.3d")
            row("Windows version", profile.windowsVersion.displayName, "window.ceiling")
            row("Wine prefix", compatibilityLocalizedPrefixModeName(profile.prefixMode ?? .wow64), "shippingbox")
            row("Game display", displayLabel, "display")
            row("Overlay compatible", profile.overlayCompatibleFullscreen ? String(localized: "Yes") : String(localized: "No"), "rectangle.on.rectangle")
            if profile.upscalingBridge != .none {
                row("Temporal bridge", compatibilityLocalizedTemporalBridgeName(profile.upscalingBridge), "arrow.triangle.branch")
            }
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
