import Foundation
import Testing
@testable import Boreal

struct ArchitectureBoundaryTests {
    @Test func installedRecordWithMissingLocationReconcilesAsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-installation-state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = BorealStorageLayout(applicationSupportURL: root)
        let installation = GameInstallation(
            gameID: UUID(),
            location: .managed(relativePath: "GOG/missing-game"),
            platform: .windows,
            state: .installed
        )

        let resolved = InstallationStateResolver.resolve(installation, layout: layout)

        #expect(resolved.state == .missing)
        #expect(resolved.id == installation.id)

        let existingRoot = root.appending(path: "Games/Existing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: existingRoot, withIntermediateDirectories: true)
        let executable = GameExecutable(relativePath: "Game.exe")
        let executableInstallation = GameInstallation(
            gameID: UUID(),
            location: .external(path: existingRoot.path),
            platform: .windows,
            executables: [executable],
            selectedExecutableID: executable.id,
            state: .installed
        )

        #expect(InstallationStateResolver.resolve(executableInstallation, layout: layout).state == .missing)
    }

    @Test func projectionUsesCanonicalMissingStateInsteadOfLegacyGameFlag() {
        let game = StoreLibraryGame(
            provider: .gog,
            externalID: "missing-123",
            name: "Missing Game",
            isInstalled: false
        )
        let installation = GameInstallation(
            id: game.id,
            gameID: game.id,
            storeReference: game.storeReference,
            location: .external(path: "/Volumes/Disconnected/Missing Game"),
            platform: .windows,
            state: .missing
        )

        let item = LibraryProjector.makeItems(
            applications: [],
            storeGames: [game],
            installations: [installation]
        ).first

        #expect(item?.installed == true)
        #expect(item?.readyToPlay == false)
        #expect(item?.statusText == "Missing files")
    }

    @Test func legacyInstallationMigrationKeepsStableProviderLinkAndApplicationEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-installation-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = BorealStorageLayout(applicationSupportURL: root)
        let environmentID = UUID()
        let game = StoreLibraryGame(
            provider: .epic,
            externalID: "epic-456",
            name: "Migrated Game",
            isInstalled: true,
            installPath: root.appending(path: "Games/Migrated", directoryHint: .isDirectory).path,
            installedPlatform: .windows
        )
        let executable = URL(fileURLWithPath: game.installPath!).appending(path: "Game.exe")
        let application = WindowsApplication(
            name: game.name,
            publisher: "Boreal",
            executablePath: executable.path,
            installerPath: "existing-installation",
            environmentID: environmentID,
            storeProvider: game.provider,
            storeExternalID: game.externalID
        )

        let migrated = InstallationMigration.fromLegacy(
            applications: [application],
            storeGames: [game],
            layout: layout
        )
        let installation = try #require(migrated.first)

        #expect(installation.gameID == game.id)
        #expect(installation.storeReference == game.storeReference)
        #expect(installation.environmentID == environmentID)
        #expect(installation.executables.first?.relativePath == "Game.exe")
    }

    @Test func launchPlanIsImmutableAndDeterministicForTheSameInputs() {
        let applicationID = UUID()
        let environmentID = UUID()
        let runtimeID = "test-runtime"
        let executable = URL(fileURLWithPath: "/Games/Test/Game.exe")
        let windowsPlan = WindowsLaunchPlan(
            executable: executable,
            arguments: ["--fullscreen"],
            environment: ["WINEDLLOVERRIDES": "ddraw=n,b"],
            workingDirectory: executable.deletingLastPathComponent(),
            overlayCompatibleFullscreen: true,
            overlayDisplayID: 1
        )

        let first = LaunchPlan(
            applicationID: applicationID,
            installationID: nil,
            environmentID: environmentID,
            runtimeID: runtimeID,
            provider: .gog,
            externalID: "123",
            windowsPlan: windowsPlan,
            graphicsBackend: .dxvk,
            compatibilityProfile: .default
        )
        let second = LaunchPlan(
            applicationID: applicationID,
            installationID: nil,
            environmentID: environmentID,
            runtimeID: runtimeID,
            provider: .gog,
            externalID: "123",
            windowsPlan: windowsPlan,
            graphicsBackend: .dxvk,
            compatibilityProfile: .default
        )

        #expect(first == second)
        #expect(first.windowsPlan == second.windowsPlan)
    }
}
