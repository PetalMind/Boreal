import Foundation
import Testing
@testable import Boreal

@Suite("Runtime resolution")
struct RuntimeResolutionTests {
    @Test func gamePortingToolkitRuntimeUsesD3DMetalIdentity() {
        let root = URL(fileURLWithPath: "/private/tmp/boreal-gptk-runtime")
        let runtime = InstalledRuntime(
            id: "gptk-2",
            displayName: "Game Porting Toolkit 2",
            wineVersion: "7.7",
            rootURL: root,
            wineExecutable: root.appending(path: "wine64"),
            wineServerExecutable: root.appending(path: "wineserver"),
            wineBootExecutable: root.appending(path: "wineboot"),
            architecture: .x86_64,
            requirements: [.rosetta2],
            engine: .gamePortingToolkit,
            features: RuntimeFeatures(wow64: true, wineMono: false, wineGecko: false, d3dmetal: true, dxmt: false)
        )

        #expect(runtime.resolvedEngine == .gamePortingToolkit)
        #expect(runtime.graphicsName == "D3DMetal")
        #expect(runtime.runtimeDescription.contains("Game Porting Toolkit"))
    }

    @Test func legacyRuntimeDescriptorStillDecodesAsWine() throws {
        let json = """
        {"id":"legacy","displayName":"Wine","wineVersion":"9.0","rootURL":"file:///tmp/legacy","wineExecutable":"file:///tmp/legacy/wine","wineServerExecutable":"file:///tmp/legacy/wineserver","wineBootExecutable":"file:///tmp/legacy/wineboot","architecture":"x86_64","requirements":[]}
        """
        let runtime = try JSONDecoder().decode(InstalledRuntime.self, from: Data(json.utf8))
        #expect(runtime.resolvedEngine == .wine)
        #expect(runtime.graphicsName == "WineD3D")
    }

    @Test func importsDetectedLocalWineWhenNoRuntimeWasPreparedEarlier() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/boreal-runtime-resolution")
        let runtime = InstalledRuntime(
            id: "local-wine",
            displayName: "Wine Staging",
            wineVersion: "11.15",
            rootURL: root,
            wineExecutable: root.appending(path: "wine"),
            wineServerExecutable: root.appending(path: "wineserver"),
            wineBootExecutable: root.appending(path: "wineboot"),
            architecture: .x86_64,
            requirements: [.rosetta2],
            origin: .localImport
        )
        let candidate = LocalRuntimeCandidate(
            id: runtime.id,
            displayName: runtime.displayName,
            wineVersion: runtime.wineVersion,
            appURL: URL(fileURLWithPath: "/Applications/Wine Staging.app"),
            architecture: runtime.architecture,
            requirements: runtime.requirements,
            minimumMacOS: "10.15",
            estimatedSize: nil
        )
        let manager = RuntimeResolutionManager(candidate: candidate, runtime: runtime)

        let selected = try await manager.prepareReadyRuntime()

        #expect(selected == runtime)
        #expect(await manager.importCount == 1)
        #expect(await manager.catalogInstallCount == 0)
    }

    @Test func preferredRuntimeEngineSelectsGPTKInsteadOfInstalledWine() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/boreal-preferred-runtime")
        let wine = InstalledRuntime(
            id: "wine",
            displayName: "Wine",
            wineVersion: "11.15",
            rootURL: root.appending(path: "wine"),
            wineExecutable: root.appending(path: "wine/wine"),
            wineServerExecutable: root.appending(path: "wine/wineserver"),
            wineBootExecutable: root.appending(path: "wine/wineboot"),
            architecture: .x86_64,
            requirements: [],
            engine: .wine
        )
        let gptk = InstalledRuntime(
            id: "gptk",
            displayName: "Game Porting Toolkit",
            wineVersion: "3.0-2",
            rootURL: root.appending(path: "gptk"),
            wineExecutable: root.appending(path: "gptk/wine64"),
            wineServerExecutable: root.appending(path: "gptk/wineserver"),
            wineBootExecutable: root.appending(path: "gptk/wineboot"),
            architecture: .x86_64,
            requirements: [],
            engine: .gamePortingToolkit,
            features: RuntimeFeatures(wow64: true, wineMono: false, wineGecko: false, d3dmetal: true, dxmt: false)
        )
        let manager = PreferredRuntimeManager(installed: [wine, gptk])

        let selected = try await manager.prepareReadyRuntime(preferredEngine: .gamePortingToolkit)

        #expect(selected.id == gptk.id)
    }
}

private actor PreferredRuntimeManager: RuntimeManaging {
    let installed: [InstalledRuntime]

    init(installed: [InstalledRuntime]) { self.installed = installed }

    func availableRuntimes() async throws -> [BorealRuntime] { [] }
    func installedRuntimes() async throws -> [InstalledRuntime] { installed }
    func localRuntimeCandidates() async -> [LocalRuntimeCandidate] { [] }
    func importLocalRuntime(_ candidate: LocalRuntimeCandidate) async throws -> InstalledRuntime { throw CocoaError(.featureUnsupported) }
    func install(_ runtime: BorealRuntime) async throws -> InstalledRuntime { throw CocoaError(.featureUnsupported) }
    func validate(_ runtime: InstalledRuntime) async throws -> RuntimeValidation {
        RuntimeValidation(
            detectedWineVersion: runtime.wineVersion,
            versionMatchesManifest: true,
            missingPaths: [],
            unmetRequirements: [],
            executablePaths: [runtime.wineExecutable.path]
        )
    }
    func remove(_ runtime: InstalledRuntime) async throws { }
}

private actor RuntimeResolutionManager: RuntimeManaging {
    let candidate: LocalRuntimeCandidate
    let runtime: InstalledRuntime
    private(set) var importCount = 0
    private(set) var catalogInstallCount = 0

    init(candidate: LocalRuntimeCandidate, runtime: InstalledRuntime) {
        self.candidate = candidate
        self.runtime = runtime
    }

    func availableRuntimes() async throws -> [BorealRuntime] { [] }
    func installedRuntimes() async throws -> [InstalledRuntime] { [] }
    func localRuntimeCandidates() async -> [LocalRuntimeCandidate] { [candidate] }

    func importLocalRuntime(_ candidate: LocalRuntimeCandidate) async throws -> InstalledRuntime {
        importCount += 1
        return runtime
    }

    func install(_ runtime: BorealRuntime) async throws -> InstalledRuntime {
        catalogInstallCount += 1
        return self.runtime
    }

    func validate(_ runtime: InstalledRuntime) async throws -> RuntimeValidation {
        RuntimeValidation(
            detectedWineVersion: runtime.wineVersion,
            versionMatchesManifest: true,
            missingPaths: [],
            unmetRequirements: [],
            executablePaths: [runtime.wineExecutable.path]
        )
    }

    func remove(_ runtime: InstalledRuntime) async throws { }
}
