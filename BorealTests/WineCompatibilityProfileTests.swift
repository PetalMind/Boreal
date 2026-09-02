import Foundation
import Testing
@testable import Boreal

struct WineCompatibilityProfileTests {
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
