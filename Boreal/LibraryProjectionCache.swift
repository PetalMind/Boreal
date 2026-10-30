import Foundation

@MainActor
final class LibraryProjectionCache {
    private var applications: [WindowsApplication] = []
    private var storeGames: [StoreLibraryGame] = []
    private var installations: [GameInstallation] = []
    private var hiddenKeys: Set<String> = []
    private var cachedItems: [LibraryItem] = []

    func items(
        applications: [WindowsApplication],
        storeGames: [StoreLibraryGame],
        installations: [GameInstallation],
        hiddenKeys: Set<String>
    ) -> [LibraryItem] {
        guard applications != self.applications || storeGames != self.storeGames || installations != self.installations || hiddenKeys != self.hiddenKeys else {
            return cachedItems
        }
        self.applications = applications
        self.storeGames = storeGames
        self.installations = installations
        self.hiddenKeys = hiddenKeys
        cachedItems = LibraryProjector.makeItems(applications: applications, storeGames: storeGames, installations: installations)
            .filter { !hiddenKeys.contains($0.favoriteKey) }
        return cachedItems
    }
}
