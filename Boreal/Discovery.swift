import Foundation
import SwiftUI
import AppKit
import ImageIO

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
        case .perfect: "Excellent"
        case .playable: "Good"
        case .runs: "Limited"
        case .menu: "Menu only"
        case .unplayable: "Broken"
        case .unknown: "Unknown"
        case .notApplicable: "Not applicable"
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
        case .all: "All games"
        case .perfect: "Perfect games"
        case .native: "Native"
        case .rosetta2: "Rosetta 2"
        case .crossover: "CrossOver"
        case .wine: "Wine"
        case .parallels: "Parallels"
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
    case forYou
    case all
    case native
    case windows

    var title: String {
        switch self {
        case .forYou: "For You"
        case .all: "All Games"
        case .native: "Native"
        case .windows: "Windows"
        }
    }

    var symbol: String {
        switch self {
        case .forYou: "sparkles"
        case .all: "square.grid.2x2"
        case .native: "apple.logo"
        case .windows: "wineglass"
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
    var isNative: Bool { native.isPlayable || macOSStoreSupport == true }
    var bestMethod: String {
        availableRatings.first(where: { $0.rating.isPlayable })?.title ?? (isNative ? "macOS" : "Unverified")
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
        case .native: isNative
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
    func loadCatalog(forceRefresh: Bool) async throws -> AppleGamingWikiCatalog
    func cachedMetadata(for games: [AppleGamingWikiGame]) async -> [String: DiscoveryGameMetadata]
    func metadata(for game: AppleGamingWikiGame, forceRefresh: Bool) async -> DiscoveryGameMetadata?
    func loadMoreSteam(in catalog: AppleGamingWikiCatalog) async throws -> AppleGamingWikiCatalog
    func searchMacGames(named query: String) async throws -> [AppleGamingWikiGame]
    func searchMacGames(developer: String) async throws -> [AppleGamingWikiGame]
}

extension DiscoveryCatalogLoading {
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
    private let unavailableMetadataCacheURL: URL?
    private var metadataCache: [String: DiscoveryGameMetadata]?
    private var unavailableMetadataCache: [String: Date]?
    private var metadataCacheWriteTask: Task<Void, Never>?
    private var unavailableMetadataCacheWriteTask: Task<Void, Never>?

    init(applicationSupportURL: URL? = nil, session: URLSession = .shared) {
        self.session = session
        cacheURL = applicationSupportURL?.appending(path: "Discovery/applegamingwiki.json", directoryHint: .notDirectory)
        metadataCacheURL = applicationSupportURL?.appending(path: "Discovery/applegamingwiki-metadata.json", directoryHint: .notDirectory)
        unavailableMetadataCacheURL = applicationSupportURL?.appending(path: "Discovery/applegamingwiki-unavailable.json", directoryHint: .notDirectory)
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
        if metadataCache == nil { metadataCache = readMetadataCache() }
        let cutoff = Date.now.addingTimeInterval(-Self.cacheLifetime)
        let requested = Set(games.map(\.id))
        return metadataCache?.filter { requested.contains($0.key) && $0.value.fetchedAt >= cutoff } ?? [:]
    }

    func metadata(for game: AppleGamingWikiGame, forceRefresh: Bool) async -> DiscoveryGameMetadata? {
        if metadataCache == nil { metadataCache = readMetadataCache() }
        if unavailableMetadataCache == nil { unavailableMetadataCache = readUnavailableMetadataCache() }
        if !forceRefresh, let cached = metadataCache?[game.id],
           Date.now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime { return cached }
        if !forceRefresh, let failedAt = unavailableMetadataCache?[game.id],
           Date.now.timeIntervalSince(failedAt) < Self.unavailableMetadataLifetime { return nil }
        if let metadata = await steamMetadata(for: game) {
            cache(metadata, for: game.id)
            return metadata
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
            guard (response as? HTTPURLResponse)?.statusCode == 200,
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
        } catch {
            return cachedOrMarkUnavailable(game.id)
        }
    }

    private func cache(_ metadata: DiscoveryGameMetadata, for id: String) {
        metadataCache?[id] = metadata
        unavailableMetadataCache?.removeValue(forKey: id)
        scheduleMetadataCacheWrite()
        scheduleUnavailableMetadataCacheWrite()
    }

    private func cachedOrMarkUnavailable(_ id: String) -> DiscoveryGameMetadata? {
        if let cached = metadataCache?[id] { return cached }
        unavailableMetadataCache?[id] = .now
        scheduleUnavailableMetadataCacheWrite()
        return nil
    }

    private func scheduleMetadataCacheWrite() {
        metadataCacheWriteTask?.cancel()
        metadataCacheWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.writeMetadataCache()
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

    private func writeMetadataCache() {
        guard let metadataCacheURL, let metadataCache else { return }
        do {
            try FileManager.default.createDirectory(
                at: metadataCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(metadataCache).write(to: metadataCacheURL, options: .atomic)
        } catch {
            // Presentation data remains available for the current session.
        }
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

    private static func parseSteamGames(_ rows: [String]) -> [AppleGamingWikiGame] {
        let tags: [String: String] = Bundle.main.url(forResource: "DiscoveryTags", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
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
                genres: tagIDs.compactMap { tags[$0] }, macOSStoreSupport: true
            )
        }
    }

    static func merge(_ existing: [AppleGamingWikiGame], _ incoming: [AppleGamingWikiGame]) -> [AppleGamingWikiGame] {
        var result = existing
        var steamIndices = Dictionary(
            result.enumerated().compactMap { item in item.element.steamAppID.map { ($0, item.offset) } },
            uniquingKeysWith: { first, _ in first }
        )
        for game in incoming {
            let titleKey = normalizedTitle(game.title)
            let titleMatches = result.indices.filter { normalizedTitle(result[$0].title) == titleKey }
            let index = game.steamAppID.flatMap { steamIndices[$0] }
                ?? (titleMatches.count == 1 && result[titleMatches[0]].steamAppID == nil ? titleMatches[0] : nil)
            if let index {
                result[index].steamAppID = game.steamAppID ?? result[index].steamAppID
                result[index].coverURL = game.coverURL ?? result[index].coverURL
                result[index].genres = game.genres ?? result[index].genres
                result[index].macOSStoreSupport = game.macOSStoreSupport ?? result[index].macOSStoreSupport
                if let steamAppID = result[index].steamAppID { steamIndices[steamAppID] = index }
            } else {
                if let steamAppID = game.steamAppID { steamIndices[steamAppID] = result.count }
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
    @State private var testedOnly = false
    @AppStorage("discoveryListLayout") private var listLayout = false
    @State private var showGuide = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let catalog = store.discoveryCatalog {
                    catalogSummary(catalog)
                    filters(catalog)
                    if !searchText.isEmpty, let message = store.discoverySearchMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    if case .failed(let message) = store.discoveryState {
                        Label(message, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
                    }
                    if case .failed(let message) = store.discoveryPaginationState {
                        Label(message, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
                    }
                    if searchText.isEmpty && !recommendedGames(in: catalog).isEmpty {
                        recommended(recommendedGames(in: catalog))
                    }
                    catalogContent(catalog)
                } else {
                    ContentUnavailableView {
                        Label("Discover games for your Mac", systemImage: "gamecontroller")
                    } description: {
                        if case .failed(let message) = store.discoveryState { Text(message) }
                        else { ProgressView("Loading catalog…") }
                    } actions: {
                        Button("Retry") { store.refreshDiscoveryCatalog() }.disabled(store.discoveryState == .loading)
                    }
                }
            }
            .padding(28)
        }
        .background(LinearGradient(colors: [Color(red: 0.045, green: 0.065, blue: 0.095), Color(red: 0.065, green: 0.075, blue: 0.115)], startPoint: .topTrailing, endPoint: .bottomLeading))
        .task { if store.discoveryCatalog == nil { store.loadDiscoveryCatalog() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh Discovery", systemImage: "arrow.clockwise") { store.refreshDiscoveryCatalog() }
                    .disabled(store.discoveryState == .loading)
            }
        }
        .sheet(isPresented: $showGuide) {
            VStack { guide; Button("Done") { showGuide = false }.keyboardShortcut(.cancelAction) }.padding(28).frame(width: 410)
        }
        .task(id: searchText) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                store.clearDiscoverySearch()
                return
            }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await store.searchDiscoveryGames(query)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("DISCOVER").font(.caption).foregroundStyle(.secondary)
                Text("Find games that work on your Mac").font(.system(size: 28, weight: .bold))
                Text(macProfile.summary)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.86))
                Text("Browse compatibility reports and choose the best available way to play before adding games to your library.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Data sources", systemImage: "info.circle") { showGuide = true }.buttonStyle(.bordered)
        }
    }

    private func catalogSummary(_ catalog: AppleGamingWikiCatalog) -> some View {
        let unknownCount = catalog.games.filter { !$0.isTested }.count
        return HStack(spacing: 7) {
            Image(systemName: "gamecontroller.fill").foregroundStyle(.secondary)
            Text(catalog.trackedCount.formatted()).fontWeight(.semibold)
            Text("games").foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Image(systemName: "apple.logo").foregroundStyle(.secondary)
            Text(catalog.count(for: .native).formatted()).fontWeight(.semibold)
            Text("Native").foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            Text(unknownCount.formatted()).fontWeight(.semibold)
            Text("Compatibility unknown").foregroundStyle(.secondary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(catalog.trackedCount) games, \(catalog.count(for: .native)) native, \(unknownCount) compatibility unknown")
    }

    private func filters(_ catalog: AppleGamingWikiCatalog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Browse", selection: $scope) {
                ForEach(DiscoveryScope.allCases, id: \.self) { value in
                    Label(value.title, systemImage: value.symbol).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    genreMenu(catalog)
                    compatibilityMenu
                    storefrontMenu
                    if scope == .windows { windowsMethodMenu }
                    filtersMenu
                    sortMenu
                }
            }
        }
    }

    private func genreMenu(_ catalog: AppleGamingWikiCatalog) -> some View {
        let genres = Set(catalog.games.flatMap { $0.genres ?? [] }).sorted()
        return Menu {
            filterOption("All genres", selected: genre == "All genres") { genre = "All genres" }
            ForEach(genres, id: \.self) { value in
                filterOption(value, selected: genre == value) { genre = value }
            }
            filterOption("Not provided", selected: genre == "Not provided") { genre = "Not provided" }
        } label: {
            Label(genre == "All genres" ? "Genre" : genre, systemImage: "tag")
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
            Label(rating == "All ratings" ? "Compatibility" : (AppleGamingWikiRating(rawValue: rating)?.displayName ?? rating), systemImage: "checkmark.seal")
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
            Label(storefront == "All stores" ? "Store" : storefront, systemImage: "bag")
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
            Label(windowsMethod == .all ? "Windows path" : windowsMethod.title, systemImage: "wineglass")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var filtersMenu: some View {
        Menu {
            Toggle("Tested compatibility only", isOn: $testedOnly)
                .help("Only entries with community compatibility reports. These are not tests performed by Boreal.")
            Divider()
            Button("Reset filters", systemImage: "arrow.counterclockwise") { resetFilters() }
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(["Recommended", "Name A–Z", "Name Z–A"], id: \.self) { value in
                filterOption(value, selected: sortOrder == value) { sortOrder = value }
            }
        } label: {
            Label("Sort: \(sortOrder)", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private func filterOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
                Text(title)
            }
        }
    }

    private func recommended(_ games: [AppleGamingWikiGame]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recommended for your Mac").font(.title3.bold())
                    Text("Strongest available compatibility reports for this Mac.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(games.count) games").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(games.prefix(4))) { game in
                        DiscoveryGameTile(game: game, horizontal: true) { selectGame(game) }.frame(width: 340)
                    }
                }
            }
        }
    }

    private func catalogContent(_ catalog: AppleGamingWikiCatalog) -> some View {
        let games = catalog.games.filter(matchesFilters).sorted {
            let effectiveSort = scope == .forYou ? "Recommended" : sortOrder
            if effectiveSort == "Recommended", recommendationScore($0) != recommendationScore($1) { return recommendationScore($0) > recommendationScore($1) }
            return effectiveSort == "Name Z–A" ? $0.title.localizedStandardCompare($1.title) == .orderedDescending : $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(scope.title).font(.title3.bold())
                Text("\(games.count.formatted()) games").foregroundStyle(.secondary)
                Spacer()
                Picker("View", selection: $listLayout) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 76)
            }
            if games.isEmpty {
                ContentUnavailableView("No games found", systemImage: "magnifyingglass", description: Text("Try another search or reset your filters."))
                Button("Reset filters") { resetFilters() }
            } else if listLayout {
                LazyVStack(spacing: 8) {
                    ForEach(games) { game in
                        DiscoveryGameTile(game: game, horizontal: true) { selectGame(game) }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 16)], spacing: 16) {
                    ForEach(games) { game in
                        DiscoveryGameTile(game: game) { selectGame(game) }
                    }
                }
            }
            loadMoreTrigger(catalog)
            Text(catalog.isStale ? "Showing the last saved catalog." : "Updated \(catalog.fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func loadMoreTrigger(_ catalog: AppleGamingWikiCatalog) -> some View {
        if (catalog.steamOffset ?? 0) < (catalog.steamTotal ?? 0) {
            if store.discoveryPaginationState == .loading {
                ProgressView("Loading more games…")
                    .frame(maxWidth: .infinity)
            } else {
                Color.clear.frame(height: 2)
                    .onAppear { store.loadMoreDiscoveryGames() }
            }
        }
    }

    private func matchesFilters(_ game: AppleGamingWikiGame) -> Bool {
        matchesScope(game)
            && matchesWindowsMethod(game)
            && (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || game.title.localizedCaseInsensitiveContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines)))
            && (!testedOnly || game.isTested)
            && (rating == "All ratings" || compatibilityRatings(for: game).contains { $0.rawValue == rating })
            && (genre == "All genres" || (genre == "Not provided" ? game.genres?.isEmpty != false : game.genres?.contains(genre) == true))
            && (storefront == "All stores" || (storefront == "Steam" ? game.steamAppID != nil : game.steamAppID == nil))
    }

    private func matchesScope(_ game: AppleGamingWikiGame) -> Bool {
        switch scope {
        case .forYou, .all: true
        case .native: game.isNative
        case .windows: [game.crossover, game.wine, game.parallels].contains { $0 != .unknown && $0 != .notApplicable }
        }
    }

    private func matchesWindowsMethod(_ game: AppleGamingWikiGame) -> Bool {
        guard scope == .windows, windowsMethod != .all else { return true }
        return game.matches(windowsMethod)
    }

    private func compatibilityRatings(for game: AppleGamingWikiGame) -> [AppleGamingWikiRating] {
        switch scope {
        case .native: [game.native]
        case .windows:
            switch windowsMethod {
            case .crossover: [game.crossover]
            case .wine: [game.wine]
            case .parallels: [game.parallels]
            case .all: [game.crossover, game.wine, game.parallels]
            case .native, .rosetta2, .perfect: []
            }
        case .forYou, .all: game.availableRatings.map(\.rating)
        }
    }

    private func recommendedGames(in catalog: AppleGamingWikiCatalog) -> [AppleGamingWikiGame] {
        catalog.games.filter {
            ($0.native == .perfect || $0.rosetta2 == .perfect || $0.crossover == .perfect || $0.wine == .perfect || $0.parallels == .perfect)
                && matchesFilters($0)
        }
        .sorted {
            recommendationScore($0) == recommendationScore($1)
                ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                : recommendationScore($0) > recommendationScore($1)
        }
    }

    private func recommendationScore(_ game: AppleGamingWikiGame) -> Int {
        let perfectPathScore = [game.native, game.rosetta2, game.crossover, game.wine, game.parallels]
            .enumerated()
            .first(where: { $0.element == .perfect })
            .map { 100 - ($0.offset * 5) } ?? 0
        return perfectPathScore + (game.coverURL == nil ? 0 : 10) - game.bestRating.rank
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
            guideRow("Add to library", "Save games you’re interested in. Purchase and installation are handled separately.", "plus")
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
        testedOnly = false
        sortOrder = "Recommended"
        scope = .all
        searchText = ""
    }

    private var macProfile: DiscoveryMacProfile { .current }
}

private struct DiscoveryMacProfile: Sendable {
    let chip: String
    let memory: String
    let os: String

    var summary: String { "\(chip) · \(memory) · \(os)" }

    static var current: Self {
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
    }

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
    let open: () -> Void
    private var metadata: DiscoveryGameMetadata? { store.discoveryMetadata[game.id] }

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .top, spacing: 12) {
                    artwork.frame(width: 105)
                    details.layoutPriority(1)
                    Spacer(minLength: 0)
                }
                    .padding(9)
            } else {
                VStack(alignment: .leading, spacing: 0) { artwork; details.padding(10) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.09)))
        .task(id: "\(game.id)-\(itadAPIKey)-\(itadCountryCode)") {
            async let metadata: Void = store.ensureDiscoveryMetadata(for: game)
            if !itadAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await store.ensureDiscoveryPrice(for: game)
            }
            await metadata
        }
    }

    private var artwork: some View {
        Button(action: open) {
            DiscoveryArtwork(
                imageURL: (game.steamAppID ?? metadata?.steamAppID).map {
                    "https://cdn.cloudflare.steamstatic.com/steam/apps/\($0)/header.jpg"
                } ?? metadata?.coverImageURL ?? game.coverURL,
                fallbackImageURL: metadata?.coverImageURL ?? game.coverURL,
                title: game.title,
                isLoading: store.isDiscoveryMetadataLoading(for: game),
                height: horizontal ? 106 : 142
            )
        }.buttonStyle(.plain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: horizontal ? 7 : 9) {
            Button(action: open) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text((game.genres ?? metadata?.genres)?.prefix(2).joined(separator: " · ") ?? "Genre not provided")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                platformBadge
                if game.isTested {
                    DiscoveryRatingLabel(title: "Compatibility", rating: game.bestRating)
                } else {
                    Label("Compatibility unknown", systemImage: "questionmark.circle")
                        .font(horizontal ? .caption : .caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if game.isTested, game.bestMethod != "Unverified" {
                Label("Reported via \(game.bestMethod)", systemImage: methodSymbol)
                    .font(horizontal ? .caption : .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            discoveryPrice
            HStack(spacing: 8) {
                if let id = game.steamAppID ?? metadata?.steamAppID,
                   let url = URL(string: "https://store.steampowered.com/app/\(id)/") {
                    Link(destination: url) {
                        Label("Steam", systemImage: "bag")
                            .font(horizontal ? .caption : .caption2)
                    }
                    .help("Open Steam store page")
                } else {
                    Text("Store unknown")
                        .font(horizontal ? .caption : .caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Button {
                    store.toggleDiscoveryGame(game)
                } label: {
                    Label(store.isDiscoveryGameSaved(game) ? "In Library" : "Add to Library", systemImage: store.isDiscoveryGameSaved(game) ? "checkmark" : "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(store.isDiscoveryGameSaved(game) ? "Remove from saved games" : "Save to your library")
            }
        }
        .frame(maxWidth: .infinity, minHeight: horizontal ? 118 : 182, alignment: .topLeading)
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
        if game.isNative { return "Native macOS" }
        if game.bestMethod == "Rosetta 2" { return "Rosetta 2" }
        return "Windows"
    }

    private var platformSymbol: String {
        if game.isNative { return "apple.logo" }
        switch game.bestMethod {
        case "CrossOver": return "rectangle.2.swap"
        case "Parallels": return "rectangle.split.3x1"
        case "Wine": return "wineglass"
        case "Rosetta 2": return "cpu"
        default: return "rectangle.on.rectangle"
        }
    }

    private var methodSymbol: String {
        switch game.bestMethod {
        case "CrossOver": "rectangle.2.swap"
        case "Parallels": "rectangle.split.3x1"
        case "Wine": "wineglass"
        case "Rosetta 2": "cpu"
        default: "checkmark.circle"
        }
    }

    @ViewBuilder private var discoveryPrice: some View {
        if let offer = store.discoveryPriceSummary(for: game)?.bestOffer {
            HStack(spacing: 6) {
                Text(offer.shop.name)
                    .font(horizontal ? .caption : .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
}

struct SavedDiscoveryGamesView: View {
    @Environment(BorealStore.self) private var store
    var searchText: String
    @State private var selectedGame: AppleGamingWikiGame?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved from Discovery").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
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
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.78), .cyan.opacity(0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let loadedImage {
                Image(nsImage: loadedImage).resizable().scaledToFill()
            } else if imageURL != nil && !attemptedLoad {
                placeholder.overlay { ProgressView().tint(.white) }
            } else if isLoading {
                placeholder.overlay { ProgressView().tint(.white) }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
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

private actor DiscoveryImagePipeline {
    static let shared = DiscoveryImagePipeline()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    func image(for url: URL, maxPixelSize: Int) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task.detached(priority: .utility) { () -> NSImage? in
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: thumbnail, size: .zero)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let representation = image.representations.first
            let width = representation?.pixelsWide ?? Int(image.size.width)
            let height = representation?.pixelsHigh ?? Int(image.size.height)
            cache.setObject(image, forKey: url as NSURL, cost: max(1, width * height * 4))
        }
        return image
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

    var body: some View {
        Group {
            if let details {
                StoreGameDetailView(game: details, discoveryGame: game, onSelectProducer: onSelectProducer)
            } else if finishedLoading {
                ContentUnavailableView(
                    "Game details unavailable",
                    systemImage: "gamecontroller",
                    description: Text("Boreal could not match \(game.title) to an unambiguous store record.")
                )
            } else {
                ProgressView("Loading details from Steam and compatibility sources…")
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .task(id: game.id) {
            await store.ensureDiscoveryMetadata(for: game)
            details = await store.discoveryStoreDetails(for: game)
            finishedLoading = true
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
