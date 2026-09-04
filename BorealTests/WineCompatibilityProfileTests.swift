import Foundation
import Testing
@testable import Boreal

struct WineCompatibilityProfileTests {
    @Test func automaticRendererPolicyUsesDXVKForDirectX11WhenAvailable() {
        let runtime = makeRuntime(
            root: FileManager.default.temporaryDirectory,
            features: RuntimeFeatures(
                wow64: true, wineMono: false, wineGecko: false,
                d3dmetal: false, dxmt: true, dxvk: true
            )
        )

        #expect(RendererPolicy.preferredBackend(for: .directX11, runtime: runtime) == .dxvk)
        #expect(RendererPolicy.preferredBackend(for: .directX12, runtime: runtime) == .wineD3D)
        #expect(RendererPolicy.preferredBackend(for: .directX9, runtime: runtime) == .wineD3D)
    }

    @Test func directXDetectorChoosesNewestImportedAPI() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-api-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appending(path: "game.exe")
        try Data("prefix d3d9.dll middle d3d11.dll suffix".utf8).write(to: executable)

        #expect(GraphicsAPIDetector.detect(executable: executable) == .directX11)
    }

    @Test func darksidersDeathinitiveProfileUsesWineD3DFallback() {
        let application = WindowsApplication(
            name: "Darksiders II Deathinitive Edition",
            publisher: "THQ Nordic",
            executablePath: "/tmp/Darksiders2.exe",
            installerPath: "existing-installation",
            environmentID: UUID(),
            storeProvider: .steam,
            storeExternalID: "388410"
        )

        #expect(GameGraphicsProfiles.profile(for: application)?.preferredBackend == .wineD3D)
    }

    @Test func graphicsBackendChoicesIncludeEverySupportedRenderer() {
        #expect(WineGraphicsBackend.allCases == [
            .automatic,
            .d3dMetal,
            .dxmt,
            .dxvk,
            .wineD3D
        ])
    }

    @Test func legacyRuntimeFeaturesDecodeWithoutDXVKCapability() throws {
        let data = Data(#"{"wow64":true,"wineMono":false,"wineGecko":false,"d3dmetal":false,"dxmt":true}"#.utf8)
        let features = try JSONDecoder().decode(RuntimeFeatures.self, from: data)

        #expect(features.dxmt)
        #expect(!features.dxvk)
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

    @Test func legacyEnvironmentConfigurationUsesSafeDefaults() throws {
        let data = Data(#"{"name":"Legacy","windowsVersion":"win10","architecture":"win32"}"#.utf8)
        let configuration = try JSONDecoder().decode(EnvironmentConfiguration.self, from: data)

        #expect(configuration.windowsVersion == "win10")
        #expect(configuration.architecture == "win32")
        #expect(configuration.graphicsBackend == .automatic)
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

    @Test func graphicsLaunchOptionKeepsProviderArgumentsAndAddsAPIArguments() {
        let plan = WindowsLaunchPlan(
            executable: URL(fileURLWithPath: "/tmp/steam.exe"),
            arguments: ["-applaunch", "475150"],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let configured = GameGraphicsProfiles.applying(
            GraphicsAPILaunchOption(api: .directX9, arguments: ["/dx9"]),
            to: plan
        )

        #expect(configured.arguments == ["-applaunch", "475150", "/dx9"])
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
}
