import Foundation

nonisolated enum RuntimeArchitecture: String, Codable, Sendable { case x86_64, arm64 }
nonisolated enum RuntimeChannel: String, Codable, Sendable {
    case developer, preview, stable

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "developer", "devel": self = .developer
        case "preview", "staging": self = .preview
        case "stable": self = .stable
        default: throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown runtime channel: \(value)")
        }
    }
}
nonisolated enum RuntimeRequirement: String, Codable, Sendable, Hashable { case rosetta2, gStreamerFramework }
nonisolated enum RuntimeOrigin: String, Codable, Sendable, Hashable { case catalog, localImport }
nonisolated enum RuntimeEngine: String, Codable, Sendable, Hashable, CaseIterable {
    case wine
    case gamePortingToolkit

    var displayName: String {
        switch self {
        case .wine: "Wine"
        case .gamePortingToolkit: "Game Porting Toolkit"
        }
    }

    var graphicsName: String { self == .gamePortingToolkit ? "D3DMetal" : "WineD3D" }
}

/// Runtime architecture is an executable capability, not the presence of a
/// helper named `wine64`.  New WoW64 builds intentionally expose one `wine`
/// launcher, so callers must use these capabilities instead of checking a
/// legacy filename.
nonisolated struct RuntimeArchitectureCapabilities: Codable, Sendable, Hashable {
    var canRunX86: Bool
    var canRunX86_64: Bool
    var usesNewWoW64: Bool
    var supportsLegacyWin32Prefix: Bool

    static let unknown = RuntimeArchitectureCapabilities(
        canRunX86: false,
        canRunX86_64: false,
        usesNewWoW64: false,
        supportsLegacyWin32Prefix: false
    )
}

/// Optional fields mean unverified, never inferred from the Wine/GPTK version.
nonisolated struct GraphicsBackendCapabilities: Codable, Sendable, Hashable {
    var metal4: Bool?
    var hdr: Bool?
    var upscaling: Bool?
    var frameGeneration: Bool?
    var performanceInsights: Bool?
    var metalHUD: Bool?
    var gpuCapture: Bool?
    var metalSystemTrace: Bool?
    var fullscreenFSRSupport: FullscreenFSRSupportLevel?
}

nonisolated enum FullscreenFSRCapabilitySource: String, Codable, Sendable, Hashable {
    case runtimeManifest
    case payloadInspection
    case runtimeProbe
}

nonisolated enum FullscreenFSRCapabilityConfidence: String, Codable, Sendable, Hashable {
    case declared
    case detected
    case verified
}

nonisolated enum FullscreenFSRSupportLevel: String, Codable, Sendable, Hashable {
    case unsupported
    case candidate
    case verified
}

nonisolated struct FullscreenFSRCapabilities: Codable, Sendable, Hashable {
    var available: Bool
    var source: FullscreenFSRCapabilitySource
    var confidence: FullscreenFSRCapabilityConfidence
    var supportsMode: Bool
    var supportsStrength: Bool
    var supportsCustomMode: Bool

    init(
        available: Bool,
        source: FullscreenFSRCapabilitySource,
        confidence: FullscreenFSRCapabilityConfidence = .detected,
        supportsMode: Bool = false,
        supportsStrength: Bool = false,
        supportsCustomMode: Bool = false
    ) {
        self.available = available
        self.source = source
        self.confidence = confidence
        self.supportsMode = supportsMode
        self.supportsStrength = supportsStrength
        self.supportsCustomMode = supportsCustomMode
    }

    private enum CodingKeys: String, CodingKey {
        case available, source, confidence, supportsMode, supportsStrength, supportsCustomMode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        available = try values.decode(Bool.self, forKey: .available)
        source = try values.decode(FullscreenFSRCapabilitySource.self, forKey: .source)
        confidence = try values.decodeIfPresent(FullscreenFSRCapabilityConfidence.self, forKey: .confidence) ?? .detected
        supportsMode = try values.decodeIfPresent(Bool.self, forKey: .supportsMode) ?? false
        supportsStrength = try values.decodeIfPresent(Bool.self, forKey: .supportsStrength) ?? false
        supportsCustomMode = try values.decodeIfPresent(Bool.self, forKey: .supportsCustomMode) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(available, forKey: .available)
        try values.encode(source, forKey: .source)
        try values.encode(confidence, forKey: .confidence)
        try values.encode(supportsMode, forKey: .supportsMode)
        try values.encode(supportsStrength, forKey: .supportsStrength)
        try values.encode(supportsCustomMode, forKey: .supportsCustomMode)
    }
}

nonisolated extension FullscreenFSRSupportLevel {
    var isUsable: Bool { self == .verified }
}

nonisolated enum FullscreenFSRMode: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case ultra
    case quality
    case balanced
    case performance

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ultra: "Ultra Quality"
        case .quality: "Quality"
        case .balanced: "Balanced"
        case .performance: "Performance"
        }
    }
}

nonisolated enum FullscreenFSRUnavailableReason: String, Codable, Sendable, Hashable {
    case runtimeUnsupported
    case runtimeNotVerified
    case graphicsStackUnsupported
    case graphicsStackNotVerified
    case windowModeUnsupported
}

nonisolated struct EffectiveFullscreenFSR: Codable, Sendable, Hashable {
    let requestedEnabled: Bool
    let enabled: Bool
    let availability: FullscreenFSRUnavailableReason?
    let capabilities: FullscreenFSRCapabilities
    let supportLevel: FullscreenFSRSupportLevel
    let mode: FullscreenFSRMode
    let strength: Int
    let customMode: String?
}

nonisolated enum UpscalingDetectionStatus: String, Codable, Sendable, Hashable {
    case unavailable
    case notDetected
    case detected
    case candidate
    case verified
}

/// A temporal upscaling bridge is an optional, immutable component snapshot.
/// The bridge is selected per game; it is never inferred from a renderer
/// name and it is never copied into the read-only GPTK runtime itself.
nonisolated enum TemporalUpscalingBridge: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case none
    case ngxToMetalFX

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "Disabled"
        case .ngxToMetalFX: "NGX → MetalFX"
        }
    }

    var detail: String {
        switch self {
        case .none: "Do not load a temporal bridge for this game."
        case .ngxToMetalFX: "Uses the GPTK NVIDIA NGX forwarder with Apple's MetalFX path."
        }
    }
}

nonisolated struct UpscalingCapability: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let status: UpscalingDetectionStatus
    let detail: String
}

/// Exact immutable snapshot of a temporal bridge copied from a runtime or
/// imported as a managed component. The launch path validates this receipt
/// before exposing any bridge DLLs to Wine.
nonisolated struct UpscalingBridgeReference: Codable, Sendable, Hashable {
    let bridge: TemporalUpscalingBridge
    let version: String
    let sha256: String
    let installedFiles: [String]
}

nonisolated struct UpscalingResolution: Codable, Sendable, Hashable {
    let spatial: UpscalingCapability
    let nativeInterfaces: [UpscalingCapability]
    let temporalReplacement: UpscalingCapability
    let bridge: UpscalingCapability
    let metalFXBridge: UpscalingCapability
    let currentRenderer: GraphicsBackend
    let compatibility: UpscalingDetectionStatus
}

/// Describes upscaling paths without claiming that an experimental bridge is
/// installed or functional. Detection is deliberately file/metadata based;
/// only a real runtime smoke test may promote a candidate to verified.
nonisolated enum UpscalingResolver {
    static func resolve(
        application: WindowsApplication,
        runtimeFeatures: RuntimeFeatures?,
        backend: GraphicsBackend
    ) -> UpscalingResolution {
        let files = gameFiles(for: application)
        let runtimeCapabilities = runtimeFeatures?.fullscreenFSRCapabilities
            ?? (runtimeFeatures?.fullscreenFSR == true
                ? FullscreenFSRCapabilities(available: true, source: .payloadInspection)
                : FullscreenFSRCapabilities(available: false, source: .payloadInspection))
        let stackLevel = runtimeFeatures?.graphicsCapabilities?[backend.rawValue]?.fullscreenFSRSupport
            ?? GraphicsStackCatalog.stack(for: backend)?.fullscreenFSRSupportLevel
            ?? .unsupported
        let spatial: UpscalingCapability
        if !runtimeCapabilities.available || stackLevel == .unsupported {
            spatial = UpscalingCapability(
                id: "wine-fsr1",
                title: "Wine FSR 1",
                status: .unavailable,
                detail: "Requires compatible Vulkan graphics path"
            )
        } else if runtimeCapabilities.confidence == .verified && stackLevel == .verified {
            spatial = UpscalingCapability(
                id: "wine-fsr1",
                title: "Wine FSR 1",
                status: .verified,
                detail: "Verified for the selected runtime and graphics path"
            )
        } else {
            spatial = UpscalingCapability(
                id: "wine-fsr1",
                title: "Wine FSR 1",
                status: .candidate,
                detail: "Detected, but not verified on this macOS graphics path"
            )
        }

        let nativeInterfaces = [
            ("dlss", "DLSS", ["nvngx_dlss.dll", "nvngx_dlssg.dll", "libnvngx.so"]),
            ("fsr", "FSR", ["amd_fidelityfx_dx12.dll", "ffx_fsr2_api_x64.dll", "ffx_fsr3_x64.dll"]),
            ("xess", "XeSS", ["libxess.dll", "libxess.so", "xess.dll"])
        ].compactMap { id, title, names -> UpscalingCapability? in
            guard names.contains(where: { files.contains($0) }) else { return nil }
            return UpscalingCapability(id: id, title: title, status: .detected, detail: "Game interface detected")
        }

        let optiScalerDetected = files.contains("optiscaler.dll")
        let temporalReplacement = UpscalingCapability(
            id: "temporal-fsr-replacement",
            title: "FSR replacement",
            status: optiScalerDetected ? .candidate : .notDetected,
            detail: optiScalerDetected
                ? "Experimental temporal replacement through OptiScaler"
                : "No temporal replacement bridge detected"
        )
        let bridge = UpscalingCapability(
            id: "optiscaler",
            title: "Bridge",
            status: optiScalerDetected ? .candidate : .notDetected,
            detail: optiScalerDetected
                ? "OptiScaler detected; output and compatibility are not verified"
                : "OptiScaler is not installed for this game"
        )
        let metalFXForwarderDetected = files.contains("nvngx-on-metalfx.dll")
            || files.contains("nvngx_on_metalfx.dll")
            || files.contains("libnvngx-on-metalfx.dylib")
        let metalFXReported = backend == .d3dMetal && (
            runtimeFeatures?.graphicsCapabilities?[backend.rawValue]?.upscaling == true
                || metalFXForwarderDetected
        )
        let metalFXBridge = UpscalingCapability(
            id: "metalfx-bridge",
            title: "NGX → MetalFX",
            status: metalFXReported ? .candidate : .notDetected,
            detail: metalFXForwarderDetected
                ? "NVIDIA NGX forwarder detected; the MetalFX bridge is not verified"
                : metalFXReported
                    ? "Runtime reports an upscaling path; the NVIDIA NGX bridge is not verified"
                : "No verified NVIDIA NGX to MetalFX bridge detected"
        )
        let compatibility: UpscalingDetectionStatus = optiScalerDetected ? .candidate : .notDetected
        return UpscalingResolution(
            spatial: spatial,
            nativeInterfaces: nativeInterfaces,
            temporalReplacement: temporalReplacement,
            bridge: bridge,
            metalFXBridge: metalFXBridge,
            currentRenderer: backend,
            compatibility: compatibility
        )
    }

    private static func gameFiles(for application: WindowsApplication) -> Set<String> {
        let executable = URL(fileURLWithPath: application.executablePath)
        let gameRoot = executable.deletingLastPathComponent()
        let searchRoots = [
            gameRoot,
            gameRoot.appending(path: "Binaries/Win64", directoryHint: .isDirectory),
            gameRoot.appending(path: "Engine/Binaries/Win64", directoryHint: .isDirectory),
            gameRoot.appending(path: "Plugins", directoryHint: .isDirectory)
        ]
        var names = Set<String>()
        let fileManager = FileManager.default
        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            names.formUnion(entries.map { $0.lastPathComponent.lowercased() })
        }
        return names
    }
}

nonisolated struct GraphicsBackendConfiguration: Sendable, Hashable {
    var backend: GraphicsBackend
    var api: GraphicsAPI
    var fullscreenFSREnabled: Bool
    var fullscreenFSRMode: FullscreenFSRMode = .balanced
    var fullscreenFSRStrength: Int = 2
    var fullscreenFSRCustomMode: String? = nil
    var overlayCompatibleFullscreen: Bool = true

    func resolvedBackend(
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture = .win64
    ) -> GraphicsBackend {
        GraphicsBackendManager().resolve(
            backend,
            graphicsAPI: api,
            runtime: runtime,
            architecture: architecture
        )
    }

    func capabilities(runtime: InstalledRuntime) -> GraphicsBackendCapabilities {
        let resolved = resolvedBackend(runtime: runtime)
        var result = runtime.features?.graphicsCapabilities?[resolved.rawValue] ?? GraphicsBackendCapabilities()
        // Existing D3DMetal HUD integration is known independently of GPTK version.
        if result.metalHUD == nil, resolved == .d3dMetal, runtime.features?.d3dmetal == true {
            result.metalHUD = true
        }
        return result
    }

    func effectiveFullscreenFSR(
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture = .win64
    ) -> EffectiveFullscreenFSR {
        let runtimeCapabilities = runtime.features?.fullscreenFSRCapabilities
            ?? (runtime.features?.fullscreenFSR == true
                ? FullscreenFSRCapabilities(available: true, source: .payloadInspection)
                : FullscreenFSRCapabilities(available: false, source: .payloadInspection))
        let resolved = resolvedBackend(runtime: runtime, architecture: architecture)
        let stackSupportLevel = runtime.features?.graphicsCapabilities?[resolved.rawValue]?.fullscreenFSRSupport
            ?? GraphicsStackCatalog.stack(for: resolved)?.fullscreenFSRSupportLevel
            ?? .unsupported
        let unavailable: FullscreenFSRUnavailableReason? = if !runtimeCapabilities.available {
            .runtimeUnsupported
        } else if runtimeCapabilities.confidence != .verified {
            .runtimeNotVerified
        } else if stackSupportLevel == .unsupported {
            .graphicsStackUnsupported
        } else if !stackSupportLevel.isUsable {
            .graphicsStackNotVerified
        } else if overlayCompatibleFullscreen {
            .windowModeUnsupported
        } else {
            nil
        }
        return EffectiveFullscreenFSR(
            requestedEnabled: fullscreenFSREnabled,
            enabled: fullscreenFSREnabled && unavailable == nil,
            availability: unavailable,
            capabilities: runtimeCapabilities,
            supportLevel: stackSupportLevel,
            mode: fullscreenFSRMode,
            strength: min(max(fullscreenFSRStrength, 0), 5),
            customMode: fullscreenFSRCustomMode
        )
    }

    /// Fullscreen FSR is a launch-time setting, not a prefix property.
    func launchEnvironment(
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture = .win64
    ) -> [String: String] {
        let effective = effectiveFullscreenFSR(runtime: runtime, architecture: architecture)
        guard effective.enabled else { return [:] }
        var values = ["WINE_FULLSCREEN_FSR": "1"]
        if effective.capabilities.supportsMode {
            values["WINE_FULLSCREEN_FSR_MODE"] = effective.mode.rawValue
        }
        if effective.capabilities.supportsStrength {
            values["WINE_FULLSCREEN_FSR_STRENGTH"] = String(effective.strength)
        }
        if effective.capabilities.supportsCustomMode, let customMode = effective.customMode, !customMode.isEmpty {
            values["WINE_FULLSCREEN_FSR_CUSTOM_MODE"] = customMode
        }
        return values
    }
}

nonisolated struct RuntimeFeatures: Codable, Sendable, Hashable {
    var wow64: Bool
    /// Optional explicit capability metadata. Older manifests derive Win32
    /// support from WoW64 and conservatively treat Win64 as available.
    var supportsWin32Execution: Bool?
    var supportsWin64Execution: Bool?
    var architectureCapabilities: RuntimeArchitectureCapabilities?
    var wineMono: Bool
    var wineGecko: Bool
    var d3dmetal: Bool
    var dxmt: Bool
    var dxvk: Bool = false
    var vkd3d: Bool = false
    var esync: Bool = false
    var msync: Bool = false
    var fullscreenFSR: Bool = false
    var fullscreenFSRCapabilities: FullscreenFSRCapabilities?
    var wineBusControllerMapping: Bool = false
    var dgVoodoo2: Bool = false
    var graphicsCapabilities: [String: GraphicsBackendCapabilities]?

    private enum CodingKeys: String, CodingKey {
        case wow64, supportsWin32Execution, supportsWin64Execution, architectureCapabilities, wineMono, wineGecko, d3dmetal, dxmt, dxvk, d9vk, vkd3d
        case esync, msync, fullscreenFSR, fullscreenFSRCapabilities, wineBusControllerMapping, dgVoodoo2, graphicsCapabilities
    }

    init(wow64: Bool, supportsWin32Execution: Bool? = nil, supportsWin64Execution: Bool? = nil, architectureCapabilities: RuntimeArchitectureCapabilities? = nil, wineMono: Bool, wineGecko: Bool, d3dmetal: Bool, dxmt: Bool, dxvk: Bool = false, d9vk: Bool = false, vkd3d: Bool = false, esync: Bool = false, msync: Bool = false, fullscreenFSR: Bool = false, fullscreenFSRCapabilities: FullscreenFSRCapabilities? = nil, wineBusControllerMapping: Bool = false, dgVoodoo2: Bool = false) {
        self.wow64 = wow64
        self.architectureCapabilities = architectureCapabilities
        self.supportsWin32Execution = supportsWin32Execution ?? architectureCapabilities?.canRunX86
        self.supportsWin64Execution = supportsWin64Execution ?? architectureCapabilities?.canRunX86_64
        self.wineMono = wineMono
        self.wineGecko = wineGecko
        self.d3dmetal = d3dmetal
        self.dxmt = dxmt
        self.dxvk = dxvk || d9vk
        self.vkd3d = vkd3d
        self.esync = esync
        self.msync = msync
        self.fullscreenFSR = fullscreenFSR
        self.fullscreenFSRCapabilities = fullscreenFSRCapabilities
        self.wineBusControllerMapping = wineBusControllerMapping
        self.dgVoodoo2 = dgVoodoo2
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        wow64 = try values.decodeIfPresent(Bool.self, forKey: .wow64) ?? false
        supportsWin32Execution = try values.decodeIfPresent(Bool.self, forKey: .supportsWin32Execution)
        supportsWin64Execution = try values.decodeIfPresent(Bool.self, forKey: .supportsWin64Execution)
        architectureCapabilities = try values.decodeIfPresent(RuntimeArchitectureCapabilities.self, forKey: .architectureCapabilities)
        wineMono = try values.decodeIfPresent(Bool.self, forKey: .wineMono) ?? false
        wineGecko = try values.decodeIfPresent(Bool.self, forKey: .wineGecko) ?? false
        d3dmetal = try values.decodeIfPresent(Bool.self, forKey: .d3dmetal) ?? false
        dxmt = try values.decodeIfPresent(Bool.self, forKey: .dxmt) ?? false
        let storedDXVK = try values.decodeIfPresent(Bool.self, forKey: .dxvk) ?? false
        let storedLegacyD9VK = try values.decodeIfPresent(Bool.self, forKey: .d9vk) ?? false
        dxvk = storedDXVK || storedLegacyD9VK
        vkd3d = try values.decodeIfPresent(Bool.self, forKey: .vkd3d) ?? false
        esync = try values.decodeIfPresent(Bool.self, forKey: .esync) ?? false
        msync = try values.decodeIfPresent(Bool.self, forKey: .msync) ?? false
        fullscreenFSR = try values.decodeIfPresent(Bool.self, forKey: .fullscreenFSR) ?? false
        fullscreenFSRCapabilities = try values.decodeIfPresent(FullscreenFSRCapabilities.self, forKey: .fullscreenFSRCapabilities)
        wineBusControllerMapping = try values.decodeIfPresent(Bool.self, forKey: .wineBusControllerMapping) ?? false
        dgVoodoo2 = try values.decodeIfPresent(Bool.self, forKey: .dgVoodoo2) ?? false
        graphicsCapabilities = try values.decodeIfPresent([String: GraphicsBackendCapabilities].self, forKey: .graphicsCapabilities)
    }

    /// Compatibility accessor for callers and persisted data from the period
    /// when D9VK was modelled as a separate backend. D9VK is now part of DXVK.
    var d9vk: Bool { dxvk }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(wow64, forKey: .wow64)
        try values.encodeIfPresent(supportsWin32Execution, forKey: .supportsWin32Execution)
        try values.encodeIfPresent(supportsWin64Execution, forKey: .supportsWin64Execution)
        try values.encodeIfPresent(architectureCapabilities, forKey: .architectureCapabilities)
        try values.encode(wineMono, forKey: .wineMono)
        try values.encode(wineGecko, forKey: .wineGecko)
        try values.encode(d3dmetal, forKey: .d3dmetal)
        try values.encode(dxmt, forKey: .dxmt)
        try values.encode(dxvk, forKey: .dxvk)
        try values.encode(vkd3d, forKey: .vkd3d)
        try values.encode(esync, forKey: .esync)
        try values.encode(msync, forKey: .msync)
        try values.encode(fullscreenFSR, forKey: .fullscreenFSR)
        try values.encodeIfPresent(fullscreenFSRCapabilities, forKey: .fullscreenFSRCapabilities)
        try values.encode(wineBusControllerMapping, forKey: .wineBusControllerMapping)
        try values.encode(dgVoodoo2, forKey: .dgVoodoo2)
        try values.encodeIfPresent(graphicsCapabilities, forKey: .graphicsCapabilities)
    }

    /// Backwards-compatible capability projection for manifests written
    /// before the explicit architecture probe was introduced.
    var resolvedArchitectureCapabilities: RuntimeArchitectureCapabilities {
        architectureCapabilities ?? RuntimeArchitectureCapabilities(
            canRunX86: supportsWin32Execution ?? wow64,
            canRunX86_64: supportsWin64Execution ?? true,
            usesNewWoW64: wow64,
            supportsLegacyWin32Prefix: !wow64
        )
    }

    var supportsWoW64: Bool { resolvedArchitectureCapabilities.usesNewWoW64 }
}

nonisolated enum RuntimeComponent: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case dxmt
    case dxvk
    case vkd3d

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "d9vk": self = .dxvk
        default:
            guard let component = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unknown runtime component: \(value)"
                )
            }
            self = component
        }
    }

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .vkd3d: "VKD3D-Proton"
        }
    }
    var directoryName: String {
        switch self {
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .vkd3d: "VKD3D"
        }
    }
}

/// Exact immutable component snapshot selected by an environment. The digest
/// is mandatory for published/downloaded components and is also used for
/// locally imported snapshots.
nonisolated struct GraphicsComponentReference: Codable, Sendable, Hashable {
    let component: RuntimeComponent
    let version: String
    let sha256: String
    let installedFiles: [String]
}

/// Windows redistributables belong to a mutable game environment, never to
/// the immutable runtime package or the user's global Wine prefix.
nonisolated enum RuntimeDependency: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case legacyDirectX, vc2010, vc2015To2022, xact, xinput, dotNetFramework, physX

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "directXRuntime": self = .legacyDirectX
        default:
            guard let dependency = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unknown runtime dependency: \(value)"
                )
            }
            self = dependency
        }
    }
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .legacyDirectX: "Legacy DirectX runtime"
        case .vc2010: "VC++ 2010"
        case .vc2015To2022: "VC++ 2015–2022"
        case .xact: "XACT"
        case .xinput: "XInput"
        case .dotNetFramework: ".NET Framework"
        case .physX: "PhysX"
        }
    }
    var winetricksVerb: String {
        switch self {
        case .legacyDirectX: "d3dx9"
        case .vc2010: "vcrun2010"
        case .vc2015To2022: "vcrun2022"
        case .xact: "xact"
        case .xinput: "xinput"
        case .dotNetFramework: "dotnet48"
        case .physX: "physx"
        }
    }
    var detectionLibraries: [String] {
        switch self {
        case .legacyDirectX: ["d3dx9_43.dll", "d3dcompiler_43.dll"]
        case .vc2010: ["msvcp100.dll", "msvcr100.dll"]
        case .vc2015To2022: ["msvcp140.dll", "vcruntime140.dll"]
        case .xact: ["xactengine3_7.dll"]
        case .xinput: ["xinput1_3.dll", "xinput1_4.dll"]
        case .dotNetFramework: ["mscoree.dll"]
        case .physX: ["PhysXLoader.dll"]
        }
    }
}

nonisolated enum RuntimeDependencyState: String, Codable, Sendable, Hashable {
    case installed, missing, installing, failed
}

nonisolated enum RuntimeDependencyRecommendation: String, Codable, Sendable, Hashable {
    case required, recommended, optional
}

nonisolated struct RuntimeDependencyStatus: Identifiable, Codable, Sendable, Hashable {
    var id: RuntimeDependency { dependency }
    let dependency: RuntimeDependency
    var state: RuntimeDependencyState
    var detail: String?
    var recommendation: RuntimeDependencyRecommendation = .optional
}

nonisolated enum RuntimeDependencyResolver {
    static func resolve(executableURL: URL?) -> [RuntimeDependency: (RuntimeDependencyRecommendation, String)] {
        var result: [RuntimeDependency: (RuntimeDependencyRecommendation, String)] = [
            .vc2015To2022: (.recommended, "Common runtime for modern Windows games"),
            .xinput: (.recommended, "Common controller API for Windows games"),
            .legacyDirectX: (.optional, "Install only when the game needs legacy DirectX components"),
            .vc2010: (.optional, "Install only for games built with Visual C++ 2010"),
            .xact: (.optional, "Install only for games using legacy XACT audio"),
            .dotNetFramework: (.optional, "Install only when this game explicitly requires .NET Framework"),
            .physX: (.optional, "Install only for games that use NVIDIA PhysX")
        ]
        guard let executableURL,
              let data = try? Data(contentsOf: executableURL, options: [.mappedIfSafe]),
              !data.isEmpty else { return result }

        // PE import names are ASCII. Scanning the memory-mapped bytes also
        // catches delay-loaded imports without executing or modifying the game.
        func containsImport(_ name: String) -> Bool {
            let lower = Data(name.lowercased().utf8)
            let upper = Data(name.uppercased().utf8)
            return data.range(of: lower) != nil || data.range(of: upper) != nil
        }
        let evidence: [(RuntimeDependency, [String], String)] = [
            (.legacyDirectX, ["d3dx9_", "d3dcompiler_43.dll"], "Required by this executable's legacy DirectX imports"),
            (.vc2010, ["msvcp100.dll", "msvcr100.dll"], "Required by this executable's Visual C++ 2010 imports"),
            (.vc2015To2022, ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"], "Required by this executable's Visual C++ runtime imports"),
            (.xact, ["xactengine"], "Required by this executable's XACT audio import"),
            (.xinput, ["xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"], "Required by this executable's controller API import"),
            (.dotNetFramework, ["mscoree.dll"], "Required by this managed .NET executable"),
            (.physX, ["physxloader.dll", "physx3"], "Required by this executable's NVIDIA PhysX import")
        ]
        for (dependency, names, detail) in evidence where names.contains(where: containsImport) {
            result[dependency] = (.required, detail)
        }
        return result
    }
}

nonisolated struct RuntimeComponentReceipt: Codable, Sendable, Hashable {
    let component: RuntimeComponent
    let version: String
    let sourceRepository: String
    let installedAt: Date
    let sha256: String
    let compressedSize: Int64?
    let installedFiles: [String]

    init(
        component: RuntimeComponent,
        version: String,
        sourceRepository: String,
        installedAt: Date,
        sha256: String = "",
        compressedSize: Int64? = nil,
        installedFiles: [String] = []
    ) {
        self.component = component
        self.version = version
        self.sourceRepository = sourceRepository
        self.installedAt = installedAt
        self.sha256 = sha256
        self.compressedSize = compressedSize
        self.installedFiles = installedFiles
    }

    private enum CodingKeys: String, CodingKey {
        case component, version, sourceRepository, installedAt, sha256, compressedSize, installedFiles
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        component = try values.decode(RuntimeComponent.self, forKey: .component)
        version = try values.decode(String.self, forKey: .version)
        sourceRepository = try values.decode(String.self, forKey: .sourceRepository)
        installedAt = try values.decode(Date.self, forKey: .installedAt)
        sha256 = try values.decodeIfPresent(String.self, forKey: .sha256) ?? ""
        compressedSize = try values.decodeIfPresent(Int64.self, forKey: .compressedSize)
        installedFiles = try values.decodeIfPresent([String].self, forKey: .installedFiles) ?? []
    }
}

nonisolated struct UpscalingBridgeReceipt: Codable, Sendable, Hashable {
    let bridge: TemporalUpscalingBridge
    let version: String
    let sourceRuntimeID: String
    let installedAt: Date
    let sha256: String
    let installedFiles: [String]

    init(
        bridge: TemporalUpscalingBridge,
        version: String,
        sourceRuntimeID: String,
        installedAt: Date,
        sha256: String,
        installedFiles: [String]
    ) {
        self.bridge = bridge
        self.version = version
        self.sourceRuntimeID = sourceRuntimeID
        self.installedAt = installedAt
        self.sha256 = sha256
        self.installedFiles = installedFiles
    }
}

nonisolated struct RuntimeComponentUpdate: Identifiable, Sendable, Hashable {
    enum State: Sendable, Hashable { case notInstalled, current, available }
    var id: String { "\(runtimeID):\(component.rawValue)" }
    let runtimeID: String
    let runtimeName: String
    let component: RuntimeComponent
    let installedVersion: String?
    let latestVersion: String
    let state: State
}

nonisolated enum WindowsExecutableArchitecture: String, Codable, Hashable, Sendable {
    case x86, x86_64, unknown

    static func inspect(_ url: URL) -> Self {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 64),
              header.count >= 64,
              header[0] == 0x4D,
              header[1] == 0x5A else { return .unknown }

        let peOffset = Int(header[60])
            | (Int(header[61]) << 8)
            | (Int(header[62]) << 16)
            | (Int(header[63]) << 24)
        guard peOffset >= 0,
              (try? handle.seek(toOffset: UInt64(peOffset))) != nil,
              let peHeader = try? handle.read(upToCount: 26),
              peHeader.count >= 26,
              Array(peHeader.prefix(4)) == [0x50, 0x45, 0x00, 0x00] else { return .unknown }

        let optionalHeaderMagic = UInt16(peHeader[24]) | (UInt16(peHeader[25]) << 8)
        switch optionalHeaderMagic {
        case 0x10B: return .x86
        case 0x20B: return .x86_64
        default: return .unknown
        }
    }
}

/// Modern Unity IL2CPP builds depend on Windows Runtime API-set imports that
/// are not available in the legacy GPTK runtime shipped with older Boreal
/// installations. Route these builds through the maintained Wine runtime.
nonisolated enum UnityIL2CPPRuntimeCompatibility {
    static func requiresModernWine(at executable: URL, fileManager: FileManager = .default) -> Bool {
        guard WindowsExecutableArchitecture.inspect(executable) == .x86_64 else { return false }
        let gameDirectory = executable.deletingLastPathComponent()
        return fileManager.fileExists(atPath: gameDirectory.appending(path: "GameAssembly.dll").path)
            && fileManager.fileExists(atPath: gameDirectory.appending(path: "UnityPlayer.dll").path)
    }

    static func recommendedRuntimeEngine(for executable: URL) -> RuntimeEngine {
        if requiresModernWine(at: executable) { return .wine }
        // PE bitness is a runtime constraint, not a Wine/GPTK selector. Keep
        // the neutral Wine default for the UI; RuntimeManaging can still pick
        // any compatible installed runtime when no engine is explicitly set.
        return .wine
    }

    static func recommendedGraphicsAPI(for executable: URL, fileManager: FileManager = .default) -> GraphicsAPI? {
        // This UnityPlayer build contains the D3D11 graphics entry point.
        // D3D12 strings are also present for optional Unity code paths, so
        // raw string detection in the main executable must not select D3D12.
        guard requiresModernWine(at: executable, fileManager: fileManager) else { return nil }
        let unityPlayer = executable.deletingLastPathComponent().appending(path: "UnityPlayer.dll")
        guard let data = try? Data(contentsOf: unityPlayer, options: [.mappedIfSafe]) else { return nil }
        let text = String(decoding: data, as: UTF8.self).lowercased()
        return text.contains("d3d11.dll") ? .directX11 : nil
    }
}

nonisolated struct RuntimeArtifact: Codable, Sendable, Hashable {
    let url: URL
    let sha256: String
    let compressedSize: Int64
}

nonisolated struct RuntimeComponents: Codable, Sendable, Hashable {
    var mono: String? = nil
    var gecko: String? = nil
}

nonisolated struct RuntimeLayout: Codable, Sendable, Hashable {
    var wineExecutable: String
    var wineServerExecutable: String
    var wineBootExecutable: String
    var dependenciesDirectory: String
    var supportDirectory: String
    var licensesDirectory: String
    var noticesFile: String
    var sbomFile: String

    static let canonical = RuntimeLayout(
        wineExecutable: "Runtime/Wine.app/Contents/Resources/wine/bin/wine",
        wineServerExecutable: "Runtime/Wine.app/Contents/Resources/wine/bin/wineserver",
        wineBootExecutable: "Runtime/Wine.app/Contents/Resources/wine/bin/wineboot",
        dependenciesDirectory: "Dependencies",
        supportDirectory: "Support",
        licensesDirectory: "Licenses",
        noticesFile: "Licenses/THIRD_PARTY_NOTICES.txt",
        sbomFile: "SBOM.spdx.json"
    )
}

nonisolated struct RuntimePackageManifest: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let id: String
    let displayName: String
    let wineVersion: String
    let borealRevision: Int
    let architecture: RuntimeArchitecture
    let minimumMacOS: String
    let requiresRosetta: Bool
    let channel: RuntimeChannel
    let engine: RuntimeEngine
    let features: RuntimeFeatures
    let components: RuntimeComponents
    let layout: RuntimeLayout

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, displayName, wineVersion, borealRevision, architecture, minimumMacOS, requiresRosetta, channel, engine, features, components, layout
    }

    init(
        schemaVersion: Int,
        id: String,
        displayName: String,
        wineVersion: String,
        borealRevision: Int = 1,
        architecture: RuntimeArchitecture,
        minimumMacOS: String,
        requiresRosetta: Bool,
        channel: RuntimeChannel,
        engine: RuntimeEngine = .wine,
        features: RuntimeFeatures,
        components: RuntimeComponents = RuntimeComponents(),
        layout: RuntimeLayout = .canonical
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.wineVersion = wineVersion
        self.borealRevision = borealRevision
        self.architecture = architecture
        self.minimumMacOS = minimumMacOS
        self.requiresRosetta = requiresRosetta
        self.channel = channel
        self.engine = engine
        self.features = features
        self.components = components
        self.layout = layout
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        id = try values.decode(String.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        wineVersion = try values.decode(String.self, forKey: .wineVersion)
        borealRevision = try values.decodeIfPresent(Int.self, forKey: .borealRevision) ?? 1
        architecture = try values.decode(RuntimeArchitecture.self, forKey: .architecture)
        minimumMacOS = try values.decode(String.self, forKey: .minimumMacOS)
        requiresRosetta = try values.decodeIfPresent(Bool.self, forKey: .requiresRosetta) ?? false
        channel = try values.decode(RuntimeChannel.self, forKey: .channel)
        features = try values.decode(RuntimeFeatures.self, forKey: .features)
        // Old package manifests encoded GPTK only through d3dmetal. Accept
        // that format on read, while every manifest Boreal writes is explicit.
        engine = try values.decodeIfPresent(RuntimeEngine.self, forKey: .engine)
            ?? (features.d3dmetal ? .gamePortingToolkit : .wine)
        components = try values.decodeIfPresent(RuntimeComponents.self, forKey: .components) ?? RuntimeComponents()
        layout = try values.decodeIfPresent(RuntimeLayout.self, forKey: .layout) ?? .canonical
    }
}

nonisolated struct BorealRuntime: Codable, Identifiable, Sendable, Hashable {
    let schemaVersion: Int
    let id: String
    let displayName: String
    let wineVersion: String
    let borealRevision: Int
    let architecture: RuntimeArchitecture
    let minimumMacOS: String
    let channel: RuntimeChannel
    let engine: RuntimeEngine
    let requirements: Set<RuntimeRequirement>
    let features: RuntimeFeatures
    let components: RuntimeComponents
    let layout: RuntimeLayout
    let artifact: RuntimeArtifact

    var packageManifest: RuntimePackageManifest {
        RuntimePackageManifest(
            schemaVersion: schemaVersion,
            id: id,
            displayName: displayName,
            wineVersion: wineVersion,
            borealRevision: borealRevision,
            architecture: architecture,
            minimumMacOS: minimumMacOS,
            requiresRosetta: requirements.contains(.rosetta2),
            channel: channel,
            engine: engine,
            features: features,
            components: components,
            layout: layout
        )
    }

    init(
        schemaVersion: Int,
        id: String,
        displayName: String,
        wineVersion: String,
        borealRevision: Int = 1,
        architecture: RuntimeArchitecture,
        minimumMacOS: String,
        channel: RuntimeChannel,
        engine: RuntimeEngine = .wine,
        requirements: Set<RuntimeRequirement>,
        features: RuntimeFeatures,
        components: RuntimeComponents = RuntimeComponents(),
        layout: RuntimeLayout = .canonical,
        artifact: RuntimeArtifact
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.wineVersion = wineVersion
        self.borealRevision = borealRevision
        self.architecture = architecture
        self.minimumMacOS = minimumMacOS
        self.channel = channel
        self.engine = engine
        self.requirements = requirements
        self.features = features
        self.components = components
        self.layout = layout
        self.artifact = artifact
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, displayName, wineVersion, borealRevision, architecture, minimumMacOS, requiresRosetta, channel, engine, requirements, features, components, layout, artifact
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        id = try values.decode(String.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        wineVersion = try values.decode(String.self, forKey: .wineVersion)
        borealRevision = try values.decodeIfPresent(Int.self, forKey: .borealRevision) ?? 1
        architecture = try values.decode(RuntimeArchitecture.self, forKey: .architecture)
        minimumMacOS = try values.decode(String.self, forKey: .minimumMacOS)
        channel = try values.decode(RuntimeChannel.self, forKey: .channel)
        let decodedFeatures = try values.decode(RuntimeFeatures.self, forKey: .features)
        features = decodedFeatures
        engine = try values.decodeIfPresent(RuntimeEngine.self, forKey: .engine)
            ?? (decodedFeatures.d3dmetal ? .gamePortingToolkit : .wine)
        var decodedRequirements = try values.decodeIfPresent(Set<RuntimeRequirement>.self, forKey: .requirements) ?? []
        if try values.decodeIfPresent(Bool.self, forKey: .requiresRosetta) == true { decodedRequirements.insert(.rosetta2) }
        requirements = decodedRequirements
        components = try values.decodeIfPresent(RuntimeComponents.self, forKey: .components) ?? RuntimeComponents()
        layout = try values.decodeIfPresent(RuntimeLayout.self, forKey: .layout) ?? .canonical
        artifact = try values.decode(RuntimeArtifact.self, forKey: .artifact)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(wineVersion, forKey: .wineVersion)
        try values.encode(borealRevision, forKey: .borealRevision)
        try values.encode(architecture, forKey: .architecture)
        try values.encode(minimumMacOS, forKey: .minimumMacOS)
        try values.encode(requirements.contains(.rosetta2), forKey: .requiresRosetta)
        try values.encode(channel, forKey: .channel)
        try values.encode(engine, forKey: .engine)
        try values.encode(requirements, forKey: .requirements)
        try values.encode(features, forKey: .features)
        try values.encode(components, forKey: .components)
        try values.encode(layout, forKey: .layout)
        try values.encode(artifact, forKey: .artifact)
    }
}

nonisolated struct InstalledRuntime: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let wineVersion: String
    let rootURL: URL
    let wineExecutable: URL
    let wineServerExecutable: URL
    let wineBootExecutable: URL
    let architecture: RuntimeArchitecture
    let requirements: Set<RuntimeRequirement>
    var origin: RuntimeOrigin? = nil
    var engine: RuntimeEngine? = nil
    var features: RuntimeFeatures? = nil

    var resolvedEngine: RuntimeEngine {
        engine ?? (features?.d3dmetal == true ? .gamePortingToolkit : .wine)
    }

    var runtimeDescription: String { "\(displayName) · \(resolvedEngine.displayName) \(wineVersion)" }
    var graphicsName: String { resolvedEngine.graphicsName }
}

nonisolated struct LocalRuntimeCandidate: Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let wineVersion: String
    let appURL: URL
    let architecture: RuntimeArchitecture
    let requirements: Set<RuntimeRequirement>
    let minimumMacOS: String
    let estimatedSize: Int64?
    var engine: RuntimeEngine = .wine
    var features: RuntimeFeatures = RuntimeFeatures(wow64: false, wineMono: false, wineGecko: false, d3dmetal: false, dxmt: false)
    var layout: RuntimeLayout = .canonical
}

nonisolated struct RuntimeValidation: Sendable, Equatable {
    var detectedWineVersion: String?
    var versionMatchesManifest: Bool
    var missingPaths: [String]
    var unmetRequirements: Set<RuntimeRequirement>
    var executablePaths: [String]
    var isReady: Bool { missingPaths.isEmpty && unmetRequirements.isEmpty && detectedWineVersion != nil && versionMatchesManifest }
}

nonisolated enum RuntimeManagerError: LocalizedError, Sendable {
    case invalidManifest
    case manifestSignatureInvalid
    case alreadyInstalled(String)
    case checksumMismatch(expected: String, actual: String)
    case unsupportedArchive
    case runtimeLayoutNotFound
    case packageManifestMismatch
    case unsafeArchive(String)
    case nonSelfContained(RuntimeRequirement)
    case validationFailed(RuntimeValidation)
    case requirementMissing(RuntimeRequirement)
    case downloadFailed(String)
    case localRuntimeInvalid(String)
    case incompatible32BitExecutable(runtime: String)
    case incompatible64BitExecutable
    case noCompatibleRuntime(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "The runtime manifest is invalid."
        case .manifestSignatureInvalid: return "The runtime manifest signature is invalid."
        case .alreadyInstalled(let id): return "Runtime \(id) is already installed."
        case .checksumMismatch: return "Runtime verification failed because its SHA-256 checksum does not match."
        case .unsupportedArchive: return "The runtime archive format is not supported."
        case .runtimeLayoutNotFound: return "Boreal couldn’t locate Wine inside the runtime package."
        case .packageManifestMismatch: return "The runtime package manifest does not match the signed catalog entry."
        case .unsafeArchive(let path): return "The runtime archive contains an unsafe path: \(path)"
        case .nonSelfContained(.gStreamerFramework): return "This runtime depends on a system GStreamer installation and is not self-contained."
        case .nonSelfContained(.rosetta2): return "Rosetta is a platform requirement, not a bundled runtime dependency."
        case .validationFailed(let validation):
            var details: [String] = []
            if !validation.missingPaths.isEmpty {
                details.append("Missing or incomplete: \(validation.missingPaths.joined(separator: ", "))")
            }
            if !validation.unmetRequirements.isEmpty {
                let requirements = validation.unmetRequirements.map {
                    switch $0 {
                    case .rosetta2: "Rosetta 2"
                    case .gStreamerFramework: "GStreamer.framework"
                    }
                }.sorted()
                details.append("Unmet requirements: \(requirements.joined(separator: ", "))")
            }
            if validation.detectedWineVersion == nil {
                details.append("Wine did not return a version.")
            } else if !validation.versionMatchesManifest {
                details.append("Detected Wine version does not match the imported app.")
            }
            return details.isEmpty
                ? "The installed runtime did not pass validation."
                : "The installed runtime did not pass validation. \(details.joined(separator: " "))"
        case .requirementMissing(.rosetta2): return "Rosetta 2 is required by this runtime."
        case .requirementMissing(.gStreamerFramework): return "GStreamer.framework is required by this development runtime."
        case .downloadFailed(let reason): return "Runtime download failed: \(reason)"
        case .localRuntimeInvalid(let reason): return "The installed Wine app can’t be imported: \(reason)"
        case .incompatible32BitExecutable(let runtime): return "This game is 32-bit, but \(runtime) does not provide WoW64 support. Use a Wine runtime that supports 32-bit Windows applications."
        case .incompatible64BitExecutable: return "This application is 64-bit and cannot run in a 32-bit Wine prefix. Choose the Win64 architecture."
        case .noCompatibleRuntime(let detail): return "No compatible runtime is available. \(detail)"
        }
    }
}

nonisolated protocol RuntimeManaging: Sendable {
    func availableRuntimes() async throws -> [BorealRuntime]
    func installedRuntimes() async throws -> [InstalledRuntime]
    func localRuntimeCandidates() async -> [LocalRuntimeCandidate]
    func importLocalRuntime(_ candidate: LocalRuntimeCandidate) async throws -> InstalledRuntime
    func install(_ runtime: BorealRuntime) async throws -> InstalledRuntime
    func validate(_ runtime: InstalledRuntime) async throws -> RuntimeValidation
    func remove(_ runtime: InstalledRuntime) async throws
    func installGraphicsComponent(
        _ backend: WineGraphicsBackend,
        from source: URL,
        into runtimeID: String
    ) async throws -> InstalledRuntime
    func downloadAndInstallGraphicsComponent(
        _ backend: WineGraphicsBackend,
        into runtimeID: String
    ) async throws -> InstalledRuntime
    func componentUpdates() async throws -> [RuntimeComponentUpdate]
    func downloadAndInstallComponent(_ component: RuntimeComponent, into runtimeID: String) async throws -> InstalledRuntime
    func installUpscalingBridge(_ bridge: TemporalUpscalingBridge, fromRuntimeID runtimeID: String) async throws -> UpscalingBridgeReference
    func upscalingBridgeReferences(_ bridge: TemporalUpscalingBridge) async throws -> [UpscalingBridgeReference]
}

nonisolated extension RuntimeManaging {
    func componentUpdates() async throws -> [RuntimeComponentUpdate] { [] }
    func downloadAndInstallComponent(_ component: RuntimeComponent, into runtimeID: String) async throws -> InstalledRuntime {
        if component == .dxmt { return try await downloadAndInstallGraphicsComponent(.dxmt, into: runtimeID) }
        if component == .dxvk { return try await downloadAndInstallGraphicsComponent(.dxvk, into: runtimeID) }
        throw CocoaError(.featureUnsupported)
    }

    func installUpscalingBridge(_ bridge: TemporalUpscalingBridge, fromRuntimeID runtimeID: String) async throws -> UpscalingBridgeReference {
        throw CocoaError(.featureUnsupported)
    }

    func upscalingBridgeReferences(_ bridge: TemporalUpscalingBridge) async throws -> [UpscalingBridgeReference] { [] }
    func installGraphicsComponent(
        _ backend: WineGraphicsBackend,
        from source: URL,
        into runtimeID: String
    ) async throws -> InstalledRuntime {
        throw CocoaError(.featureUnsupported)
    }

    func downloadAndInstallGraphicsComponent(
        _ backend: WineGraphicsBackend,
        into runtimeID: String
    ) async throws -> InstalledRuntime {
        throw CocoaError(.featureUnsupported)
    }
}
