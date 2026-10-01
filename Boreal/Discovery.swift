import Foundation
import SwiftUI
import AppKit
import ImageIO
import CryptoKit

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

// MARK: - Discovery view

// The immutable filter snapshot can be evaluated without blocking SwiftUI layout.
nonisolated private struct DiscoveryFilters: Hashable, Sendable {
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
            result.recommended = Array(recommendedOrder.lazy.map(\.game)
                .filter { compatibilityRatings(for: $0).contains(.perfect) }.prefix(4))
        }
        if sortOrder == "Recommended" {
            result.games = recommendedOrder.map(\.game)
        } else {
            result.games = entries.map(\.game).sorted {
                let comparison = $0.title.localizedStandardCompare($1.title)
                return comparison == .orderedSame ? $0.id < $1.id
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
            && (rating == "All ratings" || (rating == AppleGamingWikiRating.unknown.rawValue
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
        let perfectPathScore = ratings
            .enumerated()
            .first(where: { $0.element == .perfect })
            .map { 100 - ($0.offset * 5) } ?? 0
        // Artwork is presentation quality, not compatibility evidence.
        return perfectPathScore - (ratings.min(by: { $0.rank < $1.rank })?.rank ?? AppleGamingWikiRating.unknown.rank)
    }

}

nonisolated private struct DiscoveryProjection: Sendable {
    var filters: DiscoveryFilters?
    var games: [AppleGamingWikiGame] = []
    var recommended: [AppleGamingWikiGame] = []
    var genres: [String] = []
    var trackedCount = 0
    var unknownCount = 0
    var macSupportCount = 0
}

nonisolated private struct DiscoveryProjectionRequest: Hashable, Sendable {
    var revision: Int
    var filters: DiscoveryFilters
}

struct DiscoveryView: View {
    @Environment(BorealStore.self) private var store
    @Binding var searchText: String
    let selectGame: (AppleGamingWikiGame) -> Void
    @State private var scope: DiscoveryScope = .all
    @State private var windowsMethod: AppleGamingWikiPlatform = .all
    @State private var genre = "All genres"
    @State private var rating = "All ratings"
    @State private var storefront = "All stores"
    @State private var sortOrder = "Recommended"
    @State private var hasCompatibilityReportOnly = false
    @AppStorage("discoveryListLayout") private var listLayout = false
    @State private var showGuide = false
    @State private var projection = DiscoveryProjection()
    @State private var page = 0
    @State private var pageInput = "1"
    private let pageSize = 60
    private let macProfile = DiscoveryMacProfile.current

    private var projectionRequest: DiscoveryProjectionRequest {
        DiscoveryProjectionRequest(revision: store.discoveryCatalogRevision, filters: DiscoveryFilters(
            scope: scope, windowsMethod: windowsMethod, genre: genre, rating: rating,
            storefront: storefront, sortOrder: sortOrder,
            hasCompatibilityReportOnly: hasCompatibilityReportOnly, query: query
        ))
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(1, min(1600, geometry.size.width - 40))
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                        header
                        if let catalog = store.discoveryCatalog {
                            catalogSummary(catalog)
                            Section {
                                if !query.isEmpty, let message = store.discoverySearchMessage {
                                    Label(message, systemImage: "magnifyingglass")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                if let notice = catalog.sourceNotice {
                                    Label(LocalizedStringKey(notice), systemImage: "info.circle")
                                        .font(.callout).foregroundStyle(.secondary)
                                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                }
                                if case .failed(let message) = store.discoveryState {
                                    Label(message, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
                                }
                                if query.isEmpty && scope == .recommended && projection.filters == projectionRequest.filters && !projection.recommended.isEmpty {
                                    recommended(projection.recommended, width: contentWidth)
                                }
                                catalogContent(catalog, width: contentWidth)
                            } header: {
                                filters(catalog, width: contentWidth)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08)))
                                    .id("discovery-results")
                            }
                        } else {
                            ContentUnavailableView {
                                Label(.Navigation.discoveryTitle, systemImage: "gamecontroller")
                            } description: {
                                if case .failed(let message) = store.discoveryState { Text(message) }
                                else { ProgressView("Loading catalog…") }
                            } actions: {
                                Button("Retry") { store.refreshDiscoveryCatalog() }.disabled(store.discoveryState == .loading)
                            }
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .onChange(of: projectionRequest.filters) { _, _ in
                    page = 0
                    scrollProxy.scrollTo("discovery-results", anchor: .top)
                }
                .onChange(of: page) { _, value in
                    pageInput = String(value + 1)
                    scrollProxy.scrollTo("discovery-results", anchor: .top)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { if store.discoveryCatalog == nil { store.loadDiscoveryCatalog() } }
        .task(id: projectionRequest) {
            guard let catalog = store.discoveryCatalog else { return }
            let request = projectionRequest
            if request.filters.query != projection.filters?.query && !request.filters.query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            }
            let work = Task.detached(priority: .userInitiated) { request.filters.project(catalog) }
            let prepared = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            guard !Task.isCancelled, request == projectionRequest else { return }
            projection = prepared
            page = min(page, max(0, (prepared.games.count - 1) / pageSize))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.discoveryState == .loading {
                    ProgressView("Loading catalog…").controlSize(.small)
                } else {
                    Button("Refresh Discovery", systemImage: "arrow.clockwise") { store.refreshDiscoveryCatalog() }
                }
            }
        }
        .sheet(isPresented: $showGuide) {
            VStack { guide; Button("Done") { showGuide = false }.keyboardShortcut(.cancelAction) }.padding(28).frame(width: 410)
        }
        .onChange(of: scope) { _, value in
            if value == .recommended { sortOrder = "Recommended" }
        }
        .task(id: query) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                store.clearDiscoverySearch()
                return
            }
            store.prepareDiscoverySearch(query)
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await store.searchDiscoveryGames(query)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(.Navigation.discoveryTitle)
                        .font(.title2.weight(.bold))
                    Text("Find games and check the best available way to play them on your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Data sources", systemImage: "info.circle") { showGuide = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("View Discovery data sources")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    macProfileLabel
                    Spacer(minLength: 8)
                    Text("Community catalog").font(.caption).foregroundStyle(.tertiary)
                }
                macProfileLabel
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [.accentColor.opacity(0.13), .accentColor.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.08)))
    }

    private var macProfileLabel: some View {
        Label(macProfile.summary, systemImage: "laptopcomputer")
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.08)))
    }

    private func catalogSummary(_ catalog: AppleGamingWikiCatalog) -> some View {
        let unknownCount = projection.unknownCount
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
            summaryStat(
                value: projection.trackedCount.formatted(),
                label: "games",
                symbol: "gamecontroller.fill"
            )
            summaryStat(
                value: projection.macSupportCount.formatted(),
                label: "Mac paths",
                symbol: "apple.logo"
            )
            if projection.trackedCount - unknownCount > 0 {
                summaryStat(
                    value: (projection.trackedCount - unknownCount).formatted(),
                    label: "games with reports",
                    symbol: "checkmark.seal"
                )
            }
            if unknownCount > 0 {
                summaryStat(value: unknownCount.formatted(), label: "without compatibility report", symbol: "questionmark.circle")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(projection.trackedCount) \(String(localized: "games")), "
                + "\(projection.macSupportCount) \(String(localized: "Mac paths")), "
                + "\(unknownCount) \(String(localized: "without compatibility report"))"
        )
    }

    private func summaryStat(value: String, label: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.callout.weight(.semibold))
                Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.05)))
    }

    private func filters(_ catalog: AppleGamingWikiCatalog, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Browse", selection: $scope) {
                ForEach(DiscoveryScope.allCases, id: \.self) { value in
                    Label(value.title, systemImage: value.symbol).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            if width >= 960 {
                HStack(spacing: 8) {
                    filterMenus(catalog)
                    Spacer(minLength: 8)
                    sortMenu
                    layoutPicker
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    filterMenus(catalog)
                    HStack {
                        Spacer(minLength: 0)
                        sortMenu
                        layoutPicker
                    }
                }
            }

            if hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if genre != "All genres" {
                            activeFilterChip(genre, reset: { genre = "All genres" })
                        }
                        if rating != "All ratings" {
                            activeFilterChip(
                                AppleGamingWikiRating(rawValue: rating)?.displayName ?? rating,
                                reset: { rating = "All ratings" }
                            )
                        }
                        if storefront != "All stores" {
                            activeFilterChip(storefront, reset: { storefront = "All stores" })
                        }
                        if scope == .windows, windowsMethod != .all {
                            activeFilterChip(windowsMethod.title, reset: { windowsMethod = .all })
                        }
                        if hasCompatibilityReportOnly {
                            activeFilterChip("Has compatibility report", reset: { hasCompatibilityReportOnly = false })
                        }
                        Button("Reset filters", systemImage: "xmark") { resetFilters() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Clear active filters")
                    }
                }
            }
        }
    }

    private func filterMenus(_ catalog: AppleGamingWikiCatalog) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                genreMenu(catalog)
                compatibilityMenu
                storefrontMenu
                if scope == .windows { windowsMethodMenu }
                filtersMenu
            }
        }
    }

    private var hasActiveFilters: Bool {
        genre != "All genres"
            || rating != "All ratings"
            || storefront != "All stores"
            || (scope == .windows && windowsMethod != .all)
            || hasCompatibilityReportOnly
    }

    private func activeFilterChip(_ title: String, reset: @escaping () -> Void) -> some View {
        Button {
            reset()
        } label: {
            HStack(spacing: 5) {
                Text(LocalizedStringKey(title))
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Remove active filter")
    }

    private func genreMenu(_ catalog: AppleGamingWikiCatalog) -> some View {
        let genres = projection.genres
        return Menu {
            filterOption("All genres", selected: genre == "All genres") { genre = "All genres" }
            ForEach(genres, id: \.self) { value in
                filterOption(value, selected: genre == value) { genre = value }
            }
            filterOption("Not provided", selected: genre == "Not provided") { genre = "Not provided" }
        } label: {
            Label(genre == "All genres" ? String(localized: "Genre") : genre, systemImage: "tag")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var compatibilityMenu: some View {
        Menu {
            filterOption("All ratings", selected: rating == "All ratings") { rating = "All ratings" }
            ForEach(AppleGamingWikiRating.allCases.filter { $0 != .notApplicable }, id: \.self) { value in
                filterOption(value.displayName, selected: rating == value.rawValue) { rating = value.rawValue }
            }
        } label: {
            Label(rating == "All ratings" ? String(localized: "Compatibility") : (AppleGamingWikiRating(rawValue: rating)?.displayName ?? rating), systemImage: "checkmark.seal")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var storefrontMenu: some View {
        Menu {
            filterOption("All stores", selected: storefront == "All stores") { storefront = "All stores" }
            filterOption("Steam", selected: storefront == "Steam") { storefront = "Steam" }
            filterOption("Other / unknown", selected: storefront == "Other / unknown") { storefront = "Other / unknown" }
        } label: {
            Label(storefront == "All stores" ? String(localized: "Store") : storefront, systemImage: "bag")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var windowsMethodMenu: some View {
        Menu {
            filterOption("All Windows paths", selected: windowsMethod == .all) { windowsMethod = .all }
            ForEach([AppleGamingWikiPlatform.crossover, .wine, .parallels], id: \.self) { value in
                filterOption(value.title, selected: windowsMethod == value) { windowsMethod = value }
            }
        } label: {
            Label(windowsMethod == .all ? String(localized: "Windows path") : windowsMethod.title, systemImage: "wineglass")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var filtersMenu: some View {
        Menu {
            Toggle("Has compatibility report", isOn: $hasCompatibilityReportOnly)
                .help("Only entries with community compatibility reports. These are not tests performed by Boreal.")
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(["Recommended", "Name A–Z", "Name Z–A"], id: \.self) { value in
                filterOption(value, selected: sortOrder == value) {
                    sortOrder = value
                }
            }
        } label: {
            Label(sortLabel, systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var sortLabel: String {
        switch sortOrder {
        case "Recommended": String(localized: "Sort: Recommended")
        case "Name A–Z": String(localized: "Sort: Name A–Z")
        case "Name Z–A": String(localized: "Sort: Name Z–A")
        default: String(localized: "Sort: Recommended")
        }
    }

    private var layoutPicker: some View {
        Picker("View", selection: $listLayout) {
            Image(systemName: "square.grid.2x2").tag(false)
            Image(systemName: "list.bullet").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 76)
        .help("Choose grid or list view")
        .accessibilityLabel("View layout")
    }

    private func filterOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
                Text(LocalizedStringKey(title))
            }
        }
    }

    private func recommended(_ games: [AppleGamingWikiGame], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Best compatibility").font(.title3.bold())
                    Text("Strongest available community compatibility reports.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(min(4, games.count)) \(String(localized: "results"))").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(games.prefix(4))) { game in
                        DiscoveryGameTile(game: game, scope: scope, windowsMethod: windowsMethod) { selectGame(game) }.frame(width: min(280, width))
                    }
                }
            }
        }
    }

    private func catalogContent(_ catalog: AppleGamingWikiCatalog, width: CGFloat) -> some View {
        let games = projection.games
        let start = min(page * pageSize, games.count)
        let end = min(start + pageSize, games.count)
        let visibleGames = Array(games[start..<end])
        let columnCount = max(1, Int((width + 16) / 256))
        let cardWidth = max(1, (width - CGFloat(columnCount - 1) * 16) / CGFloat(columnCount))
        let columns = Array(repeating: GridItem(.fixed(cardWidth), spacing: 16), count: columnCount)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(scope.title).font(.title3.bold())
                Text("\(games.count.formatted()) \(String(localized: "results"))").foregroundStyle(.secondary)
                Spacer()
            }
            if games.count > pageSize && projection.filters == projectionRequest.filters {
                pageControls(resultCount: games.count)
            }
            if projection.filters != projectionRequest.filters || games.isEmpty && (!query.isEmpty && store.discoverySearchState == .loading || store.discoveryState == .loading) {
                ProgressView("Searching…").frame(maxWidth: .infinity).padding(32)
            } else if games.isEmpty {
                ContentUnavailableView("No games found", systemImage: "magnifyingglass", description: Text("Try another search or reset your filters."))
                if hasActiveFilters || !query.isEmpty {
                    Button("Reset filters") { resetFilters() }
                }
            } else if listLayout {
                LazyVStack(spacing: 8) {
                    ForEach(visibleGames) { game in
                        DiscoveryGameTile(game: game, horizontal: width >= 480, scope: scope, windowsMethod: windowsMethod, artworkWidth: 176) { selectGame(game) }
                    }
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(visibleGames) { game in
                        DiscoveryGameTile(game: game, scope: scope, windowsMethod: windowsMethod) { selectGame(game) }
                            .frame(width: cardWidth)
                    }
                }
            }
            if !games.isEmpty && projection.filters == projectionRequest.filters {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Text("Showing \(start + 1)–\(end) of \(games.count.formatted()) results")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        pageControls(resultCount: games.count)
                    }
                    VStack(spacing: 12) {
                        Text("Showing \(start + 1)–\(end) of \(games.count.formatted()) results")
                            .font(.caption).foregroundStyle(.secondary)
                        pageControls(resultCount: games.count)
                    }
                }
                .padding(.vertical, 12)
            }
            loadMoreTrigger(catalog)
            Text(catalog.isStale ? "Showing the last saved catalog." : "Updated \(catalog.fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func pageControls(resultCount: Int) -> some View {
        HStack(spacing: 12) {
            Button("Previous", systemImage: "chevron.left") { page = max(0, page - 1) }
                .disabled(page == 0)
            TextField("Page", text: $pageInput)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .accessibilityLabel("Page")
                .help("Enter a page number and press Return")
                .onSubmit {
                    if let requested = Int(pageInput) {
                        page = min(max(1, requested), max(1, (resultCount + pageSize - 1) / pageSize)) - 1
                    }
                    pageInput = String(page + 1)
                }
            Text("/ \(max(1, (resultCount + pageSize - 1) / pageSize))")
                .font(.callout.monospacedDigit())
            Button("Next", systemImage: "chevron.right") { page = min(page + 1, max(0, (resultCount - 1) / pageSize)) }
                .disabled((page + 1) * pageSize >= resultCount)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func loadMoreTrigger(_ catalog: AppleGamingWikiCatalog) -> some View {
        if query.isEmpty, (catalog.steamOffset ?? 0) < (catalog.steamTotal ?? 0) {
            if store.discoveryPaginationState == .loading {
                ProgressView("Loading more games…")
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if case .failed(let message) = store.discoveryPaginationState {
                VStack(spacing: 10) {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Retry", systemImage: "arrow.clockwise") { store.loadMoreDiscoveryGames() }
                }
                .frame(maxWidth: .infinity).padding(16)
            } else {
                Button("Load more games", systemImage: "arrow.down") { store.loadMoreDiscoveryGames() }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                if let game = store.discoveryCatalog?.games.first(where: { $0.coverURL != nil }) {
                    DiscoveryArtwork(imageURL: game.coverURL, title: game.title, isLoading: false, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text("Find the best way to play").font(.title2.bold())
            Text("Discover games, compare compatibility reports and choose a setup for your Mac.").foregroundStyle(.secondary)
        }.padding(16).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            Text("Data sources").font(.headline)
            Label("Compatibility reports: AppleGamingWiki. Store metadata and artwork: Steam. Price data: IsThereAnyDeal when configured.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
            if let notice = store.discoveryCatalog?.sourceNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            guideRow("Compatibility ratings", "Community reports for Native, Rosetta 2, CrossOver, Wine and Parallels.", "checkmark.seal")
            guideRow("Store links", "Open the game's verified store page or search another storefront.", "link")
            guideRow("Performance insights", "Read hardware and configuration reports on the source page.", "chart.bar")
            guideRow("Save for later", "Save games you’re interested in Discovery. Adding to your library is a separate action.", "bookmark")
            Text("A macOS listing does not confirm Apple Silicon or current macOS compatibility. ‘Playable’ requires a Perfect or Playable community rating; reaching a menu is insufficient.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Open compatibility documentation ↗", destination: AppleGamingWikiDiscoveryService.masterListURL)
        }
    }

    private func guideRow(_ title: String, _ description: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).frame(width: 44, height: 44).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(description).font(.callout).foregroundStyle(.secondary) }
        }
    }

    private func resetFilters() {
        genre = "All genres"
        rating = "All ratings"
        storefront = "All stores"
        windowsMethod = .all
        hasCompatibilityReportOnly = false
        sortOrder = "Recommended"
        scope = .all
        searchText = ""
    }

}

private struct DiscoveryMacProfile: Sendable {
    let chip: String
    let memory: String
    let os: String

    var summary: String { "\(chip) · \(memory) · \(os)" }

    static let current: Self = {
        let processor = hardwareString("machdep.cpu.brand_string") ?? hardwareString("hw.model") ?? "This Mac"
        let chip: String
        if processor.hasPrefix("Apple ") {
            chip = processor
        } else if processor.localizedCaseInsensitiveContains("Intel") {
            chip = "Intel Mac"
        } else {
            chip = processor == "This Mac" ? processor : "Mac"
        }
        let memoryGB = max(1, Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()))
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(version.majorVersion).\(version.minorVersion)"
        return Self(chip: chip, memory: "\(memoryGB) GB", os: os)
    }()

    private static func hardwareString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}

struct DiscoveryGameTile: View {
    @Environment(BorealStore.self) private var store
    @AppStorage(ITADPriceService.apiKeyDefaultsKey) private var itadAPIKey = ""
    @AppStorage(ITADPriceService.countryCodeDefaultsKey) private var itadCountryCode = "PL"
    let game: AppleGamingWikiGame
    var horizontal = false
    var scope: DiscoveryScope = .all
    var windowsMethod: AppleGamingWikiPlatform = .all
    var artworkWidth: CGFloat = 105
    let open: () -> Void
    @State private var isHovered = false
    private var metadata: DiscoveryGameMetadata? { store.discoveryMetadata(for: game) }

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .top, spacing: 12) {
                    artwork.frame(width: artworkWidth)
                    details.layoutPriority(1)
                    Spacer(minLength: 0)
                }
                    .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 0) { artwork; details.padding(14) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(isHovered ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(isHovered ? 0.16 : 0.08)))
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .shadow(color: .black.opacity(isHovered ? 0.18 : 0), radius: 12, y: 3)
        .onHover { isHovered = $0 }
        .task(id: "\(game.id)-\(itadAPIKey)-\(itadCountryCode)") {
            // Catalog rows already carry artwork, tags and store identity for Steam games.
            // Fetch full descriptions on the detail screen instead of for every card.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            if game.steamAppID == nil || game.genres?.isEmpty != false {
                await store.ensureDiscoveryMetadata(for: game)
            }
            guard !Task.isCancelled else { return }
            if !itadAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await store.ensureDiscoveryPrice(for: game)
            }
        }
    }

    private var artwork: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                DiscoveryArtwork(
                    imageURL: (game.steamAppID ?? metadata?.steamAppID).map {
                        "https://cdn.cloudflare.steamstatic.com/steam/apps/\($0)/header.jpg"
                    } ?? metadata?.coverImageURL ?? game.coverURL,
                    fallbackImageURL: metadata?.coverImageURL ?? game.coverURL,
                    title: game.title,
                    isLoading: store.isDiscoveryMetadataLoading(for: game),
                    height: horizontal ? 106 : 152
                )
            }
            .buttonStyle(.plain)

            Button {
                store.toggleDiscoveryGame(game)
            } label: {
                Image(systemName: store.isDiscoveryGameSaved(game) ? "bookmark.fill" : "bookmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.52), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .padding(9)
            .help(store.isDiscoveryGameSaved(game) ? "Remove from saved games" : "Save to Discovery")
            .accessibilityLabel(store.isDiscoveryGameSaved(game) ? "Saved" : "Save")
            .accessibilityAddTraits(store.isDiscoveryGameSaved(game) ? .isSelected : [])
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: horizontal ? 7 : 9) {
            Button(action: open) {
                Text(game.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text(genreDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { platformBadge; compatibilityBadge }
                VStack(alignment: .leading, spacing: 6) { platformBadge; compatibilityBadge }
            }

            discoveryPrice
            HStack(spacing: 8) {
                storeReference
                Spacer(minLength: 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: horizontal ? 118 : 168, alignment: .topLeading)
    }

    private var genreDescription: String {
        let genres = game.genres?.isEmpty == false ? game.genres : metadata?.genres
        guard let genres, !genres.isEmpty else { return String(localized: "Genre not provided") }
        return genres.prefix(2).joined(separator: " · ")
    }

    @ViewBuilder private var compatibilityBadge: some View {
        if let rating = reportedRatings.min(by: { $0.rating.rank < $1.rating.rank })?.rating {
            DiscoveryRatingLabel(title: "Compatibility", rating: rating)
        } else {
            Label("No compatibility data", systemImage: "questionmark.circle")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var reportedRatings: [AppleGamingWikiRatingEntry] {
        game.availableRatings.filter { entry in
            switch scope {
            case .mac: ["Native", "Rosetta 2"].contains(entry.title)
            case .windows:
                windowsMethod == .all
                    ? ["CrossOver", "Wine", "Parallels"].contains(entry.title)
                    : entry.title.lowercased() == windowsMethod.rawValue
            case .all, .recommended: true
            }
        }
    }

    private var bestMethod: String {
        reportedRatings.filter { $0.rating.isPlayable }
            .min(by: { $0.rating.rank < $1.rating.rank })?.title ?? "Unverified"
    }

    private var platformBadge: some View {
        Label(platformTitle, systemImage: platformSymbol)
            .font(horizontal ? .caption2.weight(.semibold) : .caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private var platformTitle: String {
        if scope == .windows {
            return isWindowsPath ? "\(String(localized: "Windows")) · \(localizedBestMethod)" : String(localized: "Windows")
        }
        if isWindowsPath { return "\(String(localized: "Windows")) · \(localizedBestMethod)" }
        if bestMethod == "Native" { return String(localized: "Native macOS") }
        if bestMethod == "Rosetta 2" { return String(localized: .Compatibility.rosetta2Title) }
        if let macSupportKind = game.macSupportKind {
            if macSupportKind == .macOS, isWindowsPath {
                return "\(macSupportKind.title) · \(localizedBestMethod)"
            }
            return macSupportKind.title
        }
        return isWindowsPath ? "\(String(localized: "Windows")) · \(localizedBestMethod)" : String(localized: "Windows")
    }

    private var isWindowsPath: Bool {
        ["CrossOver", "Wine", "Parallels"].contains(bestMethod)
    }

    private var localizedBestMethod: String {
        switch bestMethod {
        case "CrossOver": String(localized: .Compatibility.crossOverTitle)
        case "Wine": String(localized: .Compatibility.wineTitle)
        case "Parallels": String(localized: .Compatibility.parallelsTitle)
        case "Rosetta 2": String(localized: .Compatibility.rosetta2Title)
        case "Native": String(localized: .Compatibility.nativeTitle)
        default: bestMethod
        }
    }

    private var platformSymbol: String {
        if bestMethod == "Native" { return "apple.logo" }
        if bestMethod == "Rosetta 2" { return "cpu" }
        if !isWindowsPath, scope != .windows, let macSupportKind = game.macSupportKind { return macSupportKind.symbol }
        switch bestMethod {
        case "CrossOver": return "rectangle.2.swap"
        case "Parallels": return "rectangle.split.3x1"
        case "Wine": return "wineglass"
        case "Rosetta 2": return "cpu"
        default: return "rectangle.on.rectangle"
        }
    }

    @ViewBuilder private var discoveryPrice: some View {
        if let offer = store.discoveryPriceSummary(for: game)?.bestOffer {
            HStack(spacing: 6) {
                Spacer(minLength: 4)
                Text(offer.price.formatted)
                    .font(horizontal ? .headline.weight(.semibold) : .callout.weight(.semibold))
                    .foregroundStyle(.primary)
                if let discount = offer.discountLabel {
                    Text(discount)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
        } else if store.isDiscoveryPriceLoading(for: game) {
            Label("Loading price…", systemImage: "arrow.triangle.2.circlepath")
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Price unavailable")
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
                .help(itadAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add an IsThereAnyDeal API key in Settings to load prices." : "No current offer was found.")
        }
    }

    @ViewBuilder private var storeReference: some View {
        let storeName = store.discoveryPriceSummary(for: game)?.bestOffer?.shop.name
        let steamID = game.steamAppID ?? metadata?.steamAppID
        if let storeName, storeName.caseInsensitiveCompare("Steam") == .orderedSame,
           let steamID,
           let url = URL(string: "https://store.steampowered.com/app/\(steamID)/") {
            Link(destination: url) {
                Label(storeName, systemImage: "bag")
                    .font(horizontal ? .caption : .caption2)
            }
            .help("Open Steam store page")
        } else if let storeName {
            Text(storeName)
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let steamID,
                  let url = URL(string: "https://store.steampowered.com/app/\(steamID)/") {
            Link(destination: url) {
                Label("Steam", systemImage: "bag")
                    .font(horizontal ? .caption : .caption2)
            }
            .help("Open Steam store page")
        } else {
            Text("Store unavailable")
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct SavedDiscoveryGamesView: View {
    @Environment(BorealStore.self) private var store
    var searchText: String
    @State private var selectedGame: AppleGamingWikiGame?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved from Discovery").font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(store.savedDiscoveryGames.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }) { game in
                        DiscoveryGameTile(game: game, horizontal: true) { selectedGame = game }.frame(width: 320)
                    }
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 12)
            .sheet(item: $selectedGame) { DiscoveryGameDetailView(game: $0) }
    }
}

private struct DiscoveryArtwork: View {
    let imageURL: String?
    var fallbackImageURL: String? = nil
    let title: String
    let isLoading: Bool
    let height: CGFloat
    @State private var loadedImage: NSImage?
    @State private var attemptedLoad = false

    var body: some View {
        // Layout uses the card's proposed width, never the bitmap's intrinsic size.
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [.indigo.opacity(0.78), .cyan.opacity(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if let loadedImage {
                    Image(nsImage: loadedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: height)
                        .clipped()
                } else if imageURL != nil && !attemptedLoad {
                    placeholder.overlay { ProgressView().tint(.white) }
                } else if isLoading {
                    placeholder.overlay { ProgressView().tint(.white) }
                } else {
                    placeholder
                }
            }
            .frame(width: geometry.size.width, height: height)
            .clipped()
        }
        .frame(height: height)
        .accessibilityLabel("Cover for \(title)")
        .task(id: "\(imageURL ?? "")|\(fallbackImageURL ?? "")") {
            loadedImage = nil
            attemptedLoad = false
            for candidate in [imageURL, fallbackImageURL].compactMap({ $0 }).uniqued() {
                guard let url = URL(string: candidate) else { continue }
                if let image = await DiscoveryImagePipeline.shared.image(for: url, maxPixelSize: 560) {
                    guard !Task.isCancelled else { return }
                    loadedImage = image
                    attemptedLoad = true
                    return
                }
            }
            attemptedLoad = true
        }
    }

    private var placeholder: some View {
        VStack(spacing: 9) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 34, weight: .medium))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .foregroundStyle(.white.opacity(0.88))
    }
}

private actor DiscoveryArtworkGate {
    private var active = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if active < 6 { active += 1; return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    func release() {
        if waiters.isEmpty { active = max(0, active - 1) }
        else { waiters.removeFirst().continuation.resume(returning: true) }
    }
}

private actor DiscoveryImagePipeline {
    static let shared = DiscoveryImagePipeline()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 96 * 1_024 * 1_024
        cache.evictsObjectsWithDiscardedContent = true
        return cache
    }()
    private let diskCacheDirectory: URL?
    private static let diskCacheLimitBytes: UInt64 = 512 * 1_024 * 1_024
    private static let diskCacheTrimTargetBytes: UInt64 = 384 * 1_024 * 1_024
    private var diskWriteCount = 0
    private struct ImageLoad {
        let id: UUID
        let task: Task<NSImage?, Never>
        var consumers: Set<UUID>
    }
    private var inFlight: [URL: ImageLoad] = [:]
    private var failedLoads: [URL: Date] = [:]
    private let downloadGate = DiscoveryArtworkGate()

    init() {
        diskCacheDirectory = ApplicationDataLocation.logicalRoot.appending(
            path: "Discovery/Artwork",
            directoryHint: .isDirectory
        )
    }

    func image(for url: URL, maxPixelSize: Int) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let cached = readDiskImage(for: url, maxPixelSize: maxPixelSize) {
            cache.setObject(cached, forKey: url as NSURL, cost: Self.imageCost(cached))
            return cached
        }
        guard !Task.isCancelled else { return nil }
        if let load = inFlight[url] { return await consume(load, for: url, maxPixelSize: maxPixelSize) }
        if let failedAt = failedLoads[url], Date.now.timeIntervalSince(failedAt) < 120 { return nil }

        let gate = downloadGate
        let task = Task.detached(priority: .utility) { () -> NSImage? in
            guard await gate.acquire() else { return nil }
            guard !Task.isCancelled else { await gate.release(); return nil }
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let image: NSImage?
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled {
                image = Self.downsampledImage(from: data, maxPixelSize: maxPixelSize)
            } else {
                image = nil
            }
            await gate.release()
            return image
        }
        let load = ImageLoad(id: UUID(), task: task, consumers: [])
        inFlight[url] = load
        return await consume(load, for: url, maxPixelSize: maxPixelSize)
    }

    private func consume(_ load: ImageLoad, for url: URL, maxPixelSize: Int) async -> NSImage? {
        let consumer = UUID()
        inFlight[url]?.consumers.insert(consumer)
        let image = await withTaskCancellationHandler {
            await load.task.value
        } onCancel: {
            Task { await self.removeConsumer(consumer, loadID: load.id, for: url) }
        }
        removeConsumer(consumer, loadID: load.id, for: url)
        guard !Task.isCancelled else { return nil }
        if let image {
            failedLoads.removeValue(forKey: url)
            if cache.object(forKey: url as NSURL) == nil {
                cache.setObject(image, forKey: url as NSURL, cost: Self.imageCost(image))
                writeDiskImage(image, for: url, maxPixelSize: maxPixelSize)
            }
        } else {
            failedLoads = failedLoads.filter { Date.now.timeIntervalSince($0.value) < 120 }
            if failedLoads.count >= 256, let oldest = failedLoads.min(by: { $0.value < $1.value })?.key {
                failedLoads.removeValue(forKey: oldest)
            }
            failedLoads[url] = .now
        }
        return image
    }

    private func removeConsumer(_ consumer: UUID, loadID: UUID, for url: URL) {
        guard var load = inFlight[url], load.id == loadID else { return }
        load.consumers.remove(consumer)
        if load.consumers.isEmpty {
            load.task.cancel()
            inFlight[url] = nil
        } else {
            inFlight[url] = load
        }
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: .zero)
    }

    private static func imageCost(_ image: NSImage) -> Int {
        let representation = image.representations.first
        let width = representation?.pixelsWide ?? Int(image.size.width)
        let height = representation?.pixelsHigh ?? Int(image.size.height)
        return max(1, width * height * 4)
    }

    private func diskURL(for url: URL, maxPixelSize: Int) -> URL? {
        guard let diskCacheDirectory else { return nil }
        let key = "\(url.absoluteString)|\(maxPixelSize)"
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return diskCacheDirectory.appending(path: "\(digest).png", directoryHint: .notDirectory)
    }

    private func readDiskImage(for url: URL, maxPixelSize: Int) -> NSImage? {
        guard let diskURL = diskURL(for: url, maxPixelSize: maxPixelSize),
              let data = try? Data(contentsOf: diskURL),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private func writeDiskImage(_ image: NSImage, for url: URL, maxPixelSize: Int) {
        guard let diskURL = diskURL(for: url, maxPixelSize: maxPixelSize),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            try FileManager.default.createDirectory(
                at: diskURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: diskURL, options: .atomic)
            diskWriteCount += 1
            if diskWriteCount.isMultiple(of: 25) {
                trimDiskCacheIfNeeded()
            }
        } catch {
            // Artwork can always be fetched again when the optional disk cache is unavailable.
        }
    }

    private func trimDiskCacheIfNeeded() {
        guard let diskCacheDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: diskCacheDirectory,
                  includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              ) else { return }
        let entries = files.compactMap { url -> (url: URL, size: UInt64, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { return nil }
            return (url, UInt64(max(0, size)), date)
        }
        var total = entries.reduce(UInt64(0)) { $0 + $1.size }
        guard total > Self.diskCacheLimitBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > Self.diskCacheTrimTargetBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total = total > entry.size ? total - entry.size : 0
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

private struct DiscoveryRatingLabel: View {
    let title: String
    let rating: AppleGamingWikiRating
    var compact = false

    var body: some View {
        Label {
            Text(compact ? "\(title): \(rating.displayName)" : rating.displayName)
                .lineLimit(1)
        } icon: {
            Image(systemName: rating.symbol)
        }
        .font(compact ? .caption2 : .callout.weight(.semibold))
        .foregroundStyle(rating.color)
    }
}

struct DiscoveryGameDetailView: View {
    @Environment(BorealStore.self) private var store
    let game: AppleGamingWikiGame
    var onSelectProducer: (String) -> Void = { _ in }
    @State private var details: StoreLibraryGame?
    @State private var finishedLoading = false
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let details {
                StoreGameDetailView(game: details, discoveryGame: game, onSelectProducer: onSelectProducer)
            } else if finishedLoading {
                ContentUnavailableView {
                    Label("Game details unavailable", systemImage: "gamecontroller")
                } description: {
                    Text("Boreal could not match \(game.title) to an unambiguous store record.")
                } actions: {
                    Button("Retry", systemImage: "arrow.clockwise") { retryCount += 1 }
                    if let url = URL(string: game.pageURL) {
                        Link("Open source page", destination: url)
                    }
                }
            } else {
                ProgressView("Loading details from Steam and compatibility sources…")
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .task(id: "\(game.id)|\(retryCount)") {
            finishedLoading = false
            details = nil
            await store.ensureDiscoveryMetadata(for: game)
            guard !Task.isCancelled else { return }
            details = await store.discoveryStoreDetails(for: game)
            if !Task.isCancelled {
                finishedLoading = true
            }
        }
    }
}

extension AppleGamingWikiRating {
    nonisolated var rank: Int { Self.allCases.firstIndex(of: self) ?? 5 }
    var color: Color {
        switch self {
        case .perfect: .green
        case .playable: .teal
        case .runs: .cyan
        case .menu: .orange
        case .unplayable: .red
        case .unknown, .notApplicable: .secondary
        }
    }
}
