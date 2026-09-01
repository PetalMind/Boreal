import Foundation
import Testing
@testable import Boreal

struct GameStoreProviderTests {
    @Test func registryKeepsSteamClientManagedAndExposesDirectMaintenanceOnlyWhereImplemented() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BorealProviderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let registry = GameStoreProviderRegistry([
            SteamGameStoreProvider(libraryService: SteamLibraryService(steamRoot: root)),
            EpicGameStoreProvider(service: LegendaryEpicService(applicationSupportURL: root)),
            GOGGameStoreProvider(service: GOGService(applicationSupportURL: root)),
        ])

        let steam = registry.capabilities(for: .steam)
        #expect(steam.contains(.clientManagedInstall))
        #expect(!steam.contains(.directInstall))
        #expect(!steam.contains(.update))
        #expect(!steam.contains(.verify))

        for provider in [GameLibraryProvider.epic, .gog] {
            let capabilities = registry.capabilities(for: provider)
            #expect(capabilities.contains(.directInstall))
            #expect(capabilities.contains(.update))
            #expect(capabilities.contains(.verify))
            #expect(capabilities.contains(.uninstall))
            #expect(capabilities.contains(.launchPlan))
            #expect(try registry.provider(for: provider).provider == provider)
        }
    }
}
