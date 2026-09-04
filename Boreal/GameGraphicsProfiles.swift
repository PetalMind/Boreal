import Foundation

nonisolated enum GameGraphicsProfiles {
    static let builtIn: [GameGraphicsProfile] = [
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
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [],
            preferredBackend: .wineD3D
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
    ) -> WindowsLaunchPlan {
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
        return configured
    }
}

nonisolated enum RendererPolicy {
    static func preferredBackend(for api: GraphicsAPI, runtime: InstalledRuntime) -> WineGraphicsBackend {
        let features = runtime.features
        let candidates: [WineGraphicsBackend]
        switch api {
        case .directX9:
            // The maintained macOS DXVK package supports D3D10/11. Do not
            // advertise historical D9VK behavior that the package omits.
            candidates = [.wineD3D]
        case .directX10, .directX11:
            candidates = [.dxvk, .d3dMetal, .dxmt, .wineD3D]
        case .directX12:
            candidates = [.d3dMetal, .wineD3D]
        case .automatic:
            candidates = [.dxvk, .d3dMetal, .dxmt, .wineD3D]
        }
        return candidates.first { backend in
            switch backend {
            case .dxvk: features?.dxvk == true
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
