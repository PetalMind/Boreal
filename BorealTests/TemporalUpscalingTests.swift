import Foundation
import Testing
@testable import Boreal

struct TemporalUpscalingTests {
    @Test func analyzerDoesNotTrustDLLNameOrSimilarFilename() throws {
        let root = try temporaryDirectory("temporal-analyzer")
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("not a PE image".utf8).write(to: root.appending(path: "nvngx_dlss.dll"))
        try makePE(architecture: .x86_64).write(to: root.appending(path: "nvngx_dlss.dll.backup"))
        let analysis = GameUpscalerAnalysisEngine.analyze(
            gameRoot: root,
            executable: root.appending(path: "nvngx_dlss.dll.backup")
        )

        #expect(analysis.dlss?.detected == false)
        #expect(analysis.dlss?.version == nil)
        #expect(analysis.dlss?.evidence.contains { !$0.accepted && $0.source == .peArchitecture } == true)
        #expect(analysis.dlss?.fileURLs.isEmpty == true)
    }

    @Test func resolverKeepsTemporalBridgeSeparateAndUnverified() {
        let root = URL(fileURLWithPath: "/Games/Temporal")
        let capability = TemporalUpscalerCapability(
            kind: .dlss,
            detected: true,
            version: nil,
            confidence: .medium,
            sources: [.fileName],
            evidence: [],
            fileURLs: [root.appending(path: "nvngx_dlss.dll")]
        )
        let game = GameUpscalingCapabilities(
            gameRoot: root,
            analyzedAt: Date(),
            dlss: capability,
            fsr: nil,
            xess: nil,
            frameGeneration: FrameGenerationCapability(support: .unavailable, evidence: []),
            antiCheat: .unknown
        )
        let runtime = makeRuntime(root: URL(fileURLWithPath: "/Runtimes/gptk"), engine: .gamePortingToolkit)
        let config = TemporalUpscalingConfiguration(
            mode: .metalFXBridge,
            quality: .quality,
            outputUpscaler: .native,
            frameGeneration: FrameGenerationConfiguration(),
            dlsstweaks: DLSSTweaksConfiguration(),
            optiScaler: OptiScalerConfiguration()
        )
        let plan = TemporalUpscalingResolutionEngine.resolve(
            game: game,
            runtime: runtime,
            graphicsStack: GraphicsStackCatalog.stack(for: .d3dMetal)!,
            configuration: config,
            metalFX: MetalFXBridgeCapabilities(
                available: true,
                installed: true,
                source: .runtimePayload,
                supportsSpatial: true,
                supportsTemporal: true,
                requiredEnvironmentVariables: ["D3DM_ENABLE_METALFX"],
                requiredDLLs: ["nvngx-on-metalfx.dll", "nvapi64.dll"],
                evidence: []
            )
        )

        #expect(plan.requested.mode == .metalFXBridge)
        #expect(plan.effective == .metalFXBridge)
        #expect(plan.compatibility.label == "Experimental")
        #expect(plan.isActive)
        #expect(plan.fingerprintSegment.contains("dlsstweaks.enabled=false"))
        #expect(plan.fingerprintSegment.contains("optiscaler.enabled=false"))
    }

    @Test func spatialResolverNeverUsesTemporalGameInterfaces() {
        let features = RuntimeFeatures(
            wow64: true,
            supportsWin32Execution: true,
            supportsWin64Execution: true,
            wineMono: false,
            wineGecko: false,
            d3dmetal: true,
            dxmt: false,
            fullscreenFSR: true,
            fullscreenFSRCapabilities: FullscreenFSRCapabilities(
                available: true,
                confidence: .detected,
                source: .payloadInspection
            )
        )

        #expect(SpatialUpscalingResolver.resolve(runtimeFeatures: features, backend: .d3dMetal).status == .unavailable)
        #expect(SpatialUpscalingResolver.resolve(runtimeFeatures: features, backend: .dxvk).status == .candidate)
    }

    @Test func optiScalerInjectionRequiresManifestAndRestoresOriginalFile() async throws {
        let root = try temporaryDirectory("temporal-opti")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "opti-source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try makePE(architecture: .x86_64).write(to: source.appending(path: "optiscaler.dll"))
        try Data(#"{"files":["optiscaler.dll"],"proxyStrategy":{"mode":"automatic"}}"#.utf8)
            .write(to: source.appending(path: "injection.json"))

        let store = ManagedTemporalComponentStore(rootURL: root.appending(path: "Components", directoryHint: .isDirectory))
        let reference = try store.install(
            id: .optiScaler,
            version: "test-1",
            source: source,
            sourceKind: .userImport
        )
        #expect(store.contains(reference))
        let game = root.appending(path: "game", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data("original game proxy".utf8).write(to: game.appending(path: "optiscaler.dll"))
        let applicationID = UUID()
        let manager = OptiScalerManager(store: store)
        var injectionConfiguration = OptiScalerConfiguration()
        injectionConfiguration.enabled = true

        do {
            _ = try await manager.inject(
                reference: reference,
                configuration: injectionConfiguration,
                gameRoot: game,
                applicationID: applicationID,
                targetArchitecture: .x86_64
            )
            Issue.record("Injection without explicit confirmation unexpectedly succeeded.")
        } catch let error as TemporalInjectionError {
            if case .confirmationRequired = error {
                // Expected safety boundary.
            } else {
                Issue.record("Unexpected injection error: \(error.localizedDescription)")
            }
        }

        let receipt = try await manager.inject(
            reference: reference,
            configuration: injectionConfiguration,
            gameRoot: game,
            applicationID: applicationID,
            targetArchitecture: .x86_64,
            confirmUnknownInjectionPolicy: true
        )
        #expect(receipt.bridgeID == "optiscaler")
        #expect(receipt.replacedFiles.map(\.relativePath) == ["optiscaler.dll"])
        #expect(try Data(contentsOf: game.appending(path: "optiscaler.dll")) != Data("original game proxy".utf8))

        try await manager.restore(receipt, gameRoot: game)
        #expect(try Data(contentsOf: game.appending(path: "optiscaler.dll")) == Data("original game proxy".utf8))
    }

    @Test func managedDLSSRuntimeReplacementBacksUpAndRestoresExactOriginal() async throws {
        let root = try temporaryDirectory("temporal-dlss-runtime")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "dlss-source", directoryHint: .isDirectory)
        let game = root.appending(path: "game", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        var managed = makePE(architecture: .x86_64)
        managed[200] = 0x01
        try managed.write(to: source.appending(path: "nvngx_dlss.dll"))
        var original = makePE(architecture: .x86_64)
        original[200] = 0x02
        try original.write(to: game.appending(path: "nvngx_dlss.dll"))

        let store = ManagedTemporalComponentStore(rootURL: root.appending(path: "Components", directoryHint: .isDirectory))
        let reference = try store.install(
            id: .dlssRuntime,
            version: "test-dlss-1",
            source: source,
            sourceKind: .userImport
        )
        let manager = DLSSRuntimeManager(store: store)
        let applicationID = UUID()

        let backup = try await manager.backupOriginal(in: game, applicationID: applicationID)
        #expect(backup.source == .gameOriginal)
        let managed = try await manager.installManagedVersion(reference, in: game, applicationID: applicationID)
        #expect(managed.source == .borealManaged)
        #expect(try await manager.validate(in: game))
        #expect(try Data(contentsOf: game.appending(path: "nvngx_dlss.dll")) == managed)

        let restored = try await manager.removeManagedOverride(in: game)
        #expect(restored.source == .gameOriginal)
        #expect(try Data(contentsOf: game.appending(path: "nvngx_dlss.dll")) == original)
    }

    private func temporaryDirectory(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "boreal-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makePE(architecture: WindowsExecutableArchitecture) -> Data {
        var data = Data(repeating: 0, count: 512)
        data[0] = 0x4D
        data[1] = 0x5A
        data[0x3C] = 0x80
        data[0x80] = 0x50
        data[0x81] = 0x45
        data[0x82] = 0
        data[0x83] = 0
        data[0x84] = architecture == .x86 ? 0x4C : 0x64
        data[0x85] = architecture == .x86 ? 0x01 : 0x86
        data[0x86] = 0
        data[0x87] = 0
        data[0x94] = 0xF0
        data[0x98] = architecture == .x86 ? 0x0B : 0x0B
        data[0x99] = architecture == .x86 ? 0x01 : 0x02
        return data
    }

    private func makeRuntime(root: URL, engine: RuntimeEngine) -> InstalledRuntime {
        InstalledRuntime(
            id: "test-runtime",
            displayName: "Test Runtime",
            wineVersion: "test",
            rootURL: root,
            wineExecutable: root.appending(path: "wine"),
            wineServerExecutable: root.appending(path: "wineserver"),
            wineBootExecutable: root.appending(path: "wineboot"),
            architecture: .x86_64,
            requirements: [],
            engine: engine,
            features: RuntimeFeatures(
                wow64: true,
                supportsWin32Execution: true,
                supportsWin64Execution: true,
                wineMono: false,
                wineGecko: false,
                d3dmetal: engine == .gamePortingToolkit,
                dxmt: false
            )
        )
    }
}
