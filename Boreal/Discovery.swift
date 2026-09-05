import Foundation
import SwiftUI

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

nonisolated struct AppleGamingWikiRatingEntry: Hashable, Sendable {
    let title: String
    let rating: AppleGamingWikiRating
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
    func metadata(for game: AppleGamingWikiGame, forceRefresh: Bool) async -> DiscoveryGameMetadata?
    func loadMoreSteam(in catalog: AppleGamingWikiCatalog) async throws -> AppleGamingWikiCatalog
    func searchMacGames(named query: String) async throws -> [AppleGamingWikiGame]
}

extension DiscoveryCatalogLoading {
    func searchMacGames(named query: String) async throws -> [AppleGamingWikiGame] { [] }
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

    private let session: URLSession
    private let cacheURL: URL?
    private let metadataCacheURL: URL?
    private var metadataCache: [String: DiscoveryGameMetadata]?

    init(applicationSupportURL: URL? = nil, session: URLSession = .shared) {
        self.session = session
        cacheURL = applicationSupportURL?.appending(path: "Discovery/applegamingwiki.json", directoryHint: .notDirectory)
        metadataCacheURL = applicationSupportURL?.appending(path: "Discovery/applegamingwiki-metadata.json", directoryHint: .notDirectory)
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

    func metadata(for game: AppleGamingWikiGame, forceRefresh: Bool) async -> DiscoveryGameMetadata? {
        if metadataCache == nil { metadataCache = readMetadataCache() }
        if !forceRefresh, let cached = metadataCache?[game.id],
           Date.now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime { return cached }
        if let metadata = await steamMetadata(for: game) {
            metadataCache?[game.id] = metadata
            writeMetadataCache()
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
                  page.pageid != nil else { return metadataCache?[game.id] }

            let metadata = DiscoveryGameMetadata(
                summary: Self.cleanedSummary(page.extract, gameTitle: game.title),
                coverImageURL: page.thumbnail?.source,
                originalImageURL: page.original?.source,
                sourceURL: page.fullurl ?? game.pageURL,
                fetchedAt: .now
            )
            guard metadata.hasPresentationContent else { return metadataCache?[game.id] }
            metadataCache?[game.id] = metadata
            writeMetadataCache()
            return metadata
        } catch {
            return metadataCache?[game.id]
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

    private func fetchSteamPage(offset: Int, query: String? = nil) async throws -> SteamPage {
        var components = URLComponents(string: "https://store.steampowered.com/search/results/")!
        components.queryItems = [
            .init(name: "start", value: String(offset)), .init(name: "count", value: "100"),
            .init(name: "os", value: "mac"), .init(name: "category1", value: "998"),
            .init(name: "infinite", value: "1"), .init(name: "l", value: "english")
        ]
        if let query { components.queryItems?.append(.init(name: "term", value: query)) }
        guard let url = components.url else { throw AppleGamingWikiDiscoveryError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = root["results_html"] as? String,
              let total = root["total_count"] as? Int else { throw AppleGamingWikiDiscoveryError.invalidResponse }
        let games = Self.parseSteamGames(html)
        guard !games.isEmpty || offset >= total else { throw AppleGamingWikiDiscoveryError.emptyCatalog }
        return SteamPage(games: games, offset: offset + games.count, total: total)
    }

    static func parseSteamGames(_ html: String) -> [AppleGamingWikiGame] {
        let tags: [String: String] = Bundle.main.url(forResource: "DiscoveryTags", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return matches(#"(<a\s[^>]*class="search_result_row.*?</a>)"#, in: html).compactMap { row in
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
        var indices = Dictionary(result.enumerated().map { ($0.element.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")), $0.offset) }, uniquingKeysWith: { first, _ in first })
        for game in incoming {
            let key = game.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if let index = indices[key] {
                result[index].steamAppID = game.steamAppID ?? result[index].steamAppID
                result[index].coverURL = game.coverURL ?? result[index].coverURL
                result[index].genres = game.genres ?? result[index].genres
                result[index].macOSStoreSupport = game.macOSStoreSupport ?? result[index].macOSStoreSupport
            } else {
                indices[key] = result.count
                result.append(game)
            }
        }
        return result
    }

    func searchMacGames(named query: String) async throws -> [AppleGamingWikiGame] {
        try await fetchSteamPage(offset: 0, query: query).games
    }

    func loadMoreSteam(in catalog: AppleGamingWikiCatalog) async throws -> AppleGamingWikiCatalog {
        let page = try await fetchSteamPage(offset: catalog.steamOffset ?? 0)
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
    @State private var platform: AppleGamingWikiPlatform = .all
    @State private var genre = "All genres"
    @State private var rating = "All ratings"
    @State private var storefront = "All stores"
    @State private var sortOrder = "Recommended"
    @State private var testedOnly = false
    @AppStorage("discoveryListLayout") private var listLayout = false
    @State private var showGuide = false
    @AppStorage("discoveryGamesPerPage") private var gamesPerPage = 40
    @State private var currentPage = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let catalog = store.discoveryCatalog {
                        stats(catalog)
                        filters(catalog)
                        if !searchText.isEmpty, let message = store.discoverySearchMessage {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                        if let notice = catalog.sourceNotice {
                            Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                        }
                        if case .failed(let message) = store.discoveryState {
                            Label(message, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
                        }
                        if searchText.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Recommended for your Mac").font(.title3.bold())
                                    Text("Games with a Perfect community rating on macOS.").font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("See All", systemImage: "chevron.right") {
                                    platform = .perfect
                                    withAnimation { proxy.scrollTo("allGames", anchor: .top) }
                                }.buttonStyle(.bordered)
                            }
                            recommended(catalog)
                        }
                        catalogContent(catalog).id("allGames")
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
            .onChange(of: currentPage) { withAnimation { proxy.scrollTo("allGames", anchor: .top) } }
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
            guard !query.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await store.searchDiscoveryGames(query)
        }
        .onChange(of: searchText) { currentPage = 0 }
        .onChange(of: platform) { currentPage = 0 }
        .onChange(of: genre) { currentPage = 0 }
        .onChange(of: rating) { currentPage = 0 }
        .onChange(of: storefront) { currentPage = 0 }
        .onChange(of: sortOrder) { currentPage = 0 }
        .onChange(of: testedOnly) { currentPage = 0 }
        .onChange(of: gamesPerPage) { currentPage = 0 }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("DISCOVER").font(.caption).foregroundStyle(.secondary)
                Text("Discover games for your Mac").font(.system(size: 28, weight: .bold))
                Text("Browse compatibility reports and find the best way to play before adding games to your library.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Learn more", systemImage: "book") { showGuide = true }.buttonStyle(.bordered)
        }
    }

    private func stats(_ catalog: AppleGamingWikiCatalog) -> some View {
        HStack(spacing: 10) {
            DiscoveryMetric(title: "Tracked games", value: catalog.trackedCount.formatted(), symbol: "gamecontroller", tint: .blue)
            DiscoveryMetric(title: "Playable", value: catalog.playableCount.formatted(), symbol: "checkmark.circle.fill", tint: .green)
            DiscoveryMetric(title: "Native / macOS", value: catalog.count(for: .native).formatted(), symbol: "apple.logo", tint: .blue)
            DiscoveryMetric(title: "CrossOver / Wine / Parallels", value: catalog.games.filter { $0.crossover.isPlayable || $0.wine.isPlayable || $0.parallels.isPlayable }.count.formatted(), symbol: "atom", tint: .purple)
        }
    }

    private func filters(_ catalog: AppleGamingWikiCatalog) -> some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppleGamingWikiPlatform.allCases, id: \.self) { value in
                        Button { platform = value } label: {
                            Label(value.title, systemImage: value.symbol).padding(.horizontal, 6).padding(.vertical, 5)
                        }.buttonStyle(.bordered).tint(platform == value ? .blue : .gray)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { filterMenus(catalog); Spacer(); testedToggle }
                VStack(alignment: .leading) { filterMenus(catalog); testedToggle }
            }
        }
    }

    private func filterMenus(_ catalog: AppleGamingWikiCatalog) -> some View {
        let genres = Set(catalog.games.flatMap { $0.genres ?? [] }).sorted()
        return HStack(spacing: 8) {
            Picker("Genre", selection: $genre) {
                Text("All genres").tag("All genres")
                ForEach(genres, id: \.self) { Text($0).tag($0) }
                Text("Not provided").tag("Not provided")
            }.frame(maxWidth: 180)
            Picker("Compatibility", selection: $rating) {
                Text("All ratings").tag("All ratings")
                ForEach(AppleGamingWikiRating.allCases.filter { $0 != .notApplicable }, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }.frame(maxWidth: 190)
            Picker("Storefront", selection: $storefront) {
                Text("All stores").tag("All stores")
                Text("Steam").tag("Steam")
                Text("Other / unknown").tag("Other / unknown")
            }.frame(maxWidth: 160)
            Picker("Sort by", selection: $sortOrder) {
                ForEach(["Recommended", "Name A–Z", "Name Z–A"], id: \.self) { Text($0).tag($0) }
            }.frame(maxWidth: 165)
        }.labelsHidden().controlSize(.large)
    }

    private var testedToggle: some View {
        Toggle("Tested only", isOn: $testedOnly).toggleStyle(.switch).controlSize(.small)
            .help("Only entries with community compatibility reports. These are not tests performed by Boreal.")
    }

    private func recommended(_ catalog: AppleGamingWikiCatalog) -> some View {
        let games = catalog.games.filter { ($0.native == .perfect || $0.rosetta2 == .perfect) && matchesFilters($0) }
            .sorted { recommendationScore($0) == recommendationScore($1) ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : recommendationScore($0) > recommendationScore($1) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(games.prefix(3))) { game in
                    DiscoveryGameTile(game: game, horizontal: true) { selectGame(game) }.frame(width: 310)
                }
                if games.isEmpty { Text("No recommendations match these filters.").foregroundStyle(.secondary).padding() }
            }
        }
    }

    private func catalogContent(_ catalog: AppleGamingWikiCatalog) -> some View {
        let games = catalog.games.filter(matchesFilters).sorted {
            if sortOrder == "Recommended", recommendationScore($0) != recommendationScore($1) { return recommendationScore($0) > recommendationScore($1) }
            return sortOrder == "Name Z–A" ? $0.title.localizedStandardCompare($1.title) == .orderedDescending : $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let pageCount = max(1, Int(ceil(Double(games.count) / Double(gamesPerPage))))
        let page = min(currentPage, pageCount - 1)
        let visibleGames = Array(games.dropFirst(page * gamesPerPage).prefix(gamesPerPage))
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("All Games").font(.title3.bold())
                Text("\(games.count.formatted()) games").foregroundStyle(.secondary)
                Spacer()
                Picker("Games per page", selection: $gamesPerPage) {
                    ForEach([20, 40, 80], id: \.self) { Text("\($0) per page").tag($0) }
                }.frame(width: 140)
                Picker("View", selection: $listLayout) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(false)
                    Label("List", systemImage: "list.bullet").tag(true)
                }.pickerStyle(.segmented).frame(width: 150)
            }
            if games.isEmpty {
                ContentUnavailableView("No games found", systemImage: "magnifyingglass", description: Text("Try another search or reset your filters."))
                Button("Reset filters") { genre = "All genres"; rating = "All ratings"; storefront = "All stores"; platform = .all; testedOnly = false; searchText = "" }
            } else if listLayout {
                LazyVStack(spacing: 8) {
                    ForEach(visibleGames) { game in
                        DiscoveryGameTile(game: game, horizontal: true) { selectGame(game) }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12)], spacing: 12) {
                    ForEach(visibleGames) { game in
                        DiscoveryGameTile(game: game) { selectGame(game) }
                    }
                }
            }
            HStack {
                Text("Page \(page + 1) of \(pageCount)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Previous page", systemImage: "chevron.left") { currentPage = max(0, page - 1) }
                    .labelStyle(.iconOnly).buttonStyle(.bordered).disabled(page == 0)
                ForEach(Array(paginationItems(current: page, count: pageCount).enumerated()), id: \.offset) { _, item in
                    if let index = item {
                        Button { currentPage = index } label: { Text("\(index + 1)") }
                            .buttonStyle(.plain)
                            .frame(minWidth: 34, minHeight: 34)
                            .foregroundStyle(index == page ? .white : .primary)
                            .background(index == page ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                            .accessibilityLabel("Page \(index + 1)")
                            .accessibilityAddTraits(index == page ? .isSelected : [])
                    } else {
                        Text("…").frame(minWidth: 24).foregroundStyle(.secondary)
                    }
                }
                Button("Next page", systemImage: "chevron.right") { currentPage = min(pageCount - 1, page + 1) }
                    .labelStyle(.iconOnly).buttonStyle(.bordered).disabled(page + 1 >= pageCount)
                Spacer()
                Text(catalog.isStale ? "Saved catalog" : "Updated \(catalog.fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let total = catalog.steamTotal {
                Text("Steam: \((catalog.steamOffset ?? 0).formatted()) of \(total.formatted()) listings loaded. Search also checks the live macOS catalog.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Compatibility: AppleGamingWiki • macOS availability, artwork and game information: Steam. Genre and storefront filters use identified catalog records; unknown values are available under ‘Not provided’ or ‘Other / unknown’.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func paginationItems(current: Int, count: Int) -> [Int?] {
        guard count > 7 else { return Array(0..<count).map(Optional.some) }
        let pages = Set([0, count - 1, current - 1, current, current + 1].filter { (0..<count).contains($0) }).sorted()
        return pages.enumerated().flatMap { offset, page in
            offset > 0 && page - pages[offset - 1] > 1 ? [nil, page] : [page]
        }
    }

    private func matchesFilters(_ game: AppleGamingWikiGame) -> Bool {
        game.matches(platform)
            && (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || game.title.localizedCaseInsensitiveContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines)))
            && (!testedOnly || game.isTested)
            && (rating == "All ratings" || (game.rating(for: platform) ?? game.bestRating).rawValue == rating)
            && (genre == "All genres" || (genre == "Not provided" ? game.genres?.isEmpty != false : game.genres?.contains(genre) == true))
            && (storefront == "All stores" || (storefront == "Steam" ? game.steamAppID != nil : game.steamAppID == nil))
    }

    private func recommendationScore(_ game: AppleGamingWikiGame) -> Int {
        (game.native == .perfect ? 100 : game.rosetta2 == .perfect ? 90 : 0) + (game.coverURL == nil ? 0 : 10) - game.bestRating.rank
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
}

private struct DiscoveryMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                .frame(width: 45, height: 45).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) { Text(value).font(.title3.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 72)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.08)))
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
            await store.ensureDiscoveryMetadata(for: game)
            await store.ensureDiscoveryPrice(for: game)
        }
    }

    private var artwork: some View {
        Button(action: open) {
            DiscoveryArtwork(imageURL: metadata?.coverImageURL ?? game.coverURL, title: game.title, isLoading: store.isDiscoveryMetadataLoading(for: game), height: horizontal ? 106 : 96)
        }.buttonStyle(.plain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: open) { Text(game.title).font(horizontal ? .headline : .system(size: 12, weight: .semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            Text((game.genres ?? metadata?.genres)?.prefix(2).joined(separator: " · ") ?? "Genre not provided").font(horizontal ? .caption : .caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(metadata?.developer ?? (game.pageURL.contains("applegamingwiki") ? "AppleGamingWiki" : "Steam")).font(horizontal ? .caption : .caption2).foregroundStyle(.secondary).lineLimit(1)
            Label(game.bestMethod == "Unverified" ? game.bestRating.rawValue : game.bestMethod, systemImage: "circle.fill")
                .font(horizontal ? .caption : .system(size: 10)).foregroundStyle(game.isNative ? .green : game.bestRating.color)
                .padding(.horizontal, 7).padding(.vertical, 4).background((game.isNative ? Color.green : game.bestRating.color).opacity(0.1), in: Capsule())
            discoveryPrice
            HStack {
                if let id = game.steamAppID ?? metadata?.steamAppID, let url = URL(string: "https://store.steampowered.com/app/\(id)/") {
                    Link(destination: url) { Image("SteamLogo").resizable().scaledToFit().frame(width: 17, height: 17) }.help("Open Steam store page")
                }
                Spacer(minLength: 2)
                Button(store.isDiscoveryGameSaved(game) ? "Added" : "Add", systemImage: store.isDiscoveryGameSaved(game) ? "checkmark" : "plus") { store.toggleDiscoveryGame(game) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(store.isDiscoveryGameSaved(game) ? "Remove from saved games" : "Save to your library")
            }
        }.frame(maxWidth: .infinity, minHeight: horizontal ? 100 : 132, alignment: .topLeading)
    }

    @ViewBuilder private var discoveryPrice: some View {
        if let offer = store.discoveryPriceSummary(for: game)?.bestOffer {
            HStack(spacing: 6) {
                Text(offer.price.formatted)
                    .font(horizontal ? .headline.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if let discount = offer.discountLabel {
                    Text(discount)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 0)
            }
            Text(offer.shop.name)
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if store.isDiscoveryPriceLoading(for: game) {
            Label("Loading price…", systemImage: "arrow.triangle.2.circlepath")
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Price unavailable")
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
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
    let title: String
    let isLoading: Bool
    let height: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.78), .cyan.opacity(0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        placeholder.overlay { ProgressView().tint(.white) }
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
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

private struct DiscoveryRatingLabel: View {
    let title: String
    let rating: AppleGamingWikiRating
    var compact = false

    var body: some View {
        Label {
            Text(compact ? "\(title): \(rating.rawValue)" : rating.rawValue)
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
    @State private var details: StoreLibraryGame?
    @State private var finishedLoading = false

    var body: some View {
        Group {
            if let details {
                StoreGameDetailView(game: details, discoveryGame: game)
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
