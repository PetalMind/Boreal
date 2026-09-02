import Foundation
import Testing
@testable import Boreal

struct WineCompatibilityProfileTests {
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
}
