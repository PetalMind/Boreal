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
        case .perfect, .playable, .runs, .menu: true
        case .unplayable, .unknown, .notApplicable: false
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

    var id: String { pageURL }

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
            [native, rosetta2, crossover, wine, parallels, linuxARM].contains(.perfect)
        case .native: native.isPlayable
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
}

extension DiscoveryCatalogLoading {
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
        let cached = readCache()
        if !forceRefresh,
           let cached,
           Date.now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return cached
        }

        do {
            var catalog = try await fetchCatalog()
            catalog.isStale = false
            writeCache(catalog)
            return catalog
        } catch {
            guard var cached else { throw error }
            cached.isStale = true
            return cached
        }
    }

    func metadata(for game: AppleGamingWikiGame, forceRefresh: Bool) async -> DiscoveryGameMetadata? {
        if metadataCache == nil { metadataCache = readMetadataCache() }
        if !forceRefresh, let cached = metadataCache?[game.id] { return cached }

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

        for _ in 0..<10 {
            let html = try await fetchHTML(from: pageURL)
            if sourceUpdatedAt == nil { sourceUpdatedAt = Self.sourceDate(in: html) }
            games.append(contentsOf: Self.parseGames(from: html))

            guard let next = Self.nextPageURL(in: html), seenURLs.insert(next.absoluteString).inserted else { break }
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
            sourceUpdatedAt: sourceUpdatedAt
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

    private static func parseGames(from html: String) -> [AppleGamingWikiGame] {
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

    private static func matches(_ pattern: String, in value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func firstMatch(_ pattern: String, in value: String) -> String? {
        matches(pattern, in: value).first
    }

    private static func decodeHTML(_ value: String) -> String {
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

// MARK: - Discovery view

struct DiscoveryView: View {
    @Environment(BorealStore.self) private var store
    @Binding var searchText: String
    @State private var platform: AppleGamingWikiPlatform = .all
    @State private var sortAscending = true
    @State private var selectedGame: AppleGamingWikiGame?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let catalog = store.discoveryCatalog {
                    stats(catalog)
                    platformPicker(catalog)
                    catalogContent(catalog)
                } else {
                    stateContent
                }
            }
            .padding(30)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .task { store.loadDiscoveryCatalog() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.refreshDiscoveryCatalog()
                } label: {
                    Label("Refresh Discovery", systemImage: "arrow.clockwise")
                }
                .disabled(store.discoveryState == .loading)
                .help("Refresh AppleGamingWiki data")
            }
        }
        .sheet(item: $selectedGame) { game in
            DiscoveryGameDetailView(game: game)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Discovery", systemImage: "sparkles")
                .font(.largeTitle.weight(.bold))
            Text("Find games that fit your Mac before adding them to your Library.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Community compatibility from AppleGamingWiki. These ratings describe the external method, not a Boreal-tested configuration or a guaranteed GPTK result.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Browse AppleGamingWiki master list", destination: URL(string: "https://www.applegamingwiki.com/wiki/M1_compatible_games_master_list")!)
                .font(.callout.weight(.medium))
                .foregroundStyle(.cyan)
        }
    }

    private func stats(_ catalog: AppleGamingWikiCatalog) -> some View {
        HStack(spacing: 12) {
            DiscoveryMetric(title: "Tracked", value: catalog.trackedCount.formatted(), symbol: "list.number", tint: .cyan)
            DiscoveryMetric(title: "Playable", value: catalog.playableCount.formatted(), symbol: "checkmark.circle.fill", tint: .green)
            DiscoveryMetric(title: "Native", value: catalog.count(for: .native).formatted(), symbol: "apple.logo", tint: .teal)
            DiscoveryMetric(title: "CrossOver", value: catalog.count(for: .crossover).formatted(), symbol: "rectangle.2.swap", tint: .purple)
        }
    }

    private func platformPicker(_ catalog: AppleGamingWikiCatalog) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AppleGamingWikiPlatform.allCases, id: \.self) { value in
                    Button {
                        platform = value
                    } label: {
                        Label("\(value.title)  \(value == .all ? catalog.trackedCount : catalog.count(for: value))", systemImage: value.symbol)
                    }
                    .buttonStyle(.bordered)
                    .tint(platform == value ? .accentColor : .secondary)
                    .controlSize(.small)
                }
                Divider().frame(height: 20)
                Button {
                    sortAscending.toggle()
                } label: {
                    Label(sortAscending ? "A–Z" : "Z–A", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func catalogContent(_ catalog: AppleGamingWikiCatalog) -> some View {
        let games = visibleGames(from: catalog)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(platform.title).font(.title2.weight(.semibold))
                Text("\(games.count) games")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if catalog.isStale {
                    Label("Cached data", systemImage: "externaldrive")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("AppleGamingWiki", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let sourceUpdatedAt = catalog.sourceUpdatedAt {
                Text("Source refreshed \(sourceUpdatedAt.formatted(date: .abbreviated, time: .omitted)) · fetched \(catalog.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if games.isEmpty {
                ContentUnavailableView("No games found", systemImage: "magnifyingglass", description: Text("Try another search or compatibility method."))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 14)], spacing: 14) {
                    ForEach(games) { game in
                        Button { selectedGame = game } label: {
                            DiscoveryGameCard(game: game, selectedPlatform: platform)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var stateContent: some View {
        Group {
            switch store.discoveryState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading AppleGamingWiki…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Discovery unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again", systemImage: "arrow.clockwise") { store.refreshDiscoveryCatalog() }
                }
            case .loaded:
                EmptyView()
            }
        }
    }

    private func visibleGames(from catalog: AppleGamingWikiCatalog) -> [AppleGamingWikiGame] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = catalog.games.filter { game in
            game.matches(platform)
                && (query.isEmpty || game.title.localizedCaseInsensitiveContains(query))
        }
        return filtered.sorted {
            let result = $0.title.localizedStandardCompare($1.title)
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }
}

private struct DiscoveryMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.title2.weight(.bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12)) }
    }
}

private struct DiscoveryGameCard: View {
    @Environment(BorealStore.self) private var store
    let game: AppleGamingWikiGame
    let selectedPlatform: AppleGamingWikiPlatform

    private var metadata: DiscoveryGameMetadata? { store.discoveryMetadata[game.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoveryArtwork(
                imageURL: metadata?.coverImageURL ?? metadata?.originalImageURL,
                title: game.title,
                isLoading: store.isDiscoveryMetadataLoading(for: game),
                height: 176
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(game.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if let summary = metadata?.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                } else if store.isDiscoveryMetadataUnavailable(for: game) {
                    Text("No description available from the source.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let rating = game.rating(for: selectedPlatform) {
                    DiscoveryRatingLabel(title: selectedPlatform.title, rating: rating)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(game.availableRatings.prefix(4), id: \.title) { entry in
                            DiscoveryRatingLabel(title: entry.title, rating: entry.rating, compact: true)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("AppleGamingWiki")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.12)) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: game.id) { store.loadDiscoveryMetadata(for: game) }
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

private struct DiscoveryGameDetailView: View {
    @Environment(BorealStore.self) private var store
    let game: AppleGamingWikiGame
    @Environment(\.dismiss) private var dismiss

    private var metadata: DiscoveryGameMetadata? { store.discoveryMetadata[game.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(game.title).font(.title2.weight(.bold))
                    Text("Community compatibility data")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(24)
            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    DiscoveryArtwork(
                        imageURL: metadata?.originalImageURL ?? metadata?.coverImageURL,
                        title: game.title,
                        isLoading: store.isDiscoveryMetadataLoading(for: game),
                        height: 280
                    )
                    .frame(width: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About").font(.headline)
                            if let summary = metadata?.summary {
                                Text(summary)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if store.isDiscoveryMetadataLoading(for: game) {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Loading description…")
                                }
                                .foregroundStyle(.secondary)
                            } else {
                                Text("No description is available from AppleGamingWiki for this game.")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Compatibility methods").font(.headline)
                            ForEach(game.availableRatings, id: \.title) { entry in
                                HStack {
                                    Text(entry.title)
                                    Spacer()
                                    DiscoveryRatingLabel(title: "", rating: entry.rating)
                                }
                                Divider().opacity(0.45)
                            }
                        }

                        Text("AppleGamingWiki ratings are community data. Wine and CrossOver results do not verify that GPTK/D3DMetal works, and they do not replace a Boreal-tested profile.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let destination = URL(string: metadata?.sourceURL ?? game.pageURL) {
                            Link(destination: destination) {
                                Label("Open AppleGamingWiki page", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
        }
        .frame(width: 760)
        .frame(minHeight: 560)
        .task(id: game.id) { store.loadDiscoveryMetadata(for: game) }
    }
}

private extension AppleGamingWikiRating {
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
