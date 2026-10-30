import Foundation

// MARK: - Discovery view

// The immutable filter snapshot can be evaluated without blocking SwiftUI layout.
nonisolated struct DiscoveryFilters: Hashable, Sendable {
    var scope: DiscoveryScope
    var windowsMethod: AppleGamingWikiPlatform
    var genre: String
    var rating: String
    var storefront: String
    var sortOrder: String
    var hasCompatibilityReportOnly: Bool
    var query: String

    func project(_ catalog: AppleGamingWikiCatalog) -> DiscoveryProjection {
        var result = DiscoveryProjection()
        result.filters = self
        result.trackedCount = catalog.games.count
        var genres = Set<String>()
        var entries: [(game: AppleGamingWikiGame, score: Int)] = []
        entries.reserveCapacity(catalog.games.count)
        let needsRecommendedOrder = sortOrder == "Recommended" || (scope == .recommended && query.isEmpty)
        for (index, game) in catalog.games.enumerated() {
            if index.isMultiple(of: 128), Task.isCancelled { return result }
            genres.formUnion(game.genres ?? [])
            if !game.isTested { result.unknownCount += 1 }
            if game.hasMacSupport { result.macSupportCount += 1 }
            if matchesFilters(game) {
                entries.append((game, needsRecommendedOrder ? recommendationScore(game) : 0))
            }
        }
        result.genres = genres.sorted()
        var recommendedOrder = entries
        if needsRecommendedOrder {
            recommendedOrder.sort { left, right in
                if left.score != right.score { return left.score > right.score }
                if (left.game.coverURL != nil) != (right.game.coverURL != nil) { return left.game.coverURL != nil }
                let comparison = left.game.title.localizedStandardCompare(right.game.title)
                return comparison == .orderedSame ? left.game.id < right.game.id : comparison == .orderedAscending
            }
        }
        guard !Task.isCancelled else { return result }
        if scope == .recommended && query.isEmpty {
            result.recommended = Array(
                recommendedOrder.lazy.map(\.game)
                    .filter { compatibilityRatings(for: $0).contains(.perfect) }.prefix(4))
        }
        if sortOrder == "Recommended" {
            result.games = recommendedOrder.map(\.game)
        } else {
            result.games = entries.map(\.game).sorted {
                let comparison = $0.title.localizedStandardCompare($1.title)
                return comparison == .orderedSame
                    ? $0.id < $1.id
                    : comparison == (sortOrder == "Name Z–A" ? .orderedDescending : .orderedAscending)
            }
        }
        return result
    }

    private func matchesFilters(_ game: AppleGamingWikiGame) -> Bool {
        matchesScope(game)
            && matchesWindowsMethod(game)
            && (query.isEmpty || game.title.localizedCaseInsensitiveContains(query))
            && (!hasCompatibilityReportOnly || compatibilityRatings(for: game).contains { $0 != .unknown && $0 != .notApplicable })
            && (rating == "All ratings"
                || (rating == AppleGamingWikiRating.unknown.rawValue
                    ? !compatibilityRatings(for: game).contains { $0 != .unknown && $0 != .notApplicable }
                    : compatibilityRatings(for: game).contains { $0.rawValue == rating }))
            && (genre == "All genres" || (genre == "Not provided" ? game.genres?.isEmpty != false : game.genres?.contains(genre) == true))
            && (storefront == "All stores" || (storefront == "Steam" ? game.steamAppID != nil : game.steamAppID == nil))
    }

    private func matchesScope(_ game: AppleGamingWikiGame) -> Bool {
        switch scope {
        case .recommended, .all: true
        case .mac: game.hasMacSupport
        case .windows: [game.crossover, game.wine, game.parallels].contains { $0 != .unknown && $0 != .notApplicable }
        }
    }

    private func matchesWindowsMethod(_ game: AppleGamingWikiGame) -> Bool {
        guard scope == .windows, windowsMethod != .all else { return true }
        guard let report = game.rating(for: windowsMethod) else { return false }
        return report != .unknown && report != .notApplicable
    }

    private func compatibilityRatings(for game: AppleGamingWikiGame) -> [AppleGamingWikiRating] {
        switch scope {
        case .mac: [game.native, game.rosetta2]
        case .windows:
            switch windowsMethod {
            case .crossover: [game.crossover]
            case .wine: [game.wine]
            case .parallels: [game.parallels]
            case .all: [game.crossover, game.wine, game.parallels]
            case .native, .rosetta2, .perfect: []
            }
        case .recommended, .all: game.availableRatings.map(\.rating)
        }
    }

    private func recommendationScore(_ game: AppleGamingWikiGame) -> Int {
        let ratings = compatibilityRatings(for: game)
        let perfectPathScore =
            ratings
            .enumerated()
            .first(where: { $0.element == .perfect })
            .map { 100 - ($0.offset * 5) } ?? 0
        // Artwork is presentation quality, not compatibility evidence.
        return perfectPathScore - (ratings.min(by: { $0.rank < $1.rank })?.rank ?? AppleGamingWikiRating.unknown.rank)
    }

}

nonisolated struct DiscoveryProjection: Sendable {
    var filters: DiscoveryFilters?
    var games: [AppleGamingWikiGame] = []
    var recommended: [AppleGamingWikiGame] = []
    var genres: [String] = []
    var trackedCount = 0
    var unknownCount = 0
    var macSupportCount = 0
}

nonisolated struct DiscoveryProjectionRequest: Hashable, Sendable {
    var revision: Int
    var filters: DiscoveryFilters
}
