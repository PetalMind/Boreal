import Foundation
import Testing
@testable import Boreal

struct CompatibilityPreparationTests {
    @Test func analysisKeepsX86LauncherAndX64GameAsSeparateConstraints() throws {
        let root = try makeTemporaryDirectory("analysis")
        defer { try? FileManager.default.removeItem(at: root) }
        try makePE(at: root.appending(path: "Game.exe"), architecture: .x86_64, imports: ["d3d11.dll"])
        try makePE(at: root.appending(path: "Launcher.exe"), architecture: .x86)
        try makePE(at: root.appending(path: "Updater.exe"), architecture: .x86)

        let analysis = ExecutableCompatibilityAnalyzer.analyze(root: root, applicationName: "Game")

        #expect(analysis.gameExecutable?.url.lastPathComponent == "Game.exe")
        #expect(analysis.gameExecutable?.architecture == .x86_64)
        #expect(analysis.launcherArchitectures == [.x86])
        #expect(analysis.requiredArchitectures.contains(.x86_64))
        #expect(analysis.requiredArchitectures.contains(.x86))
        #expect(analysis.executables.first(where: { $0.url.lastPathComponent == "Updater.exe" })?.role == .updater)
    }

    @Test func automaticallyDetectsPhysXBehindASeparateLauncher() throws {
        let root = try makeTemporaryDirectory("physx-launcher")
        defer { try? FileManager.default.removeItem(at: root) }
        try makePE(at: root.appending(path: "GameLauncher.exe"), architecture: .x86)
        let binaries = root.appending(path: "bin_ship", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
        try makePE(
            at: binaries.appending(path: "Game.exe"),
            architecture: .x86,
            imports: ["PhysXLoader.dll"]
        )

        let analysis = ExecutableCompatibilityAnalyzer.analyze(
            root: root,
            applicationName: "Game",
            knownPrimary: root.appending(path: "GameLauncher.exe")
        )
        let dependencies = AutomaticRuntimeDependencyDetection.requiredDependencies(in: analysis)

        #expect(dependencies.contains(.physX))
    }

    @Test func runtimeConstraintsAllowMixedArchitecturesOnlyWithWoW64() {
        let runtime = makeRuntime(
            features: RuntimeFeatures(
                wow64: true,
                supportsWin32Execution: true,
                supportsWin64Execution: true,
                wineMono: false,
                wineGecko: false,
                d3dmetal: false,
                dxmt: false
            )
        )
        let request = RuntimeSelectionRequest(architectures: [.x86, .x86_64])

        #expect(CompatibilityPreparationResolver.runtimeSatisfies(runtime, request: request))
    }

    @Test func preferredBackendCanFallbackButEnforcedBackendCannot() throws {
        let root = try makeTemporaryDirectory("graphics")
        defer { try? FileManager.default.removeItem(at: root) }
        try makePE(at: root.appending(path: "Game.exe"), architecture: .x86_64, imports: ["d3d11.dll"])
        let dxvk = root.appending(path: "GraphicsComponents/DXVK/x64", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dxvk, withIntermediateDirectories: true)
        try Data("dxvk".utf8).write(to: dxvk.appending(path: "d3d11.dll"))
        let runtime = makeRuntime(
            root: root,
            features: RuntimeFeatures(
                wow64: true,
                supportsWin32Execution: true,
                supportsWin64Execution: true,
                wineMono: false,
                wineGecko: false,
                d3dmetal: false,
                dxmt: false,
                dxvk: true
            )
        )
        let analysis = ExecutableCompatibilityAnalyzer.analyze(root: root, applicationName: "Game")
        let preferred = GameGraphicsProfile(
            provider: .gog,
            externalID: "preferred",
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [],
            preferredBackend: .dxmt
        )
        let fallback = try CompatibilityPreparationResolver.resolve(
            analysis: analysis,
            userProfile: .default,
            gameProfile: preferred,
            runtime: runtime
        )
        #expect(fallback.graphicsStack.backend == .dxvk)

        let enforced = GameGraphicsProfile(
            provider: .gog,
            externalID: "enforced",
            availableAPIs: [.directX11],
            defaultAPI: .directX11,
            launchOptions: [],
            enforcedBackend: .dxmt
        )
        #expect(throws: CompatibilityPreparationError.self) {
            try CompatibilityPreparationResolver.resolve(
                analysis: analysis,
                userProfile: .default,
                gameProfile: enforced,
                runtime: runtime
            )
        }
    }

    @Test func dx9DXVKWithoutD3D9DLLIsRejectedInFavorOfWineD3D() throws {
        let root = try makeTemporaryDirectory("dx9")
        defer { try? FileManager.default.removeItem(at: root) }
        try makePE(at: root.appending(path: "Game.exe"), architecture: .x86, imports: ["d3d9.dll"])
        let dxvk = root.appending(path: "GraphicsComponents/DXVK/x32", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dxvk, withIntermediateDirectories: true)
        try Data("dxvk-d3d11".utf8).write(to: dxvk.appending(path: "d3d11.dll"))
        let runtime = makeRuntime(
            root: root,
            features: RuntimeFeatures(
                wow64: true,
                supportsWin32Execution: true,
                supportsWin64Execution: true,
                wineMono: false,
                wineGecko: false,
                d3dmetal: false,
                dxmt: false,
                dxvk: true
            )
        )
        let analysis = ExecutableCompatibilityAnalyzer.analyze(root: root, applicationName: "Game")
        let resolved = try CompatibilityPreparationResolver.resolve(
            analysis: analysis,
            userProfile: .default,
            gameProfile: nil,
            runtime: runtime
        )

        #expect(resolved.directXAPI == .directX9)
        #expect(resolved.graphicsStack.backend == .wineD3D)
    }

    @Test func wow64PrefixDoesNotMakeD3DMetalAvailableForAnX86Game() throws {
        let root = try makeTemporaryDirectory("x86-metal")
        defer { try? FileManager.default.removeItem(at: root) }
        try makePE(at: root.appending(path: "Game.exe"), architecture: .x86, imports: ["d3d11.dll"])
        let runtime = makeRuntime(root: root, features: RuntimeFeatures(
            wow64: true, wineMono: false, wineGecko: false,
            d3dmetal: true, d3dmetalVerified: true, dxmt: false
        ))
        let analysis = ExecutableCompatibilityAnalyzer.analyze(root: root, applicationName: "Game")
        let resolved = try CompatibilityPreparationResolver.resolve(
            analysis: analysis, userProfile: .default, gameProfile: nil, runtime: runtime
        )
        #expect(resolved.prefixMode == .wow64)
        #expect(resolved.graphicsStack.backend == .wineD3D)
        var manual = WineCompatibilityProfile.default
        manual.graphicsBackend = .d3dMetal
        #expect(throws: CompatibilityPreparationError.self) {
            try CompatibilityPreparationResolver.resolve(analysis: analysis, userProfile: manual, gameProfile: nil, runtime: runtime)
        }
    }

    @Test(arguments: [
        (LegacyGraphicsWrapper.dd7to9, GraphicsAPI.directX9, GraphicsBackend.dxvk),
        (.dgVoodoo2, .directX11, .dxmt), (.borealLegacyGraphics, .directX11, .dxmt)
    ])
    func legacyWrapperRoutesToItsOutputAPI(wrapper: LegacyGraphicsWrapper, outputAPI: GraphicsAPI, backend: GraphicsBackend) throws {
        let root = try makeTemporaryDirectory("legacy-output")
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "Game.exe")
        try makePE(at: executable, architecture: .x86, imports: ["ddraw.dll"])
        for architecture in ["x32", "x64"] {
            let folder = root.appending(path: "GraphicsComponents/DXVK/\(architecture)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("dxvk".utf8).write(to: folder.appending(path: "d3d9.dll"))
        }
        let runtime = makeRuntime(root: root, features: RuntimeFeatures(
            wow64: true, wineMono: false, wineGecko: false,
            d3dmetal: false, dxmt: true, d3d11Verified: true, dxvk: true
        ))
        var userProfile = WineCompatibilityProfile.default
        userProfile.legacyWrapper = wrapper
        userProfile.graphicsAPI = .directDraw
        let analysis = ExecutableCompatibilityAnalyzer.analyze(root: root, applicationName: "Game")
        let resolved = try CompatibilityPreparationResolver.resolve(
            analysis: analysis, userProfile: userProfile, gameProfile: nil, runtime: runtime
        )
        #expect(resolved.directXAPI == outputAPI)
        #expect(resolved.environmentSpecification.graphicsAPI == outputAPI)
        #expect(resolved.graphicsStack.backend == backend)

        userProfile.graphicsAPI = .directX10
        #expect(CompatibilityPreparationResolver.directXAPI(executable: executable, userProfile: userProfile, gameProfile: nil) == .directX10)
    }

    private func makeTemporaryDirectory(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makePE(
        at url: URL,
        architecture: WindowsExecutableArchitecture,
        imports: [String] = []
    ) throws {
        var data = Data(repeating: 0, count: 320)
        data[0] = 0x4D
        data[1] = 0x5A
        data[60] = 64
        data[64] = 0x50
        data[65] = 0x45
        data[66] = 0
        data[67] = 0
        data[88] = 0x0B
        data[89] = architecture == .x86 ? 0x01 : 0x02
        data[156] = 0x02
        var offset = 170
        for value in imports {
            for byte in value.utf8 where offset < data.count { data[offset] = byte; offset += 1 }
            if offset < data.count { data[offset] = 0; offset += 1 }
        }
        try data.write(to: url, options: .atomic)
    }

    private func makeRuntime(
        root: URL = FileManager.default.temporaryDirectory,
        features: RuntimeFeatures
    ) -> InstalledRuntime {
        InstalledRuntime(
            id: "test-runtime",
            displayName: "Test Runtime",
            wineVersion: "11",
            rootURL: root,
            wineExecutable: root.appending(path: "wine"),
            wineServerExecutable: root.appending(path: "wineserver"),
            wineBootExecutable: root.appending(path: "wineboot"),
            architecture: .x86_64,
            requirements: [],
            origin: .localImport,
            engine: .wine,
            features: features
        )
    }
}
