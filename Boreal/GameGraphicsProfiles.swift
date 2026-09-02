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
