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
