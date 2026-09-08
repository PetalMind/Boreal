import Foundation

nonisolated enum GameGraphicsProfiles {
    static let builtIn: [GameGraphicsProfile] = [
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
            externalID: "388410",
            availableAPIs: [.directX11, .directX9],
            // The original Deathinitive release starts in D3D9. The optional
            // -dx11 path requires a separate shader library that may not be shipped.
            defaultAPI: .directX9,
            launchOptions: [
                GraphicsAPILaunchOption(api: .directX11, arguments: ["-dx11"], requiredFile: "Darksiders2.wsl"),
                GraphicsAPILaunchOption(api: .directX9, arguments: [])
            ],
            preferredBackend: .d9vk,
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
            preferredBackend: .d9vk,
            overlayCompatibleFullscreen: true
        )
    ]

    static func profile(for application: WindowsApplication) -> GameGraphicsProfile? {
        guard let provider = application.storeProvider,
              let externalID = application.storeExternalID else { return nil }
        return builtIn.first { $0.provider == provider && $0.externalID == externalID }
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
}

nonisolated enum RendererPolicy {
    static func preferredBackend(for api: GraphicsAPI, runtime: InstalledRuntime) -> WineGraphicsBackend {
        let features = runtime.features
        let candidates: [WineGraphicsBackend]
        switch api {
        case .directX9:
            candidates = [.d9vk, .wineD3D]
        case .directX10, .directX11:
            candidates = [.dxvk, .d3dMetal, .dxmt, .wineD3D]
        case .directX12:
            candidates = [.d3dMetal, .vkd3d, .wineD3D]
        case .automatic:
            candidates = [.dxvk, .d3dMetal, .dxmt, .wineD3D]
        }
        return candidates.first { backend in
            switch backend {
            case .dxvk: features?.dxvk == true
            case .d9vk: features?.d9vk == true
            case .vkd3d: features?.vkd3d == true
            case .d3dMetal: features?.d3dmetal == true
            case .dxmt: features?.dxmt == true
            case .wineD3D: true
            case .automatic: false
            }
        } ?? .wineD3D
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
