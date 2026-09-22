import Foundation
import Testing
@testable import Boreal

struct WineCompatibilityProfileTests {
    @Test func prefixRuntimeLeasesBlockMutationsUntilEverySessionReleases() async throws {
        let coordinator = PrefixUsageCoordinator()
        let prefix = FileManager.default.temporaryDirectory
            .appending(path: "boreal-prefix-lease-\(UUID().uuidString)", directoryHint: .isDirectory)
        let firstSession = UUID()
        let secondSession = UUID()
        try await coordinator.acquireRuntimeLease(for: prefix, sessionID: firstSession)
        try await coordinator.acquireRuntimeLease(for: prefix, sessionID: secondSession)

        await #expect(throws: EnvironmentManagerError.self) {
            try await coordinator.withLock(for: prefix) { true }
        }

        await coordinator.releaseRuntimeLease(for: prefix, sessionID: firstSession)
        #expect(await coordinator.hasRuntimeLease(for: prefix))
        await #expect(throws: EnvironmentManagerError.self) {
            try await coordinator.withLock(for: prefix) { true }
        }

        await coordinator.releaseRuntimeLease(for: prefix, sessionID: secondSession)
        #expect(await !coordinator.hasRuntimeLease(for: prefix))
        #expect(try await coordinator.withLock(for: prefix) { true })
    }

    @Test func graphicsBackendDLLOverridesCoverTheSupportedDirectXMatrix() {
        let cases: [(GraphicsBackend, GraphicsAPI, Set<String>)] = [
            (.dxvk, .directX9, ["d3d9", "dxgi"]),
            (.dxvk, .directX10, ["d3d10", "d3d10_1", "d3d10core", "dxgi"]),
            (.dxvk, .directX11, ["d3d11", "dxgi"]),
            (.dxmt, .directX10, ["d3d10", "d3d10_1", "d3d10core", "d3d11", "dxgi"]),
            (.dxmt, .directX11, ["d3d11", "dxgi"]),
            (.vkd3d, .directX12, ["d3d12", "d3d12core", "dxgi"]),
            (.wineD3D, .directX9, []),
            (.d3dMetal, .directX11, []),
            (.d3dMetal, .directX12, [])
        ]

        for (backend, api, expected) in cases {
            #expect(
                GraphicsBackendManager.apiSpecificDLLOverrides(for: backend, api: api) == expected,
                "Unexpected DLL override matrix entry for \(backend.rawValue)/\(api.rawValue)."
            )
        }

        #expect(RendererLaunchFailureDetector.builtinDLLOverrides(for: .directX9) == ["d3d9"])
        #expect(RendererLaunchFailureDetector.builtinDLLOverrides(for: .directX10) == ["d3d10", "d3d10_1", "d3d10core", "dxgi"])
        #expect(RendererLaunchFailureDetector.builtinDLLOverrides(for: .directX11) == ["d3d11", "dxgi"])
        #expect(RendererLaunchFailureDetector.builtinDLLOverrides(for: .directX12) == ["d3d12", "d3d12core", "dxgi"])
    }

    @Test func automaticRendererPolicyUsesDXVKWhenNativeMetalPathsAreUnavailable() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-resolver-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dxvkRoot = root.appending(path: "GraphicsComponents/DXVK/x64", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dxvkRoot, withIntermediateDirectories: true)
        try Data("dxvk-d3d9".utf8).write(to: dxvkRoot.appending(path: "d3d9.dll"))
        try Data("dxvk-d3d10".utf8).write(to: dxvkRoot.appending(path: "d3d10core.dll"))
        try Data("dxvk-d3d11".utf8).write(to: dxvkRoot.appending(path: "d3d11.dll"))
        let runtime = makeRuntime(
            root: root,
            features: RuntimeFeatures(
                wow64: true, wineMono: false, wineGecko: false,
                d3dmetal: false, dxmt: false, dxvk: true, vkd3d: true
            )
        )

        #expect(RendererPolicy.preferredBackend(for: .directX11, runtime: runtime) == .dxvk)
        #expect(RendererPolicy.preferredBackend(for: .directX12, runtime: runtime) == .vkd3d)
        #expect(RendererPolicy.preferredBackend(for: .directX9, runtime: runtime) == .dxvk)
    }

    @Test func graphicsResolverTreatsPrefixArchitectureAsRendererConstraint() {
        let runtime = makeRuntime(
            root: FileManager.default.temporaryDirectory,
            features: RuntimeFeatures(
                wow64: true, wineMono: false, wineGecko: false,
                d3dmetal: false, dxmt: true, dxvk: true, vkd3d: false
            )
        )

        let resolution = GraphicsBackendResolver.resolve(
            api: .directX11,
            requestedBackend: .automatic,
            runtime: runtime,
            architecture: .win32
        )

        #expect(resolution.stack.backend == .dxvk)
        #expect(resolution.isAvailable)
        #expect(resolution.reasons.contains("Architecture is supported"))
    }

    @Test func directXDetectorChoosesNewestImportedAPI() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-api-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "game.exe")
        try Data("prefix d3d9.dll middle d3d11.dll suffix".utf8).write(to: executable)

        #expect(GraphicsAPIDetector.detect(executable: executable) == .directX11)
    }

    @Test func directXAnalysisIncludesDelayImportsAndPreservesAmbiguousCandidates() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-delay-api-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "game.exe")
        try makePEImage(
            at: executable,
            imports: ["d3d11.dll"],
            delayImports: ["d3d12.dll"]
        )

        let pe = WindowsPEInspection.inspect(executable)
        let detection = GraphicsAPIDetector.analyze(executable: executable)

        #expect(pe.imports.contains("d3d11.dll"))
        #expect(pe.delayImports.contains("d3d12.dll"))
        #expect(detection.api == nil)
        #expect(detection.confidence == .low)
        #expect(detection.candidates == [.directX12, .directX11])
    }

    @Test func rendererRegistryOverridesAreScopedToTheSelectedAPI() {
        #expect(GraphicsBackendManager.apiSpecificDLLOverrides(for: .dxvk, api: .directX11) == ["d3d11", "dxgi"])
        #expect(GraphicsBackendManager.apiSpecificDLLOverrides(for: .dxvk, api: .directX9) == ["d3d9", "dxgi"])
        #expect(GraphicsBackendManager.apiSpecificDLLOverrides(for: .vkd3d, api: .directX12) == ["d3d12", "d3d12core", "dxgi"])
        #expect(!GraphicsBackendManager.apiSpecificDLLOverrides(for: .dxvk, api: .directX11).contains("d3d12core"))
    }

    @Test func darksidersDeathinitiveProfileSelectsDirectX11AtLaunch() {
        let application = WindowsApplication(
            name: "Darksiders II Deathinitive Edition",
            publisher: "THQ Nordic",
            executablePath: "/tmp/Darksiders2.exe",
            installerPath: "existing-installation",
            environmentID: UUID(),
            storeProvider: .steam,
            storeExternalID: "388410"
        )

        let profile = GameGraphicsProfiles.profile(for: application)
        #expect(profile?.preferredBackend == .dxvk)
        #expect(profile?.defaultAPI == .directX9)
        #expect(profile?.launchOption(for: .directX11)?.arguments == ["-dx11"])
    }

    @Test func godOfWarProfileUsesDXMTForItsDirectX11ShaderPath() {
        let application = WindowsApplication(
            name: "God of War",
            publisher: "Santa Monica Studio",
            executablePath: "/tmp/GoW.exe",
            installerPath: "existing-installation",
            environmentID: UUID(),
            storeProvider: .steam,
            storeExternalID: "1593500"
        )

        let profile = GameGraphicsProfiles.profile(for: application)
        #expect(profile?.defaultAPI == .directX11)
        #expect(profile?.availableAPIs == [.directX11])
        #expect(profile?.preferredBackend == .dxmt)
        #expect(profile?.launchOption(for: .directX11)?.arguments.isEmpty == true)
        #expect(profile?.launchEnvironment?["DXMT_CONFIG"] == "d3d11.sampleNaNToZero=True;d3d11.defuseFma=True;dxmt.shaderMetalVersion=310;")
    }

    @Test func godOfWarShaderWorkaroundsStayScopedToDXMTLaunches() {
        let application = WindowsApplication(
            name: "God of War",
            publisher: "Santa Monica Studio",
            executablePath: "/tmp/GoW.exe",
            installerPath: "existing-installation",
            environmentID: UUID(),
            storeProvider: .steam,
            storeExternalID: "1593500"
        )
        let profile = GameGraphicsProfiles.profile(for: application)
        let plan = WindowsLaunchPlan(
            executable: URL(fileURLWithPath: "/tmp/GoW.exe"),
            arguments: [],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let dxmtPlan = GameGraphicsProfiles.applying(profile, backend: .dxmt, to: plan)
        let d3dMetalPlan = GameGraphicsProfiles.applying(profile, backend: .d3dMetal, to: plan)

        #expect(dxmtPlan.environment["DXMT_CONFIG"]?.contains("sampleNaNToZero=True") == true)
        #expect(d3dMetalPlan.environment["DXMT_CONFIG"] == nil)
    }

    @Test func dawnwalkerUsesDirectDX12D3DMetalLaunchForGOGAndPersistedSteamMetadata() throws {
        for (provider, externalID) in [
            (GameLibraryProvider.gog, "1889754300"),
            (GameLibraryProvider.steam, "3751260")
        ] {
            let profile = try #require(GameGraphicsProfiles.profile(provider: provider, externalID: externalID))
            #expect(profile.defaultAPI == .directX12)
            #expect(profile.enforcedAPI == .directX12)
            #expect(profile.enforcedBackend == .d3dMetal)
            #expect(profile.overlayCompatibleFullscreen == false)
        }
    }

    @Test func dawnwalkerDirectLaunchRecommendationDoesNotOverrideSavedUserChoice() {
        let application = WindowsApplication(
            name: "The Blood of Dawnwalker",
            publisher: "Rebel Wolves",
            executablePath: "/tmp/Dawnwalker.exe",
            installerPath: "existing-installation",
            environmentID: UUID(),
            storeProvider: .gog,
            storeExternalID: "1889754300",
            compatibilityProfile: WineCompatibilityProfile(
                graphicsBackend: .d3dMetal,
                graphicsAPI: .directX12,
                overlayCompatibleFullscreen: true
            )
        )

        let effective = GameGraphicsProfiles.effectiveCompatibilityProfile(
            application.resolvedCompatibilityProfile,
            for: application
        )

        #expect(effective.overlayCompatibleFullscreen)
        #expect(effective.graphicsBackend == .d3dMetal)
        #expect(effective.graphicsAPI == .directX12)
    }

    @Test func graphicsBackendChoicesIncludeEverySupportedRenderer() {
        #expect(WineGraphicsBackend.allCases == [
            .automatic,
            .d3dMetal,
            .dxmt,
            .dxvk,
            .vkd3d,
            .wineD3D
        ])
    }

    @Test func legacyRuntimeFeaturesDecodeWithoutDXVKCapability() throws {
        let data = Data(#"{"wow64":true,"wineMono":false,"wineGecko":false,"d3dmetal":false,"dxmt":true}"#.utf8)
        let features = try JSONDecoder().decode(RuntimeFeatures.self, from: data)

        #expect(features.dxmt)
        #expect(!features.dxvk)

        let legacyData = Data(#"{"wow64":true,"wineMono":false,"wineGecko":false,"d3dmetal":false,"dxmt":false,"d9vk":true}"#.utf8)
        let migratedFeatures = try JSONDecoder().decode(RuntimeFeatures.self, from: legacyData)
        #expect(migratedFeatures.dxvk)
    }

    @Test func dxvkActivationRestoresOriginalPrefixLibrariesWhenReset() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "boreal-graphics-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let components = root.appending(path: "runtime/GraphicsComponents/DXVK/x64", directoryHint: .isDirectory)
        let system32 = root.appending(path: "environment/.prefix-installing/drive_c/windows/system32", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: components, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: system32, withIntermediateDirectories: true)
        try Data("dxvk".utf8).write(to: components.appending(path: "dxgi.dll"))
        try Data("wine".utf8).write(to: system32.appending(path: "dxgi.dll"))
        let runtimeRoot = root.appending(path: "runtime", directoryHint: .isDirectory)
        let runtime = InstalledRuntime(
            id: "test-dxvk",
            displayName: "Test DXVK",
            wineVersion: "test",
            rootURL: runtimeRoot,
            wineExecutable: runtimeRoot.appending(path: "wine"),
            wineServerExecutable: runtimeRoot.appending(path: "wineserver"),
            wineBootExecutable: runtimeRoot.appending(path: "wineboot"),
            architecture: .arm64,
            requirements: [],
            features: RuntimeFeatures(wow64: true, wineMono: false, wineGecko: false, d3dmetal: false, dxmt: false, dxvk: true)
        )
        let environmentRoot = root.appending(path: "environment", directoryHint: .isDirectory)
        let stagingEnvironment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "DXVK"),
            runtimeID: runtime.id,
            rootURL: environmentRoot,
            prefixURL: environmentRoot.appending(path: ".prefix-installing", directoryHint: .isDirectory),
            logsURL: environmentRoot.appending(path: "Logs", directoryHint: .isDirectory),
            state: .ready
        )
        let manager = GraphicsBackendManager()

        let activation = try manager.activate(.dxvk, in: stagingEnvironment, runtime: runtime)

        #expect(activation.backend == .dxvk)
        #expect(activation.dllOverrides == ["dxgi"])
        #expect(try String(contentsOf: system32.appending(path: "dxgi.dll"), encoding: .utf8) == "dxvk")

        let publishedPrefix = environmentRoot.appending(path: "prefix", directoryHint: .isDirectory)
        try fileManager.moveItem(at: stagingEnvironment.prefixURL, to: publishedPrefix)
        let publishedEnvironment = ManagedBorealEnvironment(
            id: stagingEnvironment.id,
            configuration: stagingEnvironment.configuration,
            runtimeID: stagingEnvironment.runtimeID,
            rootURL: environmentRoot,
            prefixURL: publishedPrefix,
            logsURL: stagingEnvironment.logsURL,
            state: .ready
        )
        try manager.prefixDidMove(in: publishedEnvironment, from: stagingEnvironment.prefixURL)
        try manager.reset(publishedEnvironment)

        #expect(try String(contentsOf: publishedPrefix.appending(path: "drive_c/windows/system32/dxgi.dll"), encoding: .utf8) == "wine")
        #expect(!fileManager.fileExists(atPath: environmentRoot.appending(path: ".graphics-backend.json").path))
    }

    @Test func unavailableReplacementBackendLeavesCurrentPrefixActivationUntouched() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "boreal-graphics-rollback-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let runtimeRoot = root.appending(path: "runtime", directoryHint: .isDirectory)
        let dxvk = runtimeRoot.appending(path: "GraphicsComponents/DXVK/x64", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: dxvk, withIntermediateDirectories: true)
        try Data("dxvk-d3d11".utf8).write(to: dxvk.appending(path: "d3d11.dll"))
        try Data("dxvk-dxgi".utf8).write(to: dxvk.appending(path: "dxgi.dll"))

        let runtime = InstalledRuntime(
            id: "rollback-runtime",
            displayName: "Rollback Runtime",
            wineVersion: "test",
            rootURL: runtimeRoot,
            wineExecutable: runtimeRoot.appending(path: "wine"),
            wineServerExecutable: runtimeRoot.appending(path: "wineserver"),
            wineBootExecutable: runtimeRoot.appending(path: "wineboot"),
            architecture: .arm64,
            requirements: [],
            features: RuntimeFeatures(
                wow64: true,
                wineMono: false,
                wineGecko: false,
                d3dmetal: false,
                dxmt: true,
                d3d11Verified: true,
                d3d11VerifiedArchitectures: [.x86_64],
                dxvk: true
            )
        )
        let environmentRoot = root.appending(path: "environment", directoryHint: .isDirectory)
        let prefix = environmentRoot.appending(path: "prefix", directoryHint: .isDirectory)
        let system32 = prefix.appending(path: "drive_c/windows/system32", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: system32, withIntermediateDirectories: true)
        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(
                name: "Rollback",
                profile: WineCompatibilityProfile(graphicsAPI: .directX11)
            ),
            runtimeID: runtime.id,
            rootURL: environmentRoot,
            prefixURL: prefix,
            logsURL: environmentRoot.appending(path: "Logs", directoryHint: .isDirectory),
            state: .ready
        )
        let manager = GraphicsBackendManager()
        _ = try manager.activate(.dxvk, in: environment, runtime: runtime)

        #expect(throws: GraphicsBackendManagerError.self) {
            try manager.activate(.dxmt, in: environment, runtime: runtime)
        }

        #expect(try String(contentsOf: system32.appending(path: "d3d11.dll"), encoding: .utf8) == "dxvk-d3d11")
        #expect(try String(contentsOf: system32.appending(path: "dxgi.dll"), encoding: .utf8) == "dxvk-dxgi")
        #expect(fileManager.fileExists(atPath: environmentRoot.appending(path: ".graphics-backend.json").path))
    }

    @Test func deferredBackendActivationCanRestorePreviousFilesAndManifest() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "boreal-graphics-deferred-rollback-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let runtimeRoot = root.appending(path: "runtime", directoryHint: .isDirectory)
        let dxvk = runtimeRoot.appending(path: "GraphicsComponents/DXVK/x64", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: dxvk, withIntermediateDirectories: true)
        try Data("dxvk-d3d11".utf8).write(to: dxvk.appending(path: "d3d11.dll"))
        try Data("dxvk-dxgi".utf8).write(to: dxvk.appending(path: "dxgi.dll"))

        let runtime = InstalledRuntime(
            id: "deferred-rollback-runtime",
            displayName: "Deferred Rollback Runtime",
            wineVersion: "test",
            rootURL: runtimeRoot,
            wineExecutable: runtimeRoot.appending(path: "wine"),
            wineServerExecutable: runtimeRoot.appending(path: "wineserver"),
            wineBootExecutable: runtimeRoot.appending(path: "wineboot"),
            architecture: .arm64,
            requirements: [],
            features: RuntimeFeatures(wow64: true, wineMono: false, wineGecko: false, d3dmetal: false, dxmt: false, dxvk: true)
        )
        let environmentRoot = root.appending(path: "environment", directoryHint: .isDirectory)
        let prefix = environmentRoot.appending(path: "prefix", directoryHint: .isDirectory)
        let system32 = prefix.appending(path: "drive_c/windows/system32", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: system32, withIntermediateDirectories: true)
        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "Deferred rollback", profile: WineCompatibilityProfile(graphicsAPI: .directX11)),
            runtimeID: runtime.id,
            rootURL: environmentRoot,
            prefixURL: prefix,
            logsURL: environmentRoot.appending(path: "Logs", directoryHint: .isDirectory),
            state: .ready
        )
        let manager = GraphicsBackendManager()
        _ = try manager.activate(.dxvk, in: environment, runtime: runtime)

        let staged = try manager.activate(.wineD3D, in: environment, runtime: runtime, keepRollbackSnapshot: true)

        #expect(staged.rollbackSnapshot != nil)
        #expect(!fileManager.fileExists(atPath: system32.appending(path: "d3d11.dll").path))
        try manager.rollback(staged, in: environment)

        #expect(try String(contentsOf: system32.appending(path: "d3d11.dll"), encoding: .utf8) == "dxvk-d3d11")
        #expect(try String(contentsOf: system32.appending(path: "dxgi.dll"), encoding: .utf8) == "dxvk-dxgi")
        #expect(fileManager.fileExists(atPath: environmentRoot.appending(path: ".graphics-backend.json").path))
    }

    @Test func modernWow64Installs32BitRendererIntoSyswow64() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "boreal-wow64-graphics-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let components = root.appending(path: "runtime/GraphicsComponents/DXVK", directoryHint: .isDirectory)
        let system32 = root.appending(path: "environment/prefix/drive_c/windows/system32", directoryHint: .isDirectory)
        let syswow64 = root.appending(path: "environment/prefix/drive_c/windows/syswow64", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: components.appending(path: "x32"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: components.appending(path: "x64"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: system32, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: syswow64, withIntermediateDirectories: true)
        try Data("dxvk-x32".utf8).write(to: components.appending(path: "x32/d3d9.dll"))
        try Data("wine-x64".utf8).write(to: system32.appending(path: "d3d9.dll"))
        try Data("wine-x32".utf8).write(to: syswow64.appending(path: "d3d9.dll"))
        let runtimeRoot = root.appending(path: "runtime", directoryHint: .isDirectory)
        let runtime = InstalledRuntime(
            id: "test-wow64-dxvk",
            displayName: "Test WoW64 DXVK",
            wineVersion: "test",
            rootURL: runtimeRoot,
            wineExecutable: runtimeRoot.appending(path: "wine"),
            wineServerExecutable: runtimeRoot.appending(path: "wineserver"),
            wineBootExecutable: runtimeRoot.appending(path: "wineboot"),
            architecture: .arm64,
            requirements: [],
            features: RuntimeFeatures(
                wow64: true, wineMono: false, wineGecko: false,
                d3dmetal: false, dxmt: false, dxvk: true
            )
        )
        let environmentRoot = root.appending(path: "environment", directoryHint: .isDirectory)
        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(
                name: "32-bit game in WoW64",
                architecture: WinePrefixArchitecture.win32.rawValue
            ),
            runtimeID: runtime.id,
            rootURL: environmentRoot,
            prefixURL: environmentRoot.appending(path: "prefix", directoryHint: .isDirectory),
            logsURL: environmentRoot.appending(path: "Logs", directoryHint: .isDirectory),
            state: .ready
        )

        let activation = try GraphicsBackendManager().activate(.dxvk, in: environment, runtime: runtime)

        #expect(activation.dllOverrides == ["d3d9"])
        #expect(try String(contentsOf: syswow64.appending(path: "d3d9.dll"), encoding: .utf8) == "dxvk-x32")
        #expect(try String(contentsOf: system32.appending(path: "d3d9.dll"), encoding: .utf8) == "wine-x64")
    }

    @Test func vkd3dActivationInstallsDirectX12LibrariesAndOverrides() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "boreal-vkd3d-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let component = root.appending(path: "runtime/GraphicsComponents/VKD3D/x64", directoryHint: .isDirectory)
        let system32 = root.appending(path: "environment/prefix/drive_c/windows/system32", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: component, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: system32, withIntermediateDirectories: true)
        try Data("vkd3d".utf8).write(to: component.appending(path: "d3d12.dll"))
        try Data("vkd3d-core".utf8).write(to: component.appending(path: "d3d12core.dll"))
        let runtimeRoot = root.appending(path: "runtime", directoryHint: .isDirectory)
        let runtime = InstalledRuntime(
            id: "test-vkd3d", displayName: "Test VKD3D", wineVersion: "test",
            rootURL: runtimeRoot, wineExecutable: runtimeRoot.appending(path: "wine"),
            wineServerExecutable: runtimeRoot.appending(path: "wineserver"),
            wineBootExecutable: runtimeRoot.appending(path: "wineboot"), architecture: .arm64,
            requirements: [],
            features: RuntimeFeatures(
                wow64: true, wineMono: false, wineGecko: false,
                d3dmetal: false, dxmt: false, vkd3d: true
            )
        )
        let environmentRoot = root.appending(path: "environment", directoryHint: .isDirectory)
        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "VKD3D"),
            runtimeID: runtime.id, rootURL: environmentRoot,
            prefixURL: environmentRoot.appending(path: "prefix", directoryHint: .isDirectory),
            logsURL: environmentRoot.appending(path: "Logs", directoryHint: .isDirectory), state: .ready
        )

        let activation = try GraphicsBackendManager().activate(.vkd3d, in: environment, runtime: runtime)

        #expect(activation.backend == .vkd3d)
        #expect(activation.dllOverrides == ["d3d12", "d3d12core"])
        #expect(try String(contentsOf: system32.appending(path: "d3d12.dll"), encoding: .utf8) == "vkd3d")
        #expect(try String(contentsOf: system32.appending(path: "d3d12core.dll"), encoding: .utf8) == "vkd3d-core")
    }

    @Test func everyWindowsApplicationCanPersistAnyGraphicsAPIChoice() throws {
        #expect(GraphicsAPI.allCases == [
            .automatic,
            .directX9,
            .directX10,
            .directX11,
            .directX12
        ])

        let encoded = try JSONEncoder().encode(WineCompatibilityProfile(graphicsAPI: .directX11))
        let decoded = try JSONDecoder().decode(WineCompatibilityProfile.self, from: encoded)

        #expect(decoded.graphicsAPI == .directX11)
    }

    @Test func parsesQuotedLaunchArgumentsWithoutUsingAShell() {
        let profile = WineCompatibilityProfile(
            launchArguments: #"-windowed "C:\Game Files\config.ini" 'safe mode' escaped\ value"#
        )

        #expect(profile.parsedLaunchArguments == [
            "-windowed",
            #"C:\Game Files\config.ini"#,
            "safe mode",
            "escaped value"
        ])
    }

    @Test func legacyProfileDefaultsToOverlayCompatibleFullscreen() throws {
        let data = Data(#"{"windowsVersion":"win10","fullscreenFSREnabled":false}"#.utf8)
        let profile = try JSONDecoder().decode(WineCompatibilityProfile.self, from: data)

        #expect(profile.overlayCompatibleFullscreen)
    }

    @Test func legacyEnvironmentConfigurationUsesSafeDefaults() throws {
        let data = Data(#"{"name":"Legacy","windowsVersion":"win10","architecture":"win32"}"#.utf8)
        let configuration = try JSONDecoder().decode(EnvironmentConfiguration.self, from: data)

        #expect(configuration.windowsVersion == "win10")
        #expect(configuration.architecture == "win32")
        #expect(configuration.graphicsBackend == .automatic)
        #expect(configuration.prefixMode == nil)
        #expect(configuration.resolvedPrefixMode(runtimeSupportsWoW64: true) == .wow64)
        #expect(configuration.resolvedPrefixMode(runtimeSupportsWoW64: false) == .legacyWin32)
        #expect(configuration.esyncEnabled)
        #expect(configuration.msyncEnabled)
        #expect(!configuration.debugLoggingEnabled)
    }

    @Test func legacyApplicationDecodesWithoutCompatibilityProfile() throws {
        let id = UUID()
        let environmentID = UUID()
        let json = #"{"id":"\#(id.uuidString)","name":"Legacy","publisher":"Vendor","executablePath":"/tmp/game.exe","installerPath":"existing-installation","environmentID":"\#(environmentID.uuidString)","status":"Ready","compatibility":"Unknown","windowsVersion":"Windows 10","graphics":"WineD3D","storageBytes":0,"iconSymbol":"app.dashed"}"#
        let application = try JSONDecoder().decode(WindowsApplication.self, from: Data(json.utf8))

        #expect(application.compatibilityProfile == nil)
        #expect(application.resolvedAuxiliaryExecutables.isEmpty)
        #expect(application.resolvedCompatibilityProfile.windowsVersion == .windows10)
        #expect(application.resolvedCompatibilityProfile.graphicsBackend == .wineD3D)
        #expect(application.resolvedCompatibilityProfile.legacyWrapper == .none)
    }

    @Test func legacyCompatibilityProfileDecodesWithoutWrapperFields() throws {
        let data = Data(#"{"windowsVersion":"win7","architecture":"win32","graphicsBackend":"wineD3D","esyncEnabled":false}"#.utf8)
        let profile = try JSONDecoder().decode(WineCompatibilityProfile.self, from: data)

        #expect(profile.windowsVersion == .windows7)
        #expect(profile.architecture == .win32)
        #expect(profile.graphicsBackend == .wineD3D)
        #expect(profile.legacyWrapper == .none)
        #expect(profile.legacyGraphicsAPI == .directDraw)
        #expect(!profile.esyncEnabled)
    }

    @Test func dgVoodooInstallsOnlySelectedLibraryAndResetRemovesIt() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "boreal-wrapper-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let component = root.appending(path: "runtime/GraphicsComponents/dgVoodoo2", directoryHint: .isDirectory)
        let game = root.appending(path: "game", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: component.appending(path: "x86"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: game, withIntermediateDirectories: true)
        try Data("ddraw-wrapper".utf8).write(to: component.appending(path: "x86/ddraw.dll"))
        try Data("d3d8-wrapper".utf8).write(to: component.appending(path: "x86/d3d8.dll"))
        let manifest = LegacyWrapperComponentManifest(
            id: "dgVoodoo2",
            version: "test",
            architectures: ["x86"],
            supportedAPIs: [.directDraw, .direct3D8]
        )
        try JSONEncoder().encode(manifest).write(to: component.appending(path: "manifest.json"))
        let executable = game.appending(path: "game.exe")
        try Data().write(to: executable)
        let runtime = makeRuntime(root: root.appending(path: "runtime"))
        let environment = makeEnvironment(root: root.appending(path: "environment"), architecture: .win32)
        let manager = LegacyWrapperManager()

        let activation = try manager.activate(
            .dgVoodoo2,
            api: .directDraw,
            gameExecutable: executable,
            environment: environment,
            runtime: runtime
        )

        #expect(activation.dllOverrides == [DLLOverride(library: "ddraw", mode: .nativeThenBuiltin)])
        #expect(fileManager.fileExists(atPath: game.appending(path: "ddraw.dll").path))
        #expect(!fileManager.fileExists(atPath: game.appending(path: "d3d8.dll").path))

        try manager.reset(gameExecutable: executable)
        #expect(!fileManager.fileExists(atPath: game.appending(path: "ddraw.dll").path))
        #expect(!fileManager.fileExists(atPath: game.appending(path: ".boreal-legacy-wrapper.json").path))
    }

    @Test func dgVoodooRefusesToOverwriteForeignWrapper() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "boreal-wrapper-foreign-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let component = root.appending(path: "runtime/GraphicsComponents/dgVoodoo2/x86", directoryHint: .isDirectory)
        let game = root.appending(path: "game", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: component, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: game, withIntermediateDirectories: true)
        try Data("managed".utf8).write(to: component.appending(path: "ddraw.dll"))
        try JSONEncoder().encode(LegacyWrapperComponentManifest(
            id: "dgVoodoo2",
            version: "test",
            architectures: ["x86"],
            supportedAPIs: [.directDraw]
        )).write(to: component.deletingLastPathComponent().appending(path: "manifest.json"))
        let executable = game.appending(path: "game.exe")
        let foreign = game.appending(path: "ddraw.dll")
        try Data().write(to: executable)
        try Data("user-mod".utf8).write(to: foreign)
        let manager = LegacyWrapperManager()

        #expect(throws: GraphicsCompatibilityError.self) {
            try manager.activate(
                .dgVoodoo2,
                api: .directDraw,
                gameExecutable: executable,
                environment: makeEnvironment(root: root.appending(path: "environment"), architecture: .win32),
                runtime: makeRuntime(root: root.appending(path: "runtime"))
            )
        }
        #expect(try String(contentsOf: foreign, encoding: .utf8) == "user-mod")
    }

    @Test func graphicsLayerPlanAddsPerLaunchOverrideWithoutDroppingProviderOverrides() {
        let manager = GraphicsCompatibilityManager()
        let plan = WindowsLaunchPlan(
            executable: URL(fileURLWithPath: "/tmp/game.exe"),
            arguments: [],
            environment: ["WINEDLLOVERRIDES": "xaudio2_7=b"],
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let graphics = GraphicsLayerPlan(
            legacyWrapper: .dgVoodoo2,
            backend: .dxvk,
            dllOverrides: [DLLOverride(library: "ddraw", mode: .nativeThenBuiltin)],
            files: []
        )

        let configured = manager.applying(graphics, to: plan)

        #expect(configured.environment["WINEDLLOVERRIDES"] == "xaudio2_7=b;ddraw=n,b")
    }

    @Test func titanQuestProfileMapsDirectXModesToDocumentedArguments() {
        let application = WindowsApplication(
            name: "Titan Quest Anniversary Edition",
            publisher: "THQ Nordic",
            executablePath: "/tmp/steam.exe",
            installerPath: "steam-windows-game",
            environmentID: UUID(),
            storeProvider: .steam,
            storeExternalID: "475150"
        )

        let profile = GameGraphicsProfiles.profile(for: application)
        #expect(profile?.defaultAPI == .directX11)
        #expect(profile?.availableAPIs == [.directX11, .directX9])
        #expect(profile?.launchOption(for: .directX11)?.arguments == ["/dx11"])
        #expect(profile?.launchOption(for: .directX9)?.arguments == ["/dx9"])
    }

    @Test func graphicsLaunchOptionKeepsProviderArgumentsAndAddsAPIArguments() throws {
        let plan = WindowsLaunchPlan(
            executable: URL(fileURLWithPath: "/tmp/steam.exe"),
            arguments: ["-applaunch", "475150"],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let configured = try GameGraphicsProfiles.applying(
            GraphicsAPILaunchOption(api: .directX9, arguments: ["/dx9"]),
            to: plan
        )

        #expect(configured.arguments == ["-applaunch", "475150", "/dx9"])
    }

    @Test func torchlightUsesWineD3DWhenAnOlderProfileSelectedDXVK() throws {
        let application = WindowsApplication(
            name: "Torchlight II",
            publisher: "Runic Games",
            executablePath: "/tmp/Torchlight2.exe",
            installerPath: "",
            environmentID: UUID(),
            storeMetadataOnly: true,
            compatibilityProfile: WineCompatibilityProfile(
                windowsVersion: .windows10,
                architecture: .win32,
                graphicsBackend: .dxvk,
                graphicsAPI: .directX9
            ),
            storeProvider: .steam,
            storeExternalID: "200710"
        )

        let profile = GameGraphicsProfiles.profile(for: application)
        let effective = GameGraphicsProfiles.effectiveCompatibilityProfile(
            application.resolvedCompatibilityProfile,
            for: application
        )

        #expect(profile?.enforcedBackend == .wineD3D)
        #expect(profile?.defaultAPI == .directX9)
        #expect(effective.graphicsBackend == .wineD3D)
        #expect(effective.graphicsAPI == .directX9)
    }

    @Test func boundByFlameUsesWineD3DOpenGLForGOGLaunches() {
        let application = WindowsApplication(
            name: "Bound By Flame",
            publisher: "Spiders",
            executablePath: "/tmp/BoundByFlame.exe",
            installerPath: "existing-installation",
            environmentID: UUID(),
            compatibilityProfile: WineCompatibilityProfile(
                windowsVersion: .windows10,
                architecture: .win32,
                graphicsBackend: .dxvk,
                graphicsAPI: .directX9
            ),
            storeProvider: .gog,
            storeExternalID: "1787707874"
        )

        let profile = GameGraphicsProfiles.profile(for: application)
        let effective = GameGraphicsProfiles.effectiveCompatibilityProfile(
            application.resolvedCompatibilityProfile,
            for: application
        )

        #expect(profile?.defaultAPI == .directX9)
        #expect(profile?.preferredBackend == .wineD3D)
        #expect(profile?.enforcedBackend == .wineD3D)
        #expect(profile?.overlayCompatibleFullscreen == false)
        #expect(profile?.launchEnvironment?["WINE_D3D_CONFIG"] == "renderer=gl")
        #expect(effective.graphicsBackend == .wineD3D)
        #expect(effective.graphicsAPI == .directX9)
    }

    @Test func dragonAgeOriginsUsesWineD3DOpenGLForGOGLaunches() {
        let application = WindowsApplication(
            name: "Dragon Age: Origins - Ultimate Edition",
            publisher: "BioWare",
            executablePath: "/tmp/bin_ship/DAOrigins.exe",
            installerPath: "existing-installation",
            environmentID: UUID(),
            compatibilityProfile: WineCompatibilityProfile(
                windowsVersion: .windows10,
                architecture: .win32,
                graphicsBackend: .wineD3D,
                graphicsFallback: .wineD3DVulkan,
                graphicsAPI: .directX9
            ),
            storeProvider: .gog,
            storeExternalID: "1949616134"
        )

        let profile = GameGraphicsProfiles.profile(for: application)
        let effective = GameGraphicsProfiles.effectiveCompatibilityProfile(
            application.resolvedCompatibilityProfile,
            for: application
        )

        #expect(profile?.defaultAPI == .directX9)
        #expect(profile?.preferredBackend == .wineD3D)
        #expect(profile?.enforcedBackend == .wineD3D)
        #expect(profile?.launchEnvironment?["WINE_D3D_CONFIG"] == "renderer=gl")
        #expect(effective.graphicsBackend == .wineD3D)
        #expect(effective.graphicsFallback == .none)
        #expect(effective.graphicsAPI == .directX9)
    }

    @Test func explicitWineD3DRendererOverridesGameCompatibilityDefault() {
        let plan = WindowsLaunchPlan(
            executable: URL(fileURLWithPath: "/tmp/DAOrigins.exe"),
            arguments: [],
            environment: ["WINE_D3D_CONFIG": "renderer=gl"],
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let vulkan = GameGraphicsProfiles.applying(
            wineD3DRenderer: .vulkan,
            backend: .wineD3D,
            to: plan
        )
        let automatic = GameGraphicsProfiles.applying(
            wineD3DRenderer: .automatic,
            backend: .wineD3D,
            to: plan
        )

        #expect(vulkan.environment["WINE_D3D_CONFIG"] == "renderer=vulkan")
        #expect(automatic.environment["WINE_D3D_CONFIG"] == "renderer=gl")
    }

    @Test func rendererDeviceFailureSelectsGenericWineD3DFallback() {
        let profile = WineCompatibilityProfile(
            graphicsBackend: .dxvk,
            graphicsAPI: .directX9
        )
        let log = "info: DXVK: v1.10.3\nerr: DxvkAdapter: Failed to create device\n"

        #expect(RendererLaunchFailureDetector.shouldUseWineD3DVulkanFallback(stderr: log, profile: profile))
        #expect(RendererLaunchFailureDetector.builtinDLLOverrides(for: .directX9) == ["d3d9"])
    }

    @Test func rendererFallbackDoesNotTriggerForNormalGameOutput() {
        let profile = WineCompatibilityProfile(
            graphicsBackend: .dxvk,
            graphicsAPI: .directX11
        )

        #expect(!RendererLaunchFailureDetector.shouldUseWineD3DVulkanFallback(
            stderr: "info: DXVK: v1.10.3\ninfo: D3D11 device initialized\n",
            profile: profile
        ))
    }

    @Test func torchlightDirectLaunchGetsTheSteamAppIDFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-torchlight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "Torchlight2.exe")
        try Data().write(to: executable)
        let application = WindowsApplication(
            name: "Torchlight II",
            publisher: "Runic Games",
            executablePath: executable.path,
            installerPath: "",
            environmentID: UUID(),
            storeMetadataOnly: true,
            storeProvider: .steam,
            storeExternalID: "200710"
        )

        try GameLaunchCompatibility.prepare(application: application)

        #expect(try String(contentsOf: root.appending(path: "steam_appid.txt"), encoding: .utf8) == "200710\n")
    }

    @Test func torchlightCompatibilityDoesNotTouchSteamManagedInstallations() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-torchlight-steam-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "Torchlight2.exe")
        try Data().write(to: executable)
        let application = WindowsApplication(
            name: "Torchlight II",
            publisher: "Runic Games",
            executablePath: executable.path,
            installerPath: "steam-windows-game",
            environmentID: UUID(),
            storeProvider: .steam,
            storeExternalID: "200710"
        )

        try GameLaunchCompatibility.prepare(application: application)

        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "steam_appid.txt").path))
    }

    private func makeRuntime(
        root: URL,
        features: RuntimeFeatures = RuntimeFeatures(
            wow64: true, wineMono: false, wineGecko: false,
            d3dmetal: false, dxmt: false
        )
    ) -> InstalledRuntime {
        InstalledRuntime(
            id: "test-runtime",
            displayName: "Test Runtime",
            wineVersion: "test",
            rootURL: root,
            wineExecutable: root.appending(path: "wine"),
            wineServerExecutable: root.appending(path: "wineserver"),
            wineBootExecutable: root.appending(path: "wineboot"),
            architecture: .arm64,
            requirements: [],
            features: features
        )
    }

    private func makeEnvironment(root: URL, architecture: WinePrefixArchitecture) -> ManagedBorealEnvironment {
        ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "Test", architecture: architecture.rawValue),
            runtimeID: "test-runtime",
            rootURL: root,
            prefixURL: root.appending(path: "prefix"),
            logsURL: root.appending(path: "Logs"),
            state: .ready
        )
    }

    private func makePEImage(at url: URL, imports: [String], delayImports: [String]) throws {
        let peOffset = 0x80
        let optionalHeaderOffset = peOffset + 24
        let optionalHeaderSize = 240
        let sectionTableOffset = optionalHeaderOffset + optionalHeaderSize
        let rawDataOffset = 0x200
        var data = Data(repeating: 0, count: 0x400)

        func put16(_ value: UInt16, at offset: Int) {
            data[offset] = UInt8(value & 0xff)
            data[offset + 1] = UInt8((value >> 8) & 0xff)
        }
        func put32(_ value: UInt32, at offset: Int) {
            for byte in 0..<4 { data[offset + byte] = UInt8((value >> (byte * 8)) & 0xff) }
        }
        func putLibrary(_ name: String, at offset: Int) {
            for (index, byte) in name.utf8.enumerated() { data[offset + index] = byte }
            data[offset + name.utf8.count] = 0
        }

        data[0] = 0x4d
        data[1] = 0x5a
        put32(UInt32(peOffset), at: 0x3c)
        put32(0x00004550, at: peOffset)
        let fileHeaderOffset = peOffset + 4
        put16(0x8664, at: fileHeaderOffset)
        put16(1, at: fileHeaderOffset + 2)
        put16(UInt16(optionalHeaderSize), at: fileHeaderOffset + 16)
        put16(0x020b, at: optionalHeaderOffset)
        put32(16, at: optionalHeaderOffset + 108)

        let dataDirectoryOffset = optionalHeaderOffset + 112
        put32(0x1000, at: dataDirectoryOffset + 8)
        put32(40, at: dataDirectoryOffset + 12)
        put32(0x1040, at: dataDirectoryOffset + (13 * 8))
        put32(64, at: dataDirectoryOffset + (13 * 8) + 4)

        put32(0x200, at: sectionTableOffset + 8)
        put32(0x1000, at: sectionTableOffset + 12)
        put32(0x200, at: sectionTableOffset + 16)
        put32(UInt32(rawDataOffset), at: sectionTableOffset + 20)

        if let library = imports.first {
            put32(0x1080, at: rawDataOffset)
            put32(0x1060, at: rawDataOffset + 12)
            put32(0x1080, at: rawDataOffset + 16)
            putLibrary(library, at: rawDataOffset + 0x60)
        }
        if let library = delayImports.first {
            put32(1, at: rawDataOffset + 0x40)
            put32(0x1068, at: rawDataOffset + 0x44)
            putLibrary(library, at: rawDataOffset + 0x68)
        }
        try data.write(to: url, options: .atomic)
    }
}
