import CryptoKit
import Foundation
import SwiftUI
import AppKit

// MARK: - AppleGamingWiki catalog

nonisolated enum AppleGamingWikiRating: String, Codable, CaseIterable, Hashable, Sendable {
    case perfect = "Perfect"
    case playable = "Playable"
    case runs = "Runs"
    case menu = "Menu"
    case unplayable = "Unplayable"
    case unknown = "Unknown"
    case notApplicable = "N/A"

    init(sourceValue: String) {
        switch sourceValue.lowercased().replacingOccurrences(of: "-", with: "") {
        case "perfect": self = .perfect
        case "playable": self = .playable
        case "runs": self = .runs
        case "menu": self = .menu
        case "unplayable": self = .unplayable
        case "na", "notapplicable": self = .notApplicable
        default: self = .unknown
        }
    }

    var symbol: String {
        switch self {
        case .perfect: "checkmark.seal.fill"
        case .playable: "checkmark.circle.fill"
        case .runs: "play.circle.fill"
        case .menu: "rectangle.on.rectangle"
        case .unplayable: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        case .notApplicable: "minus.circle"
        }
    }

    var isPlayable: Bool {
        switch self {
        case .perfect, .playable: true
        case .runs, .menu, .unplayable, .unknown, .notApplicable: false
        }
    }

    var displayName: String {
        switch self {
        case .perfect: String(localized: .Compatibility.excellentTitle)
        case .playable: String(localized: .Compatibility.goodTitle)
        case .runs: String(localized: .Compatibility.limitedTitle)
        case .menu: String(localized: .Compatibility.menuOnlyTitle)
        case .unplayable: String(localized: .Compatibility.brokenTitle)
        case .unknown: String(localized: .Compatibility.unknownTitle)
        case .notApplicable: String(localized: .Compatibility.notApplicableTitle)
        }
    }

    var localizedDisplayName: LocalizedStringResource {
        switch self {
        case .perfect: .Compatibility.excellentTitle
        case .playable: .Compatibility.goodTitle
        case .runs: .Compatibility.limitedTitle
        case .menu: .Compatibility.menuOnlyTitle
        case .unplayable: .Compatibility.brokenTitle
        case .unknown: .Compatibility.unknownTitle
        case .notApplicable: .Compatibility.notApplicableTitle
        }
    }
}

nonisolated enum AppleGamingWikiPlatform: String, CaseIterable, Hashable, Sendable {
    case all
    case perfect
    case native
    case rosetta2
    case crossover
    case wine
    case parallels

    var title: String {
        switch self {
        case .all: String(localized: "All Windows paths")
        case .perfect: String(localized: "Perfect games")
        case .native: String(localized: "Native")
        case .rosetta2: String(localized: .Compatibility.rosetta2Title)
        case .crossover: String(localized: .Compatibility.crossOverTitle)
        case .wine: String(localized: .Compatibility.wineTitle)
        case .parallels: String(localized: .Compatibility.parallelsTitle)
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .perfect: "checkmark.seal.fill"
        case .native: "apple.logo"
        case .rosetta2: "cpu"
        case .crossover: "rectangle.2.swap"
        case .wine: "wineglass"
        case .parallels: "rectangle.split.3x1"
        }
    }
}

nonisolated enum DiscoveryScope: String, CaseIterable, Hashable, Sendable {
    case recommended
    case all
    case mac
    case windows

    var title: String {
        switch self {
        case .recommended: String(localized: "Recommended")
        case .all: String(localized: "All Games")
        case .mac: String(localized: "Mac")
        case .windows: String(localized: "Windows")
        }
    }

    var symbol: String {
        switch self {
        case .recommended: "sparkles"
        case .all: "square.grid.2x2"
        case .mac: "apple.logo"
        case .windows: "wineglass"
        }
    }
}

nonisolated enum DiscoveryMacSupportKind: Hashable, Sendable {
    case native
    case rosetta2
    case macOS

    var title: String {
        switch self {
        case .native: String(localized: .Compatibility.nativeTitle)
        case .rosetta2: String(localized: .Compatibility.rosetta2Title)
        case .macOS: String(localized: "macOS")
        }
    }

    var symbol: String {
        switch self {
        case .native, .macOS: "apple.logo"
        case .rosetta2: "cpu"
        }
    }
}

nonisolated struct AppleGamingWikiRatingEntry: Hashable, Sendable {
    let title: String
    let rating: AppleGamingWikiRating

    var localizedTitle: LocalizedStringResource {
        switch title {
        case "Native": .Compatibility.nativeTitle
        case "Rosetta 2": .Compatibility.rosetta2Title
        case "CrossOver": .Compatibility.crossOverTitle
        case "Wine": .Compatibility.wineTitle
        case "Parallels": .Compatibility.parallelsTitle
        default: .Compatibility.unknownTitle
        }
    }
}

nonisolated struct AppleGamingWikiGame: Codable, Hashable, Sendable, Identifiable {
    var title: String
    var pageURL: String
    var native: AppleGamingWikiRating
    var rosetta2: AppleGamingWikiRating
    var crossover: AppleGamingWikiRating
    var wine: AppleGamingWikiRating
    var parallels: AppleGamingWikiRating
    var linuxARM: AppleGamingWikiRating

    var steamAppID: String?
    var coverURL: String?
    var genres: [String]?
    var macOSStoreSupport: Bool?

    var id: String { pageURL }
    var isTested: Bool { !availableRatings.isEmpty }
    var hasNativeMacOSReport: Bool { native.isPlayable }
    var hasMacSupport: Bool { hasNativeMacOSReport || rosetta2.isPlayable || macOSStoreSupport == true }
    var macSupportKind: DiscoveryMacSupportKind? {
        if native.isPlayable { return .native }
        if rosetta2.isPlayable { return .rosetta2 }
        if macOSStoreSupport == true { return .macOS }
        return nil
    }
    var bestMethod: String {
        availableRatings.filter { $0.rating.isPlayable }
            .min(by: { $0.rating.rank < $1.rating.rank })?.title ?? (hasMacSupport ? "macOS" : "Unverified")
    }
    var bestRating: AppleGamingWikiRating {
        availableRatings.map(\.rating).min(by: { $0.rank < $1.rank }) ?? .unknown
    }


    func rating(for platform: AppleGamingWikiPlatform) -> AppleGamingWikiRating? {
        switch platform {
        case .all, .perfect: nil
        case .native: native
        case .rosetta2: rosetta2
        case .crossover: crossover
        case .wine: wine
        case .parallels: parallels
        }
    }

    func matches(_ platform: AppleGamingWikiPlatform) -> Bool {
        switch platform {
        case .all: true
        case .perfect:
            [native, rosetta2, crossover, wine, parallels].contains(.perfect)
        case .native: hasNativeMacOSReport
        case .rosetta2: rosetta2.isPlayable
        case .crossover: crossover.isPlayable
        case .wine: wine.isPlayable
        case .parallels: parallels.isPlayable
        }
    }

    var availableRatings: [AppleGamingWikiRatingEntry] {
        [
            AppleGamingWikiRatingEntry(title: "Native", rating: native),
            AppleGamingWikiRatingEntry(title: "Rosetta 2", rating: rosetta2),
            AppleGamingWikiRatingEntry(title: "CrossOver", rating: crossover),
            AppleGamingWikiRatingEntry(title: "Wine", rating: wine),
            AppleGamingWikiRatingEntry(title: "Parallels", rating: parallels),
        ].filter { $0.rating != .unknown && $0.rating != .notApplicable }
    }
}

nonisolated struct AppleGamingWikiCatalog: Codable, Hashable, Sendable {
    var games: [AppleGamingWikiGame]
    var fetchedAt: Date
    var sourceUpdatedAt: Date?
    var isStale = false
    var sourceNotice: String?
    var steamOffset: Int?
    var steamTotal: Int?

    var trackedCount: Int { games.count }
    var playableCount: Int { games.filter { $0.availableRatings.contains { $0.rating.isPlayable } }.count }
    var macSupportCount: Int { games.filter(\.hasMacSupport).count }

    func count(for platform: AppleGamingWikiPlatform) -> Int {
        games.filter { $0.matches(platform) }.count
    }
}

nonisolated struct DiscoveryGameMetadata: Codable, Hashable, Sendable {
    var summary: String?
    var coverImageURL: String?
    var originalImageURL: String?
    var sourceURL: String
    var fetchedAt: Date
    var steamAppID: String?
    var developer: String?
    var genres: [String]?

    var hasPresentationContent: Bool {
        summary?.isEmpty == false || coverImageURL != nil || originalImageURL != nil
    }
}

nonisolated enum AppleGamingWikiDiscoveryState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

nonisolated protocol DiscoveryCatalogLoading: Sendable {
    func savedCatalog() async -> AppleGamingWikiCatalog?
    func loadCatalog(forceRefresh: Bool) async throws -> AppleGamingWikiCatalog
    func cachedMetadata(for games: [AppleGamingWikiGame]) async -> [String: DiscoveryGameMetadata]
    func metadata(for game: AppleGamingWikiGame, forceRefresh: Bool) async -> DiscoveryGameMetadata?
    func loadMoreSteam(in catalog: AppleGamingWikiCatalog) async throws -> AppleGamingWikiCatalog
    func searchMacGames(named query: String) async throws -> [AppleGamingWikiGame]
    func searchMacGames(developer: String) async throws -> [AppleGamingWikiGame]
}

extension DiscoveryCatalogLoading {
    func savedCatalog() async -> AppleGamingWikiCatalog? { nil }

    func cachedMetadata(for games: [AppleGamingWikiGame]) async -> [String: DiscoveryGameMetadata] {
        _ = games
        return [:]
    }
    func searchMacGames(named query: String) async throws -> [AppleGamingWikiGame] { [] }
    func searchMacGames(developer: String) async throws -> [AppleGamingWikiGame] { [] }
    func loadMoreSteam(in catalog: AppleGamingWikiCatalog) async throws -> AppleGamingWikiCatalog { catalog }
    func metadata(for game: AppleGamingWikiGame, forceRefresh: Bool) async -> DiscoveryGameMetadata? {
        _ = game
        _ = forceRefresh
        return nil
    }
}

nonisolated enum AppleGamingWikiDiscoveryError: LocalizedError, Sendable {
    case invalidResponse
    case invalidHTML
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "AppleGamingWiki returned an invalid response."
        case .invalidHTML: "AppleGamingWiki changed the format of its public game list."
        case .emptyCatalog: "AppleGamingWiki returned no game records."
        }
    }
}

// MARK: - GoG Revived public catalog

nonisolated struct GOGRevivedEntry: Codable, Hashable, Sendable, Identifiable {
    var title: String
    var pageURL: String
    var version: String?
    var platforms: [String]
    var year: Int?
    var size: String?
    var isRecent: Bool

    var id: String { pageURL }
}

nonisolated enum GOGRevivedAvailability: Equatable, Sendable {
    case unknown
    case checking
    case available(GOGRevivedEntry)
    case notFound
    case unavailable
}

nonisolated protocol GOGRevivedCatalogLoading: Sendable {
    func lookup(named title: String) async throws -> GOGRevivedEntry?
}

actor GOGRevivedCatalogService: GOGRevivedCatalogLoading {
    private let session: URLSession

    init(applicationSupportURL: URL? = nil, session: URLSession = .shared) {
        self.session = session
        _ = applicationSupportURL
    }

    func lookup(named title: String) async throws -> GOGRevivedEntry? {
        guard var components = URLComponents(string: "https://gog-rev.com/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: title)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Boreal/1.0 (title availability lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppleGamingWikiDiscoveryError.invalidResponse }
        let html = String(decoding: data, as: UTF8.self)
        guard let json = AppleGamingWikiDiscoveryService.firstMatch(#"const initialGames = (\[.*?\]);"#, in: html),
              let jsonData = json.data(using: .utf8),
              let games = try? JSONDecoder().decode([SearchGame].self, from: jsonData) else {
            throw AppleGamingWikiDiscoveryError.invalidHTML
        }
        let requestedKey = Self.normalizedTitle(title)
        guard let game = games.first(where: { Self.normalizedTitle($0.title) == requestedKey }) else { return nil }
        return GOGRevivedEntry(
            title: game.title,
            pageURL: "https://gog-rev.com/games/\(game.slug)",
            version: game.currentVersion,
            platforms: [game.platforms.windows ? "Windows" : nil, game.platforms.macos ? "macOS" : nil, game.platforms.linux ? "Linux" : nil].compactMap { $0 },
            year: game.releaseTimestamp.map { Calendar(identifier: .gregorian).component(.year, from: Date(timeIntervalSince1970: TimeInterval($0))) },
            size: game.downloadSizeBadge,
            isRecent: false
        )
    }

    private struct SearchGame: Decodable {
        struct Platforms: Decodable { let windows: Bool; let macos: Bool; let linux: Bool }
        let slug: String
        let title: String
        let currentVersion: String?
        let downloadSizeBadge: String?
        let releaseTimestamp: Int?
        let platforms: Platforms
    }

    private static func normalizedTitle(_ value: String) -> String {
        var value = " " + value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased() + " "
        for (roman, number) in [(" viii ", " 8 "), (" vii ", " 7 "), (" vi ", " 6 "), (" v ", " 5 "), (" iv ", " 4 "), (" iii ", " 3 "), (" ii ", " 2 "), (" i ", " 1 ")] {
            value = value.replacingOccurrences(of: roman, with: number)
        }
        return value.filter { $0.isLetter || $0.isNumber }
    }
}

actor AppleGamingWikiDiscoveryService: DiscoveryCatalogLoading {
    private struct MediaWikiResponse: Decodable {
        struct Query: Decodable {
            let pages: [String: Page]
        }

        struct Page: Decodable {
            struct Image: Decodable {
                let source: String
            }

            let pageid: Int?
            let title: String
            let fullurl: String?
            let extract: String?
            let thumbnail: Image?
            let original: Image?
        }

        let query: Query?
    }

    static let masterListURL = URL(string: "https://www.applegamingwiki.com/wiki/M1_compatible_games_master_list")!
    private static let cacheLifetime: TimeInterval = 24 * 60 * 60
    private static let unavailableMetadataLifetime: TimeInterval = 15 * 60

    private let session: URLSession
    private let cacheURL: URL?
    private let metadataCacheURL: URL?
    private let metadataEntriesURL: URL?
    private let unavailableMetadataCacheURL: URL?
    private var metadataCache: [String: DiscoveryGameMetadata]?
    private var metadataCachePrepared = false
    private var metadataAccessOrder: [String] = []
    private var unavailableMetadataCache: [String: Date]?
    private var unavailableMetadataCacheWriteTask: Task<Void, Never>?

    init(applicationSupportURL: URL? = nil, session: URLSession = .shared) {
        self.session = session
        cacheURL = applicationSupportURL?.appending(path: "Discovery/applegamingwiki.json", directoryHint: .notDirectory)
        metadataCacheURL = applicationSupportURL?.appending(path: "Discovery/applegamingwiki-metadata.json", directoryHint: .notDirectory)
        metadataEntriesURL = applicationSupportURL?.appending(path: "Discovery/metadata", directoryHint: .isDirectory)
        unavailableMetadataCacheURL = applicationSupportURL?.appending(path: "Discovery/applegamingwiki-unavailable.json", directoryHint: .notDirectory)
    }

    func savedCatalog() async -> AppleGamingWikiCatalog? {
        readCache() ?? Self.bundledCatalog()
    }

    func loadCatalog(forceRefresh: Bool) async throws -> AppleGamingWikiCatalog {
        let cached = readCache() ?? Self.bundledCatalog()
        if !forceRefresh,
           let cached,
           !cached.isStale,
           Date.now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return cached
        }

        do {
            async let wikiRequest = try? fetchCatalog()
            async let steamRequest = try? fetchSteamPage(offset: 0)
            let (wiki, steam) = await (wikiRequest, steamRequest)
            guard wiki != nil || steam != nil else { throw AppleGamingWikiDiscoveryError.invalidResponse }
            var catalog = wiki ?? cached ?? AppleGamingWikiCatalog(games: [], fetchedAt: .now)
            catalog.isStale = wiki == nil
            catalog.sourceNotice = wiki == nil ? "AppleGamingWiki unavailable; showing saved compatibility and live Steam data." : wiki?.sourceNotice
            if let cached, wiki != nil {
                // A refresh fetches only the first Steam page, not the entire store.
                // Keep previously discovered store records rather than dropping thousands.
                let savedSteamGames = cached.games.filter { $0.macOSStoreSupport == true && $0.steamAppID != nil }
                catalog.games = Self.merge(catalog.games, savedSteamGames)
            }
            if let steam {
                catalog.games = Self.merge(catalog.games, steam.games)
                catalog.steamOffset = steam.offset
                catalog.steamTotal = steam.total
            } else {
                catalog.sourceNotice = "Steam unavailable; showing AppleGamingWiki compatibility data."
            }
            catalog.fetchedAt = .now
            writeCache(catalog)
            return catalog
        } catch {
            guard var cached else { throw error }
            cached.isStale = true
            cached.sourceNotice = "Sources unavailable. Showing the last saved catalog."
            return cached
        }
    }

    func cachedMetadata(for games: [AppleGamingWikiGame]) async -> [String: DiscoveryGameMetadata] {
        prepareMetadataCache()
        let cutoff = Date.now.addingTimeInterval(-Self.cacheLifetime)
        var result: [String: DiscoveryGameMetadata] = [:]
        for game in games {
            guard let metadata = cachedMetadata(for: game.id), metadata.fetchedAt >= cutoff else { continue }
            result[game.id] = metadata
        }
        return result
    }

    func metadata(for game: AppleGamingWikiGame, forceRefresh: Bool) async -> DiscoveryGameMetadata? {
        prepareMetadataCache()
        if unavailableMetadataCache == nil { unavailableMetadataCache = readUnavailableMetadataCache() }
        if !forceRefresh, let cached = cachedMetadata(for: game.id),
           Date.now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime { return cached }
        if !forceRefresh, let failedAt = unavailableMetadataCache?[game.id],
           Date.now.timeIntervalSince(failedAt) < Self.unavailableMetadataLifetime { return nil }
        guard !Task.isCancelled else { return nil }
        if let metadata = await steamMetadata(for: game) {
            guard !Task.isCancelled else { return nil }
            cache(metadata, for: game.id)
            return metadata
        }
        guard !Task.isCancelled else { return nil }
        guard URL(string: game.pageURL)?.host == "www.applegamingwiki.com" else {
            return cachedOrMarkUnavailable(game.id)
        }

        guard var components = URLComponents(string: "https://www.applegamingwiki.com/w/api.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "pageimages|extracts|info"),
            URLQueryItem(name: "inprop", value: "url"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "piprop", value: "thumbnail|original"),
            URLQueryItem(name: "pithumbsize", value: "720"),
            URLQueryItem(name: "titles", value: Self.pageTitle(for: game)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "1"),
        ]
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("Boreal/1.0 (https://github.com/dominik/Boreal)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let page = try JSONDecoder().decode(MediaWikiResponse.self, from: data).query?.pages.values.first,
                  page.pageid != nil else { return cachedOrMarkUnavailable(game.id) }

            let metadata = DiscoveryGameMetadata(
                summary: Self.cleanedSummary(page.extract, gameTitle: game.title),
                coverImageURL: page.thumbnail?.source,
                originalImageURL: page.original?.source,
                sourceURL: page.fullurl ?? game.pageURL,
                fetchedAt: .now
            )
            guard metadata.hasPresentationContent else { return cachedOrMarkUnavailable(game.id) }
            cache(metadata, for: game.id)
            return metadata
        } catch is CancellationError {
            return nil
        } catch {
            return cachedOrMarkUnavailable(game.id)
        }
    }

    private func cache(_ metadata: DiscoveryGameMetadata, for id: String) {
        prepareMetadataCache()
        cacheInMemory(metadata, for: id)
        writeMetadataEntry(metadata, for: id)
        unavailableMetadataCache?.removeValue(forKey: id)
        scheduleUnavailableMetadataCacheWrite()
    }

    private func cachedOrMarkUnavailable(_ id: String) -> DiscoveryGameMetadata? {
        if let cached = cachedMetadata(for: id) { return cached }
        unavailableMetadataCache?[id] = .now
        scheduleUnavailableMetadataCacheWrite()
        return nil
    }

    private func cachedMetadata(for id: String) -> DiscoveryGameMetadata? {
        if let metadata = metadataCache?[id] {
            cacheInMemory(metadata, for: id)
            return metadata
        }
        guard let url = metadataEntryURL(for: id),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode(DiscoveryGameMetadata.self, from: data) else { return nil }
        cacheInMemory(metadata, for: id)
        return metadata
    }

    private func cacheInMemory(_ metadata: DiscoveryGameMetadata, for id: String) {
        metadataCache = metadataCache ?? [:]
        metadataCache?[id] = metadata
        metadataAccessOrder.removeAll { $0 == id }
        metadataAccessOrder.append(id)
        while metadataAccessOrder.count > 128 {
            let evictedID = metadataAccessOrder.removeFirst()
            metadataCache?.removeValue(forKey: evictedID)
        }
    }

    private func prepareMetadataCache() {
        guard !metadataCachePrepared else { return }
        metadataCachePrepared = true
        metadataCache = metadataCache ?? [:]
        guard let metadataEntriesURL,
              !FileManager.default.fileExists(atPath: metadataEntriesURL.path) else { return }
        let legacy = readMetadataCache()
        guard !legacy.isEmpty else { return }
        for (id, metadata) in legacy {
            writeMetadataEntry(metadata, for: id)
        }
    }

    private func metadataEntryURL(for id: String) -> URL? {
        guard let metadataEntriesURL else { return nil }
        let digest = SHA256.hash(data: Data(id.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return metadataEntriesURL.appending(path: "\(digest).json", directoryHint: .notDirectory)
    }

    private func writeMetadataEntry(_ metadata: DiscoveryGameMetadata, for id: String) {
        guard let url = metadataEntryURL(for: id) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(metadata).write(to: url, options: .atomic)
        } catch {
            // The metadata remains useful in memory when the optional disk cache is unavailable.
        }
    }

    private func scheduleUnavailableMetadataCacheWrite() {
        unavailableMetadataCacheWriteTask?.cancel()
        unavailableMetadataCacheWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.writeUnavailableMetadataCache()
        }
    }

    private func fetchCatalog() async throws -> AppleGamingWikiCatalog {
        var pageURL = Self.masterListURL
        var seenURLs: Set<String> = []
        var games: [AppleGamingWikiGame] = []
        var sourceUpdatedAt: Date?
        var partial = false

        while seenURLs.insert(pageURL.absoluteString).inserted {
            let html: String
            do { html = try await fetchHTML(from: pageURL) }
            catch {
                if games.isEmpty { throw error }
                partial = true
                break
            }
            let pageGames = Self.parseGames(from: html)
            if pageGames.isEmpty && !games.isEmpty { partial = true; break }
            if sourceUpdatedAt == nil { sourceUpdatedAt = Self.sourceDate(in: html) }
            games.append(contentsOf: pageGames)

            guard let next = Self.nextPageURL(in: html) else { break }
            pageURL = next
        }

        var unique: [String: AppleGamingWikiGame] = [:]
        for game in games { unique[game.id] = game }
        let normalized = unique.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard !normalized.isEmpty else { throw AppleGamingWikiDiscoveryError.emptyCatalog }
        guard normalized.count >= 100 else { throw AppleGamingWikiDiscoveryError.invalidHTML }

        return AppleGamingWikiCatalog(
            games: normalized,
            fetchedAt: .now,
            sourceUpdatedAt: sourceUpdatedAt,
            sourceNotice: partial ? "AppleGamingWiki limits public access to \(normalized.count) records. Use Steam search to discover more macOS games." : nil
        )
    }

    private func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Boreal/1.0 (https://github.com/dominik/Boreal)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw AppleGamingWikiDiscoveryError.invalidResponse
        }
        return html
    }

    private func readCache() -> AppleGamingWikiCatalog? {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppleGamingWikiCatalog.self, from: data)
    }

    private func writeCache(_ catalog: AppleGamingWikiCatalog) {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(catalog).write(to: cacheURL, options: .atomic)
        } catch {
            // The catalog remains useful for the current session when the cache is unavailable.
        }
    }

    private func readMetadataCache() -> [String: DiscoveryGameMetadata] {
        guard let metadataCacheURL,
              let data = try? Data(contentsOf: metadataCacheURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: DiscoveryGameMetadata].self, from: data)) ?? [:]
    }

    private func readUnavailableMetadataCache() -> [String: Date] {
        guard let unavailableMetadataCacheURL,
              let data = try? Data(contentsOf: unavailableMetadataCacheURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }

    private func writeUnavailableMetadataCache() {
        guard let unavailableMetadataCacheURL, let unavailableMetadataCache else { return }
        do {
            try FileManager.default.createDirectory(
                at: unavailableMetadataCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(unavailableMetadataCache).write(to: unavailableMetadataCacheURL, options: .atomic)
        } catch {
            // A failed lookup may be retried next time when this optional cache is unavailable.
        }
    }

    static func parseGames(from html: String) -> [AppleGamingWikiGame] {
        let rows = matches(#"<tr[^>]*class="[^"]*table-listofgames-body-row[^"]*"[^>]*>(.*?)</tr>"#, in: html)
        return rows.compactMap { row in
            let normalizedRow = row.replacingOccurrences(of: "&#95;", with: "_")
            guard let nameMatch = firstMatch(#"<th[^>]*table-listofgames-body-name[^>]*>.*?<a[^>]*title="([^"]+)"[^>]*>.*?</a>"#, in: row),
                  let href = firstMatch(#"<th[^>]*table-listofgames-body-name[^>]*>.*?<a[^>]*href="([^"]+)"[^>]*"#, in: row),
                  !decodeHTML(nameMatch).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let title = decodeHTML(nameMatch)

            let pageURL: String
            if let url = URL(string: decodeHTML(href), relativeTo: masterListURL)?.absoluteURL {
                pageURL = url.absoluteString
            } else {
                pageURL = "https://www.applegamingwiki.com\(href)"
            }

            return AppleGamingWikiGame(
                title: title,
                pageURL: pageURL,
                native: rating(in: normalizedRow, field: "native"),
                rosetta2: rating(in: normalizedRow, field: "rosetta_2"),
                crossover: rating(in: normalizedRow, field: "crossover"),
                wine: rating(in: normalizedRow, field: "wine"),
                parallels: rating(in: normalizedRow, field: "parallels"),
                linuxARM: rating(in: normalizedRow, field: "linux_arm")
            )
        }
    }

    private static func rating(in row: String, field: String) -> AppleGamingWikiRating {
        let pattern = #"<td[^>]*class="[^"]*table-listofgames-body-#(field)[^"]*"[^>]*>.*?rating-([a-z0-9-]+)"#
        guard let raw = firstMatch(pattern, in: row) else { return .unknown }
        return AppleGamingWikiRating(sourceValue: raw)
    }

    private static func nextPageURL(in html: String) -> URL? {
        guard let href = firstMatch(#"href="([^"]*Special:ViewData[^"]*offset=[^"]+)"[^>]*>More"#, in: html) else { return nil }
        return URL(string: decodeHTML(href), relativeTo: masterListURL)?.absoluteURL
    }

    private static func sourceDate(in html: String) -> Date? {
        guard let raw = firstMatch(#"last refreshed on\s*<b>([^<]+)</b>"#, in: html) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.date(from: raw.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func pageTitle(for game: AppleGamingWikiGame) -> String {
        guard let url = URL(string: game.pageURL) else { return game.title }
        let component = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return component.replacingOccurrences(of: "_", with: " ")
    }

    private static func cleanedSummary(_ value: String?, gameTitle: String) -> String? {
        guard let value else { return nil }
        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let meaningful = lines.first(where: {
            $0.localizedCaseInsensitiveCompare(gameTitle) != .orderedSame && $0.count >= 24
        }) else { return nil }
        return meaningful.count > 700 ? String(meaningful.prefix(697)) + "…" : meaningful
    }

    static func matches(_ pattern: String, in value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[range])
        }
    }

    static func firstMatch(_ pattern: String, in value: String) -> String? {
        matches(pattern, in: value).first
    }

    static func decodeHTML(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let numericPattern = #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#
        guard let expression = try? NSRegularExpression(pattern: numericPattern) else { return result }
        let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in expression.matches(in: result, range: fullRange).reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let hex = match.numberOfRanges > 1 ? Range(match.range(at: 1), in: result).map { String(result[$0]) } : nil
            let decimal = match.numberOfRanges > 2 ? Range(match.range(at: 2), in: result).map { String(result[$0]) } : nil
            guard let scalarValue = hex.flatMap({ UInt32($0, radix: 16) }) ?? decimal.flatMap({ UInt32($0) }),
                  let scalar = UnicodeScalar(scalarValue) else { continue }
            result.replaceSubrange(matchRange, with: String(scalar))
        }
        return result
    }
}


extension AppleGamingWikiDiscoveryService {
    nonisolated static func bundledCatalog() -> AppleGamingWikiCatalog? {
        guard let url = Bundle.main.url(forResource: "DiscoveryCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppleGamingWikiCatalog.self, from: data)
    }

    private struct SteamPage {
        var games: [AppleGamingWikiGame]
        var offset: Int
        var total: Int
    }

    private func fetchSteamPage(offset: Int, query: String? = nil, developer: String? = nil) async throws -> SteamPage {
        var components = URLComponents(string: "https://store.steampowered.com/search/results/")!
        components.queryItems = [
            .init(name: "start", value: String(offset)), .init(name: "count", value: "100"),
            .init(name: "os", value: "mac"), .init(name: "category1", value: "998"),
            .init(name: "infinite", value: "1"), .init(name: "l", value: "english")
        ]
        if let query { components.queryItems?.append(.init(name: "term", value: query)) }
        if let developer { components.queryItems?.append(.init(name: "developer", value: developer)) }
        guard let url = components.url else { throw AppleGamingWikiDiscoveryError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = root["results_html"] as? String,
              let total = root["total_count"] as? Int else { throw AppleGamingWikiDiscoveryError.invalidResponse }
        let rows = Self.steamResultRows(in: html)
        let games = Self.parseSteamGames(rows)
        guard !rows.isEmpty || offset >= total else { throw AppleGamingWikiDiscoveryError.emptyCatalog }
        return SteamPage(games: games, offset: min(total, offset + rows.count), total: total)
    }

    static func parseSteamGames(_ html: String) -> [AppleGamingWikiGame] {
        parseSteamGames(steamResultRows(in: html))
    }

    private static func steamResultRows(in html: String) -> [String] {
        matches(#"(<a\s[^>]*class="search_result_row.*?</a>)"#, in: html)
    }

    nonisolated private static let steamTags: [String: String] = Bundle.main.url(forResource: "DiscoveryTags", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]

    private static func parseSteamGames(_ rows: [String]) -> [AppleGamingWikiGame] {
        return rows.compactMap { row in
            guard let id = firstMatch(#"data-ds-appid="(\d+)""#, in: row),
                  let title = firstMatch(#"<span class="title">(.*?)</span>"#, in: row),
                  row.contains("platform_img mac") else { return nil }
            let tagIDs = firstMatch(#"data-ds-tagids="\[([^\]]*)\]""#, in: row)?.split(separator: ",").map(String.init) ?? []
            return AppleGamingWikiGame(
                title: decodeHTML(title), pageURL: "https://store.steampowered.com/app/\(id)/",
                native: .unknown, rosetta2: .unknown, crossover: .unknown, wine: .unknown,
                parallels: .unknown, linuxARM: .unknown, steamAppID: id,
                coverURL: firstMatch(#"<img src="([^"]+)""#, in: row),
                genres: tagIDs.compactMap { steamTags[$0] }, macOSStoreSupport: true
            )
        }
    }

    static func merge(_ existing: [AppleGamingWikiGame], _ incoming: [AppleGamingWikiGame]) -> [AppleGamingWikiGame] {
        var result = existing
        var pageIndices = Dictionary(result.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var steamIndices = Dictionary(
            result.enumerated().compactMap { item in item.element.steamAppID.map { ($0, item.offset) } },
            uniquingKeysWith: { first, _ in first }
        )
        var titleIndices = Dictionary(grouping: result.indices, by: { normalizedTitle(result[$0].title) })
        for game in incoming {
            let titleKey = normalizedTitle(game.title)
            let titleMatches = titleIndices[titleKey] ?? []
            let index = pageIndices[game.id] ?? game.steamAppID.flatMap { steamIndices[$0] }
                ?? (titleMatches.count == 1 && result[titleMatches[0]].steamAppID == nil ? titleMatches[0] : nil)
            if let index {
                result[index].steamAppID = game.steamAppID ?? result[index].steamAppID
                result[index].coverURL = game.coverURL ?? result[index].coverURL
                if let genres = game.genres, !genres.isEmpty { result[index].genres = genres }
                result[index].macOSStoreSupport = game.macOSStoreSupport ?? result[index].macOSStoreSupport
                if let steamAppID = result[index].steamAppID { steamIndices[steamAppID] = index }
            } else {
                pageIndices[game.id] = result.count
                if let steamAppID = game.steamAppID { steamIndices[steamAppID] = result.count }
                titleIndices[titleKey, default: []].append(result.count)
                result.append(game)
            }
        }
        return result
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    func searchMacGames(named query: String) async throws -> [AppleGamingWikiGame] {
        try await fetchSteamPage(offset: 0, query: query).games
    }

    func searchMacGames(developer: String) async throws -> [AppleGamingWikiGame] {
        try await fetchSteamPage(offset: 0, developer: developer).games
    }

    func loadMoreSteam(in catalog: AppleGamingWikiCatalog) async throws -> AppleGamingWikiCatalog {
        let currentOffset = catalog.steamOffset ?? 0
        if let total = catalog.steamTotal, currentOffset >= total { return catalog }
        let page = try await fetchSteamPage(offset: currentOffset)
        guard page.offset > currentOffset else { throw AppleGamingWikiDiscoveryError.emptyCatalog }
        var result = catalog
        result.games = Self.merge(catalog.games, page.games)
        result.steamOffset = page.offset
        result.steamTotal = page.total
        writeCache(result)
        return result
    }

    private func steamMetadata(for game: AppleGamingWikiGame) async -> DiscoveryGameMetadata? {
        var appID = game.steamAppID
        if appID == nil {
            var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
            components.queryItems = [.init(name: "term", value: game.title), .init(name: "l", value: "english"), .init(name: "cc", value: "US")]
            guard let url = components.url,
                  let data = await requestData(url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = root["items"] as? [[String: Any]] else { return nil }
            // Only exact normalized titles may attach a store identity to a wiki entry.
            let normalize: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).filter { $0.isLetter || $0.isNumber } }
            let candidates = items.filter { ($0["name"] as? String).map(normalize) == normalize(game.title) }
            guard candidates.count == 1, let id = candidates[0]["id"] as? Int else { return nil }
            appID = String(id)
        }
        guard let appID,
              let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=english"),
              let data = await requestData(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelope = root[appID] as? [String: Any], envelope["success"] as? Bool == true,
              let details = envelope["data"] as? [String: Any] else { return nil }
        return DiscoveryGameMetadata(
            summary: (details["short_description"] as? String).map(Self.decodeHTML),
            coverImageURL: details["header_image"] as? String,
            originalImageURL: details["header_image"] as? String,
            sourceURL: game.pageURL, fetchedAt: .now, steamAppID: appID,
            developer: (details["developers"] as? [String])?.joined(separator: ", "),
            genres: (details["genres"] as? [[String: Any]])?.compactMap { $0["description"] as? String }
        )
    }

    private func requestData(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
