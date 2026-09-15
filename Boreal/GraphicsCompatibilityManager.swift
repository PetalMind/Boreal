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
        let wrapperSettings = GameGraphicsProfiles.profile(for: application)?.legacyWrapperSettings ?? [:]
        let wrapper = try wrapperManager.activate(
            configuration.legacyWrapper,
            api: configuration.legacyGraphicsAPI,
            gameExecutable: executable,
            environment: environment,
            runtime: runtime,
            settings: wrapperSettings
        )
        return GraphicsLayerPlan(
            legacyWrapper: wrapper.wrapper,
            backend: backendManager.resolve(
                configuration.graphicsBackend,
                graphicsAPI: configuration.graphicsAPI ?? .automatic,
                runtime: runtime,
                architecture: environment.configuration.resolvedPrefixArchitecture(
                    runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true
                )
            ),
            dllOverrides: wrapper.dllOverrides,
            files: wrapper.files
        )
    }

    func reset(application _: WindowsApplication, executable: URL) throws {
        try wrapperManager.reset(gameExecutable: executable)
    }

    func applying(_ graphics: GraphicsLayerPlan, to launchPlan: WindowsLaunchPlan) -> WindowsLaunchPlan {
        var plan = launchPlan

        if graphics.legacyWrapper == .borealLegacyGraphics,
           graphics.backend == .dxmt {
            // Sacred's BLG bridge submits many small D3D11 scenes. Keep the
            // compatibility path on DXMT's native Metal presentation path;
            // the host shim owns display-layer pacing for this legacy window.
            // Keep all BLG diagnostics opt-in from leaking into the normal
            // profile. The validated Sacred path bakes the cached surface
            // texels into diffuse vertices and avoids both the SRV/present
            // stall and the intentionally slow software rasterizer.
            plan.environment["BLG_TEXTURE_SAMPLING"] = "0"
            plan.environment["BLG_SOFTWARE_RENDERING"] = "0"
            plan.environment["BLG_FRAME_LATENCY"] = "16"
            plan.environment["BLG_PRESENT_INTERVAL_MS"] = "0"
            plan.environment["BLG_SWAPCHAIN_MODE"] = "discard"
            plan.environment["BLG_GEOMETRY_CULLING"] = "0"
        }

        guard !graphics.dllOverrides.isEmpty else { return plan }
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
