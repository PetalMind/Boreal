import Foundation

nonisolated struct GraphicsLayerPlan: Sendable, Hashable {
    let legacyWrapper: LegacyGraphicsWrapper
    let backend: WineGraphicsBackend
    let dllOverrides: [DLLOverride]
    let files: [GraphicsInjectedFile]
}

/// Coordinates per-game legacy input wrappers with the existing prefix-level
/// renderer manager. The two remain separate layers and ownership domains.
nonisolated struct GraphicsCompatibilityManager: Sendable {
    private let backendManager: GraphicsBackendManager
    private let wrapperManager: LegacyWrapperManager

    init(
        backendManager: GraphicsBackendManager = GraphicsBackendManager(),
        wrapperManager: LegacyWrapperManager = LegacyWrapperManager()
    ) {
        self.backendManager = backendManager
        self.wrapperManager = wrapperManager
    }

    func apply(
        configuration: WineCompatibilityProfile,
        application: WindowsApplication,
        executable: URL,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) throws -> GraphicsLayerPlan {
        let wrapper = try wrapperManager.activate(
            configuration.legacyWrapper,
            api: configuration.legacyGraphicsAPI,
            gameExecutable: executable,
            environment: environment,
            runtime: runtime
        )
        return GraphicsLayerPlan(
            legacyWrapper: wrapper.wrapper,
            backend: backendManager.resolve(configuration.graphicsBackend, runtime: runtime),
            dllOverrides: wrapper.dllOverrides,
            files: wrapper.files
        )
    }

    func reset(application _: WindowsApplication, executable: URL) throws {
        try wrapperManager.reset(gameExecutable: executable)
    }

    func applying(_ graphics: GraphicsLayerPlan, to launchPlan: WindowsLaunchPlan) -> WindowsLaunchPlan {
        guard !graphics.dllOverrides.isEmpty else { return launchPlan }
        var plan = launchPlan
        let overrides = graphics.dllOverrides
            .map { "\($0.library)=\($0.mode.wineValue)" }
            .joined(separator: ";")
        if let existing = plan.environment["WINEDLLOVERRIDES"], !existing.isEmpty {
            plan.environment["WINEDLLOVERRIDES"] = existing + ";" + overrides
        } else {
            plan.environment["WINEDLLOVERRIDES"] = overrides
        }
        return plan
    }
}
