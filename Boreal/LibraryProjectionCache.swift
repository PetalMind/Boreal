import Foundation

@MainActor
final class LibraryProjectionCache {
    private var applications: [WindowsApplication] = []
    private var storeGames: [StoreLibraryGame] = []
    private var installations: [GameInstallation] = []
    private var hiddenKeys: Set<String> = []
    private var cachedItems: [LibraryItem] = []
    private var revision: UInt = 0
    private var filteredRevision: UInt?
    private var filteredRequest: LibraryProjectionRequest?
    private var filteredItems: [LibraryItem] = []
    private var consoleRevision: UInt?
    private var consoleScope: ConsoleLibraryScope?
    private var consoleFavorites: Set<String> = []
    private var cachedConsoleItems: [LibraryItem] = []

    func items(
        applications: [WindowsApplication],
        storeGames: [StoreLibraryGame],
        installations: [GameInstallation],
        hiddenKeys: Set<String>
    ) -> [LibraryItem] {
        guard applications != self.applications || storeGames != self.storeGames || installations != self.installations || hiddenKeys != self.hiddenKeys else {
            return cachedItems
        }
        revision &+= 1
        self.applications = applications
        self.storeGames = storeGames
        self.installations = installations
        self.hiddenKeys = hiddenKeys
        cachedItems = LibraryProjector.makeItems(applications: applications, storeGames: storeGames, installations: installations)
            .filter { !hiddenKeys.contains($0.favoriteKey) }
        return cachedItems
    }

    func projectedItems(
        applications: [WindowsApplication], storeGames: [StoreLibraryGame],
        installations: [GameInstallation], hiddenKeys: Set<String>,
        request: LibraryProjectionRequest
    ) -> [LibraryItem] {
        let source = items(applications: applications, storeGames: storeGames, installations: installations, hiddenKeys: hiddenKeys)
        // The "recent" cutoff advances with time even if domain data stays unchanged.
        if !request.availability.contains(.recent), filteredRevision == revision, filteredRequest == request {
            return filteredItems
        }
        filteredItems = LibraryProjector.project(
            source, searchText: request.searchText, sources: request.sources,
            availability: request.availability, compatibility: request.compatibility,
            sort: request.sort, producer: request.producer,
            favorites: request.favorites, favoritesOnly: request.favoritesOnly
        )
        filteredRevision = revision
        filteredRequest = request
        return filteredItems
    }

    func consoleItems(
        applications: [WindowsApplication], storeGames: [StoreLibraryGame],
        installations: [GameInstallation], hiddenKeys: Set<String>,
        scope: ConsoleLibraryScope, favorites: Set<String>
    ) -> [LibraryItem] {
        let source = items(applications: applications, storeGames: storeGames, installations: installations, hiddenKeys: hiddenKeys)
        let relevantFavorites: Set<String> = scope == .favorites ? favorites : []
        if consoleRevision == revision, consoleScope == scope, consoleFavorites == relevantFavorites {
            return cachedConsoleItems
        }
        cachedConsoleItems = source.filter { item in
            guard !item.isInstallerOnly else { return false }
            switch scope {
            case .all: return true
            case .installed: return item.installed
            case .recent: return item.lastUsed != nil
            case .favorites: return relevantFavorites.contains(item.favoriteKey)
            }
        }
        .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        consoleRevision = revision
        consoleScope = scope
        consoleFavorites = relevantFavorites
        return cachedConsoleItems
    }

}
