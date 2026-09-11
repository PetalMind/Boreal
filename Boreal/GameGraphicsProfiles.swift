import Foundation

nonisolated enum GameRuntimeProfiles {
    static func requiredEngine(provider: GameLibraryProvider, externalID: String) -> RuntimeEngine? {
        switch (provider, externalID) {
        case (.gog, "1887281589"), (.steam, "1466060"):
            // Unity 6 needs D3D11 feature level 11, which WineD3D cannot
            // expose on Apple Silicon. Boreal supplies the missing WinRT API
            // alias in the prefix so GPTK can load IL2CPP and use D3DMetal.
            return .gamePortingToolkit
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
            overlayCompatibleFullscreen: true
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
            launchEnvironment: ["WINED3D_RENDERER": "gl"]
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

    static func effectiveCompatibilityProfile(
        _ currentProfile: WineCompatibilityProfile,
        for application: WindowsApplication
    ) -> WineCompatibilityProfile {
        guard let builtIn = profile(for: application),
              builtIn.enforcedBackend != nil || builtIn.enforcedAPI != nil else { return currentProfile }
        var effective = currentProfile
        effective.graphicsAPI = builtIn.defaultAPI
        if let enforcedAPI = builtIn.enforcedAPI {
            effective.graphicsAPI = enforcedAPI
        }
        if let enforcedBackend = builtIn.enforcedBackend {
            effective.graphicsBackend = enforcedBackend
        }
        return effective
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
            supportedArchitectures: [.win64],
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
                && runtimeSupports($0, api: api, runtime: runtime)
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
        return runtimeSupports(stack, api: api, runtime: runtime)
    }

    private static func runtimeSupports(
        _ stack: GraphicsStack,
        api: GraphicsAPI,
        runtime: InstalledRuntime
    ) -> Bool {
        let featuresAvailable = stack.requiredRuntimeFeatures.allSatisfy { feature in
            switch feature {
            case .d3dMetal: runtime.features?.d3dmetal == true
            case .dxmt: runtime.features?.dxmt == true
            case .dxvk: runtime.features?.dxvk == true
            case .vkd3d: runtime.features?.vkd3d == true
            }
        }
        let componentsAvailable = stack.requiredComponents.allSatisfy { component in
            switch component {
            case .dxmt: runtime.features?.dxmt == true
            case .dxvk: runtime.features?.dxvk == true
            case .vkd3d: runtime.features?.vkd3d == true
            }
        }
        guard featuresAvailable && componentsAvailable else { return false }
        // The upstream DXVK model covers D3D9, but the current macOS package
        // may intentionally omit d3d9.dll. Keep D3D9 available only when the
        // selected runtime really contains that library.
        if stack.backend == .dxvk, api == .directX9 {
            return containsGraphicsLibrary(["DXVK", "D9VK"], named: "d3d9.dll", in: runtime)
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
        in runtime: InstalledRuntime
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
            guard let enumerator = fileManager.enumerator(
                at: root,
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
