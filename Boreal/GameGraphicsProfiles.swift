import Foundation

nonisolated enum GameRuntimeProfiles {
    static func requiredEngine(provider: GameLibraryProvider, externalID: String) -> RuntimeEngine? {
        switch (provider, externalID) {
        case (.gog, "1887281589"), (.steam, "1466060"):
            // Unity 6 needs D3D11 feature level 11, which WineD3D cannot
            // expose on Apple Silicon. Boreal supplies the missing WinRT API
            // alias in the prefix so GPTK can load IL2CPP and use D3DMetal.
            return .gamePortingToolkit
        case (.gog, "1635210189"):
            // GreedFall is a 64-bit DirectX 11 title. Use the current GPTK
            // WoW64 runtime so its D3DMetal path is selected instead of the
            // legacy GPTK build that cannot create a modern WoW64 prefix.
            return .gamePortingToolkit
        case (.gog, "1711230643"):
            // Skyrim Special Edition is a 64-bit DirectX 11 title. Keep it
            // away from stale GPTK/D3DMetal snapshots and WineD3D.
            return .wine
        default:
            return nil
        }
    }

    static func requiredEngine(for application: WindowsApplication) -> RuntimeEngine? {
        guard let provider = application.storeProvider,
              let externalID = application.storeExternalID else { return nil }
        return requiredEngine(provider: provider, externalID: externalID)
    }

    static func requiredEngine(for game: StoreLibraryGame) -> RuntimeEngine? {
        requiredEngine(provider: game.provider, externalID: game.externalID)
    }
}

nonisolated enum GameGraphicsProfiles {
    static let builtIn: [GameGraphicsProfile] = [
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1711230643",
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [GraphicsAPILaunchOption(api: .directX11, arguments: [])],
            preferredBackend: .dxvk,
            enforcedBackend: .dxvk,
            enforcedAPI: .directX11,
            overlayCompatibleFullscreen: true
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1887281589",
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [GraphicsAPILaunchOption(api: .directX11, arguments: [])],
            preferredBackend: .d3dMetal,
            enforcedBackend: .d3dMetal,
            overlayCompatibleFullscreen: true,
            launchEnvironment: ["WINEDLLOVERRIDES": "Rewired_WindowsGamingInput="]
        ),
        GameGraphicsProfile(
            provider: .steam,
            externalID: "1466060",
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [GraphicsAPILaunchOption(api: .directX11, arguments: [])],
            preferredBackend: .d3dMetal,
            enforcedBackend: .d3dMetal,
            overlayCompatibleFullscreen: true,
            launchEnvironment: ["WINEDLLOVERRIDES": "Rewired_WindowsGamingInput="]
        ),
        GameGraphicsProfile(
            provider: .steam,
            externalID: "1593500",
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX11, arguments: [])
            ],
            // God of War's D3D11 shaders use atomic results whose unused
            // components must stay undefined. DXMT 0.40 and newer fixed the
            // translation path that made those components visible as white
            // flickering pixels on character materials.
            preferredBackend: .dxmt,
            overlayCompatibleFullscreen: true,
            // These are DXMT's per-process shader translation workarounds for
            // the remaining God of War artifacts. Keep them scoped to this
            // game; applying them globally would change unrelated D3D11 games.
            launchEnvironment: [
                "DXMT_CONFIG": "d3d11.sampleNaNToZero=True;d3d11.defuseFma=True;dxmt.shaderMetalVersion=310;"
            ]
        ),
        GameGraphicsProfile(
            provider: .steam,
            externalID: GameLaunchCompatibility.gtaSanAndreasDefinitiveEditionSteamAppID,
            availableAPIs: [.directX12],
            defaultAPI: .directX12,
            launchOptions: [
                // GTA SA Definitive Edition's DLSS integration and the
                // linked DLSS Unlocker both require the game's DX12 path.
                GraphicsAPILaunchOption(api: .directX12, arguments: ["-dx12"])
            ],
            preferredBackend: .d3dMetal,
            overlayCompatibleFullscreen: true,
            // GTA SA:DE's OptiScaler compatibility path is documented with
            // the DX12 proxy. Keep the global automatic resolver unchanged;
            // this game-specific default avoids the DXGI loader path that
            // has failed during startup on this title.
            preferredOptiScalerProxy: "d3d12.dll",
            // D3DMetal does not expose patchable ID3D12Device vtable methods;
            // keeping HUD resource tracking enabled produces error 57 in
            // every Present and prevents a stable OptiFG path.
            preferredOptiScalerHUDHandling: .off,
            preferredOptiScalerUpscalerInput: .dlss,
            preferredOptiScalerPreserveSwapChain: true,
            preferredOptiScalerSkipResizeBuffers: true
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1889754300",
            availableAPIs: [.directX12],
            defaultAPI: .directX12,
            launchOptions: [GraphicsAPILaunchOption(api: .directX12, arguments: [])],
            preferredBackend: .d3dMetal,
            enforcedBackend: .d3dMetal,
            enforcedAPI: .directX12,
            // Dawnwalker's UE build resolves its IoStore Global shader library
            // relative to the game process. Launching it through explorer's
            // virtual desktop leaves the executable alive, but initialization
            // reports the existing Content/Paks shader containers as missing.
            overlayCompatibleFullscreen: false
        ),
        GameGraphicsProfile(
            provider: .steam,
            externalID: "3751260",
            availableAPIs: [.directX12],
            defaultAPI: .directX12,
            launchOptions: [GraphicsAPILaunchOption(api: .directX12, arguments: [])],
            preferredBackend: .d3dMetal,
            enforcedBackend: .d3dMetal,
            enforcedAPI: .directX12,
            // Keep compatibility with the currently persisted Steam metadata
            // record for this installation; the GOG build uses the profile above.
            overlayCompatibleFullscreen: false
        ),
        GameGraphicsProfile(
            provider: .steam,
            externalID: "475150",
            availableAPIs: [.directX11, .directX9],
            defaultAPI: .directX11,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX11, arguments: ["/dx11"]),
                GraphicsAPILaunchOption(api: .directX9, arguments: ["/dx9"])
            ]
        ),
        GameGraphicsProfile(
            provider: .steam,
            externalID: "200710",
            availableAPIs: [.directX9],
            defaultAPI: .directX9,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX9, arguments: [])
            ],
            // Torchlight II reaches its world renderer through D3D9. On the
            // current Wine/MoltenVK path, DXVK fails buffer creation during
            // that transition, while WineD3D is the compatible fallback.
            preferredBackend: .wineD3D,
            enforcedBackend: .wineD3D,
            overlayCompatibleFullscreen: true
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1949616134",
            availableAPIs: [.directX9],
            defaultAPI: .directX9,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX9, arguments: [])
            ],
            // Dragon Age: Origins reaches its D3D9 device with WineD3D's
            // Vulkan renderer, but MoltenVK rejects the first game buffer on
            // Apple Silicon and Wine terminates with an access violation.
            // Keep this title on WineD3D's OpenGL renderer instead of feeding
            // the same failure back into the generic Vulkan fallback.
            preferredBackend: .wineD3D,
            enforcedBackend: .wineD3D,
            overlayCompatibleFullscreen: true,
            launchEnvironment: ["WINE_D3D_CONFIG": "renderer=gl"]
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "2015389384",
            availableAPIs: [.directX9],
            defaultAPI: .directX9,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX9, arguments: [])
            ],
            // Gunslinger is a 32-bit DirectX 9 game. Both D9VK and WineD3D's
            // Vulkan renderer fail while creating buffers through MoltenVK on
            // Apple Silicon. Keep this title on WineD3D's OpenGL renderer.
            preferredBackend: .wineD3D,
            enforcedBackend: .wineD3D,
            enforcedAPI: .directX9,
            overlayCompatibleFullscreen: true,
            launchEnvironment: [
                "WINE_D3D_CONFIG": "renderer=gl",
                // Wine's WMV reader enters the movie and then faults/stalls
                // before returning a frame for this title. The game handles
                // an unavailable WMV reader and continues to the menu.
                "WINEDLLOVERRIDES": "wmvcore="
            ]
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1449651388",
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX11, arguments: [])
            ],
            // Grim Dawn's 64-bit renderer uses D3D11. WineD3D's Vulkan path
            // reaches MoltenVK but crashes before presenting the first frame
            // on the current Apple Silicon runtime. DXVK is the compatible
            // translation path. Keep the game inside Boreal's virtual desktop:
            // its startup switches a 1024x720 swap chain to an exclusive
            // 1024x768 display mode, which crashes the macOS Wine window path.
            preferredBackend: .dxvk,
            enforcedBackend: .dxvk,
            overlayCompatibleFullscreen: true
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1635210189",
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX11, arguments: [])
            ],
            // GreedFall's SilkEngine is a DirectX 11 title and should use
            // Apple's D3DMetal path in a current GPTK WoW64 prefix. Keep the
            // game out of the virtual desktop while it creates its device.
            preferredBackend: .d3dMetal,
            enforcedBackend: .d3dMetal,
            enforcedAPI: .directX11,
            overlayCompatibleFullscreen: false
        ),
        GameGraphicsProfile(
            provider: .steam,
            externalID: "388410",
            availableAPIs: [.directX11, .directX9],
            // The original Deathinitive release starts in D3D9. The optional
            // -dx11 path requires a separate shader library that may not be shipped.
            defaultAPI: .directX9,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX11, arguments: ["-dx11"], requiredFile: "Darksiders2.wsl"),
                GraphicsAPILaunchOption(api: .directX9, arguments: [])
            ],
            preferredBackend: .dxvk,
            overlayCompatibleFullscreen: true
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1446463013",
            availableAPIs: [.directX11, .directX9],
            defaultAPI: .directX9,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX11, arguments: ["-dx11"], requiredFile: "Darksiders2.wsl"),
                GraphicsAPILaunchOption(api: .directX9, arguments: [])
            ],
            preferredBackend: .dxvk,
            overlayCompatibleFullscreen: true
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1787707874",
            availableAPIs: [.directX9],
            defaultAPI: .directX9,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX9, arguments: [])
            ],
            // Bound by Flame's SilkEngine reaches D3D9. The installed D9VK
            // component can create an Apple M4 device, but MoltenVK then
            // rejects the game's first buffer allocation. Keep WineD3D as
            // the honest fallback until a Metal-native D3D9 path is present.
            // The virtual explorer desktop hides this game's window on the
            // current Wine runtime, so it must use a native Wine window.
            preferredBackend: .wineD3D,
            enforcedBackend: .wineD3D,
            overlayCompatibleFullscreen: false,
            launchEnvironment: ["WINE_D3D_CONFIG": "renderer=gl"]
        ),
        GameGraphicsProfile(
            provider: .gog,
            externalID: "1207658688",
            // Sacred Gold is a 32-bit DirectDraw/Direct3D 7 title. The default
            // profile uses Boreal Legacy Graphics: a traced x86 ddraw proxy
            // with a D3D11 first-draw path backed by the selected DXMT runtime.
            availableAPIs: [.automatic, .directX9, .directX11],
            defaultAPI: .automatic,
            launchOptions: [],
            preferredBackend: .dxmt,
            preferredLegacyWrapper: LegacyGraphicsWrapper.borealLegacyGraphics,
            enforcedLegacyGraphicsAPI: .directDraw,
            overlayCompatibleFullscreen: false,
            enforcedOverlayCompatibleFullscreen: false,
            // The bundled BLG path creates D3D11 itself and relies on the
            // selected runtime's DXMT libraries. No dgVoodoo configuration is
            // written for this profile.
            legacyWrapperSettings: [:]
        )
    ]

    static func profile(for application: WindowsApplication) -> GameGraphicsProfile? {
        guard let provider = application.storeProvider,
              let externalID = application.storeExternalID else { return nil }
        return profile(provider: provider, externalID: externalID)
    }

    static func profile(provider: GameLibraryProvider, externalID: String) -> GameGraphicsProfile? {
        builtIn.first { $0.provider == provider && $0.externalID == externalID }
    }

    static func preferredOptiScalerProxy(
        provider: GameLibraryProvider?,
        externalID: String?
    ) -> String? {
        guard let provider, let externalID else { return nil }
        return profile(provider: provider, externalID: externalID)?.preferredOptiScalerProxy
    }

    static func preferredOptiScalerHUDHandling(
        provider: GameLibraryProvider?,
        externalID: String?
    ) -> OptiScalerHUDHandling? {
        guard let provider, let externalID else { return nil }
        return profile(provider: provider, externalID: externalID)?.preferredOptiScalerHUDHandling
    }

    static func preferredOptiScalerUpscalerInput(
        provider: GameLibraryProvider?,
        externalID: String?
    ) -> OptiScalerUpscalerInput? {
        guard let provider, let externalID else { return nil }
        return profile(provider: provider, externalID: externalID)?.preferredOptiScalerUpscalerInput
    }

    static func preferredOptiScalerPreserveSwapChain(
        provider: GameLibraryProvider?,
        externalID: String?
    ) -> Bool? {
        guard let provider, let externalID else { return nil }
        return profile(provider: provider, externalID: externalID)?.preferredOptiScalerPreserveSwapChain
    }

    static func preferredOptiScalerSkipResizeBuffers(
        provider: GameLibraryProvider?,
        externalID: String?
    ) -> Bool? {
        guard let provider, let externalID else { return nil }
        return profile(provider: provider, externalID: externalID)?.preferredOptiScalerSkipResizeBuffers
    }

    static func effectiveCompatibilityProfile(
        _ currentProfile: WineCompatibilityProfile,
        for application: WindowsApplication
    ) -> WineCompatibilityProfile {
        var effective = currentProfile
        if let builtIn = profile(for: application) {
            if builtIn.enforcedBackend != nil || builtIn.enforcedAPI != nil {
                effective.graphicsAPI = builtIn.defaultAPI
            }
            if let enforcedAPI = builtIn.enforcedAPI {
                effective.graphicsAPI = enforcedAPI
            }
            if let enforcedBackend = builtIn.enforcedBackend {
                effective.graphicsBackend = enforcedBackend
            }
            if let enforcedLegacyWrapper = builtIn.enforcedLegacyWrapper {
                effective.legacyWrapper = enforcedLegacyWrapper
            }
            if let enforcedLegacyGraphicsAPI = builtIn.enforcedLegacyGraphicsAPI {
                effective.legacyGraphicsAPI = enforcedLegacyGraphicsAPI
            }
            if let enforcedOverlayCompatibleFullscreen = builtIn.enforcedOverlayCompatibleFullscreen {
                effective.overlayCompatibleFullscreen = enforcedOverlayCompatibleFullscreen
            }
        }
        if GameRuntimeProfiles.requiredEngine(for: application) == .gamePortingToolkit,
           application.storeProvider == .gog,
           application.storeExternalID == "1635210189" {
            // The old persisted profile may point at GPTK 3, which advertises
            // D3DMetal but cannot create the WoW64 prefix GreedFall should
            // use. Let runtime selection choose the installed GPTK WoW64
            // build instead of preserving that stale pin.
            effective.prefixMode = .wow64
            effective.windowsVersion = .windows10
            effective.overlayCompatibleFullscreen = false
            effective.runtimeIDOverride = nil
        }
        if application.storeProvider == .gog,
           application.storeExternalID == "1711230643",
           effective.runtimeIDOverride?.contains("game-porting-toolkit") == true {
            effective.runtimeIDOverride = nil
        }
        if application.storeProvider == .gog,
           application.storeExternalID == "2015389384" {
            // Discard renderer choices persisted by the earlier D9VK and
            // WineD3D/Vulkan recovery attempts. The built-in profile above
            // is reapplied and persisted during launch.
            effective.runtimeIDOverride = nil
            effective.graphicsFallback = .none
            effective.wineD3DRenderer = .openGL
        }
        return effective
    }

    static func requiresRuntimeMigration(
        for application: WindowsApplication,
        profile: WineCompatibilityProfile,
        runtime: InstalledRuntime
    ) -> Bool {
        guard let builtIn = Self.profile(for: application),
              builtIn.enforcedBackend != nil || builtIn.enforcedAPI != nil else {
            return false
        }
        let api = profile.graphicsAPI ?? builtIn.enforcedAPI ?? builtIn.defaultAPI
        let prefixArchitecture: WinePrefixArchitecture = profile.prefixMode == .legacyWin32
            ? .win32
            : .win64
        return !GraphicsBackendResolver.resolve(
            api: api,
            requestedBackend: profile.graphicsBackend,
            gameProfile: builtIn,
            runtime: runtime,
            architecture: prefixArchitecture,
            fallback: profile.graphicsFallback
        ).isAvailable
    }

    static func legacyWrapperDecision(
        for application: WindowsApplication,
        requested profile: WineCompatibilityProfile
    ) -> LegacyWrapperDecision {
        let builtIn = Self.profile(for: application)
        let enforcement = builtIn?.enforcedLegacyWrapper
        let preference = builtIn?.preferredLegacyWrapper
        if let enforcement {
            return LegacyWrapperDecision(
                requested: profile.legacyWrapper,
                profilePreference: preference,
                profileEnforcement: enforcement,
                effective: enforcement,
                source: .profileEnforcement
            )
        }

        let matchesPreference = preference == profile.legacyWrapper
        let source: LegacyWrapperDecisionSource = matchesPreference
            ? (preference == nil ? .automaticDefault : .profilePreference)
            : .userOverride
        return LegacyWrapperDecision(
            requested: profile.legacyWrapper,
            profilePreference: preference,
            profileEnforcement: nil,
            effective: profile.legacyWrapper,
            source: source
        )
    }

    static func applying(
        _ option: GraphicsAPILaunchOption?,
        to plan: WindowsLaunchPlan,
        gameDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> WindowsLaunchPlan {
        guard let option else { return plan }
        var configured = plan
        configured.arguments.append(contentsOf: option.arguments)
        if let executableName = option.executable {
            let roots = [gameDirectory, plan.executable.deletingLastPathComponent()].compactMap { $0 }
            if let replacement = roots
                .map({ $0.appending(path: executableName) })
                .first(where: { fileManager.fileExists(atPath: $0.path) }) {
                configured.executable = replacement
                configured.workingDirectory = replacement.deletingLastPathComponent()
            }
        }
        if let requiredFile = option.requiredFile {
            let directory = gameDirectory ?? configured.workingDirectory ?? configured.executable.deletingLastPathComponent()
            let file = directory.appending(path: requiredFile)
            guard fileManager.isReadableFile(atPath: file.path) else {
                throw NSError(
                    domain: "Boreal.GraphicsAPI", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "\(option.api.displayName) requires the shader library \(requiredFile), which is missing or unreadable at \(file.path). Select DirectX 9 for this installation."]
                )
            }
        }
        return configured
    }

    static func applying(
        _ profile: GameGraphicsProfile?,
        backend: WineGraphicsBackend,
        to plan: WindowsLaunchPlan
    ) -> WindowsLaunchPlan {
        guard let preferredBackend = profile?.preferredBackend,
              preferredBackend == backend,
              let launchEnvironment = profile?.launchEnvironment,
              !launchEnvironment.isEmpty else { return plan }
        var configured = plan
        configured.environment.merge(launchEnvironment) { _, profileValue in profileValue }
        return configured
    }

    static func applying(
        wineD3DRenderer: WineD3DRenderer,
        backend: WineGraphicsBackend,
        to plan: WindowsLaunchPlan
    ) -> WindowsLaunchPlan {
        guard backend == .wineD3D,
              let renderer = wineD3DRenderer.launchEnvironmentValue else { return plan }
        var configured = plan
        configured.environment["WINE_D3D_CONFIG"] = renderer
        return configured
    }
}

/// Recognizes renderer initialization failures from the process log. The
/// signature deliberately requires both a Vulkan/translation hint and a
/// device/resource creation failure, so an ordinary game error does not
/// silently change the selected renderer.
nonisolated enum RendererLaunchFailureDetector {
    static func shouldUseWineD3DVulkanFallback(
        logURL: URL,
        profile: WineCompatibilityProfile,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.isReadableFile(atPath: logURL.path),
              let data = try? Data(contentsOf: logURL),
              let stderr = String(data: data, encoding: .utf8) else { return false }
        return shouldUseWineD3DVulkanFallback(stderr: stderr, profile: profile)
    }

    static func shouldUseWineD3DVulkanFallback(
        stderr: String,
        profile: WineCompatibilityProfile
    ) -> Bool {
        guard profile.graphicsFallback == .none,
              [.automatic, .dxvk].contains(profile.graphicsBackend) else { return false }
        let normalized = stderr.lowercased()
        let rendererHint = ["dxvk", "moltenvk", "vulkan", "direct3d", "d3d9", "d3d10", "d3d11", "d3d12"]
            .contains { normalized.contains($0) }
        let initializationFailure = [
            "failed to create device",
            "failed to create buffer",
            "failed to create the direct3d rendering device",
            "vk_error_feature_not_present",
            "dxvkadapter",
            "dxvkbuffer"
        ].contains { normalized.contains($0) }
        return rendererHint && initializationFailure
    }

    static func builtinDLLOverrides(for api: GraphicsAPI) -> [String] {
        switch api {
        case .directX9: ["d3d9"]
        case .directX10: ["d3d10", "d3d10_1", "d3d10core", "dxgi"]
        case .directX11: ["d3d11", "dxgi"]
        case .directX12: ["d3d12", "d3d12core", "dxgi"]
        case .automatic: ["d3d8", "d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "d3d12", "d3d12core", "dxgi"]
        }
    }
}

nonisolated struct GraphicsStackResolution: Codable, Hashable, Sendable {
    let stack: GraphicsStack
    let score: Int
    let reasons: [String]

    var isAvailable: Bool { score >= 0 }
}

nonisolated enum GraphicsStackCatalog {
    static let all: [GraphicsStack] = [
        GraphicsStack(
            backend: .d3dMetal,
            supportedAPIs: [.directX11, .directX12],
            supportedArchitectures: [.win64],
            hostAPI: .metal,
            requiredRuntimeFeatures: [.d3dMetal],
            requiredComponents: [],
            priority: 95
        ),
        GraphicsStack(
            backend: .dxmt,
            supportedAPIs: [.directX10, .directX11],
            // DXMT ships separate Win32 and Win64 entry points. The Unix
            // Metal side remains x64, while Wine's WoW64 loader dispatches
            // the x86 Windows DLL for a 32-bit game.
            supportedArchitectures: [.win32, .win64],
            hostAPI: .metal,
            requiredRuntimeFeatures: [.dxmt],
            requiredComponents: [.dxmt],
            priority: 90
        ),
        GraphicsStack(
            backend: .dxvk,
            supportedAPIs: [.directX9, .directX10, .directX11],
            supportedArchitectures: [.win32, .win64],
            hostAPI: .vulkan,
            requiredRuntimeFeatures: [.dxvk],
            requiredComponents: [.dxvk],
            priority: 88
        ),
        GraphicsStack(
            backend: .vkd3d,
            supportedAPIs: [.directX12],
            supportedArchitectures: [.win32, .win64],
            hostAPI: .vulkan,
            requiredRuntimeFeatures: [.vkd3d],
            requiredComponents: [.vkd3d],
            priority: 86
        ),
        GraphicsStack(
            backend: .wineD3D,
            supportedAPIs: [.directX9, .directX10, .directX11],
            supportedArchitectures: [.win32, .win64],
            hostAPI: .openGL,
            requiredRuntimeFeatures: [],
            requiredComponents: [],
            priority: 10
        )
    ]

    static func stack(for backend: GraphicsBackend) -> GraphicsStack? {
        all.first { $0.backend == backend }
    }
}

nonisolated enum GraphicsBackendResolver {
    static func resolve(
        api: GraphicsAPI,
        requestedBackend: GraphicsBackend,
        gameProfile: GameGraphicsProfile? = nil,
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture = .win64,
        fallback: WineGraphicsFallback = .none
    ) -> GraphicsStackResolution {
        let effectiveRequested = gameProfile?.enforcedBackend ?? requestedBackend
        let eligible = GraphicsStackCatalog.all.filter {
            $0.supports(api: api, architecture: architecture)
                && runtimeSupports($0, api: api, runtime: runtime, architecture: architecture)
        }

        let preferred = gameProfile?.preferredBackend
        let ranked = eligible.map { stack -> GraphicsStackResolution in
            var score = stack.priority + 20 + 10
            var reasons = [
                "Runtime capability matches (\(stack.backend.displayName))",
                "Architecture is supported"
            ]
            if stack.backend == preferred {
                score += 40
                reasons.append("Game profile preference")
            }
            if stack.hostAPI == .metal {
                score += 20
                reasons.append("Native Metal path")
            }
            if fallback == .wineD3DVulkan, stack.backend == .wineD3D {
                reasons.append("Renderer fallback uses WineD3D/Vulkan")
            }
            return GraphicsStackResolution(
                stack: stack.withHostAPI(fallback == .wineD3DVulkan && stack.backend == .wineD3D ? .vulkan : stack.hostAPI),
                score: score,
                reasons: reasons
            )
        }

        if effectiveRequested != .automatic,
           let explicit = GraphicsStackCatalog.stack(for: effectiveRequested) {
            if ranked.contains(where: { $0.stack.backend == explicit.backend }) {
                return GraphicsStackResolution(
                    stack: explicit.withHostAPI(fallback == .wineD3DVulkan && explicit.backend == .wineD3D ? .vulkan : explicit.hostAPI),
                    score: 1_000,
                    reasons: ["Explicit renderer selection"]
                )
            }
            if gameProfile?.enforcedBackend != nil || requestedBackend != .automatic {
                return GraphicsStackResolution(
                    stack: explicit,
                    score: -1_000,
                    reasons: [
                        gameProfile?.enforcedBackend != nil
                            ? "Enforced renderer is unavailable"
                            : "User-selected renderer is unavailable"
                    ]
                )
            }
            if let compatibleFallback = ranked.max(by: { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.stack.backend.rawValue > rhs.stack.backend.rawValue
            }) {
                return GraphicsStackResolution(
                    stack: compatibleFallback.stack,
                    score: compatibleFallback.score,
                    reasons: ["Selected renderer is unavailable for this runtime or architecture", "Using the best compatible fallback"] + compatibleFallback.reasons
                )
            }
        }

        return ranked.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.stack.backend.rawValue > rhs.stack.backend.rawValue
        } ?? GraphicsStackResolution(
            stack: GraphicsStackCatalog.stack(for: .wineD3D)!,
            score: -1_000,
            reasons: ["No compatible graphics stack was found"]
        )
    }

    static func supports(
        _ backend: GraphicsBackend,
        api: GraphicsAPI,
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture
    ) -> Bool {
        guard let stack = GraphicsStackCatalog.stack(for: backend),
              stack.supports(api: api, architecture: architecture) else { return false }
        return runtimeSupports(stack, api: api, runtime: runtime, architecture: architecture)
    }

    private static func runtimeSupports(
        _ stack: GraphicsStack,
        api: GraphicsAPI,
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture
    ) -> Bool {
        let featuresAvailable = stack.requiredRuntimeFeatures.allSatisfy { feature in
            switch feature {
            case .d3dMetal: runtime.features?.hasVerifiedD3DMetal == true
            case .dxmt: runtime.features?.dxmt == true && runtime.features?.d3d11Verified == true
            case .dxvk: runtime.features?.dxvk == true
            case .vkd3d: runtime.features?.vkd3d == true
            }
        }
        let componentsAvailable = stack.requiredComponents.allSatisfy { component in
            switch component {
            case .dxmt: runtime.features?.dxmt == true && runtime.features?.d3d11Verified == true
            case .dxvk: runtime.features?.dxvk == true
            case .vkd3d: runtime.features?.vkd3d == true
            }
        }
        guard featuresAvailable && componentsAvailable else { return false }
        // The upstream DXVK model covers D3D9, but the current macOS package
        // may intentionally omit d3d9.dll. Keep D3D9 available only when the
        // selected runtime really contains that library.
        if stack.backend == .dxvk, api == .directX9 {
            // Gunslinger is a 32-bit executable. A WoW64 runtime must expose
            // both sides of the component, while a legacy Win32 prefix only
            // needs x32. Checking the directory prevents a D3D9-capable
            // runtime with only an x64 DLL from being selected for this game.
            let requiredArchitectures = architecture == .win32 ? ["x32"] : ["x32", "x64"]
            return requiredArchitectures.allSatisfy { architectureDirectory in
                containsGraphicsLibrary(
                    ["D9VK", "DXVK"],
                    named: "d3d9.dll",
                    in: runtime,
                    requiredSubdirectory: architectureDirectory
                )
            }
        }
        if stack.backend == .dxvk, api == .directX10 {
            return containsGraphicsLibrary(["DXVK"], named: "d3d10core.dll", in: runtime)
        }
        if stack.backend == .dxvk, api == .directX11 {
            return containsGraphicsLibrary(["DXVK"], named: "d3d11.dll", in: runtime)
        }
        return true
    }

    private static func containsGraphicsLibrary(
        _ components: [String],
        named libraryName: String,
        in runtime: InstalledRuntime,
        requiredSubdirectory: String? = nil
    ) -> Bool {
        let fileManager = FileManager.default
        let legacyRoots = components.flatMap { component in
            [
                runtime.rootURL.appending(path: "GraphicsComponents/\(component)", directoryHint: .isDirectory),
                runtime.rootURL.appending(path: "Support/Graphics/\(component)", directoryHint: .isDirectory)
            ]
        }
        // Installed runtimes and the immutable component store share the
        // same Boreal support root. This keeps API-specific resolution (for
        // example DXVK D3D9) correct after components were detached from the
        // runtime package.
        let componentStoreRoot = runtime.rootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Components", directoryHint: .isDirectory)
        let componentStore = GraphicsComponentStore(rootURL: componentStoreRoot)
        let componentRoots = Set(components.compactMap { name -> URL? in
            let component: RuntimeComponent? = name.uppercased() == "VKD3D"
                ? .vkd3d
                : (name.uppercased() == "DXMT" ? .dxmt : (name.uppercased() == "DXVK" || name.uppercased() == "D9VK" ? .dxvk : nil))
            guard let component,
                  let reference = componentStore.reference(for: component) else { return nil }
            return componentStore.componentURL(component, version: reference.version)
        })
        let roots = legacyRoots + componentRoots
        return roots.contains { root in
            let searchRoot = requiredSubdirectory.map {
                root.appending(path: $0, directoryHint: .isDirectory)
            } ?? root
            guard let enumerator = fileManager.enumerator(
                at: searchRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return false }
            for case let url as URL in enumerator {
                guard url.lastPathComponent.caseInsensitiveCompare(libraryName) == .orderedSame,
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                return true
            }
            return false
        }
    }
}

nonisolated enum RendererPolicy {
    static func preferredBackend(for api: GraphicsAPI, runtime: InstalledRuntime) -> WineGraphicsBackend {
        GraphicsBackendResolver.resolve(
            api: api,
            requestedBackend: .automatic,
            runtime: runtime
        ).stack.backend
    }
}

nonisolated enum GraphicsAPIDetector {
    static func detect(
        executable: URL,
        fileManager: FileManager = .default
    ) -> GraphicsAPI? {
        let candidates = [executable]
        var detected = Set<GraphicsAPI>()
        for candidate in candidates {
            guard let handle = try? FileHandle(forReadingFrom: candidate) else { continue }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 8 * 1_024 * 1_024) else { continue }
            let text = String(decoding: data, as: UTF8.self).lowercased()
            if text.contains("d3d12.dll") { detected.insert(.directX12) }
            if text.contains("d3d11.dll") { detected.insert(.directX11) }
            if text.contains("d3d10.dll") || text.contains("d3d10core.dll") { detected.insert(.directX10) }
            if text.contains("d3d9.dll") { detected.insert(.directX9) }
        }
        return [.directX12, .directX11, .directX10, .directX9].first { detected.contains($0) }
    }
}
