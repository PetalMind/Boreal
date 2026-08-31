import Foundation

nonisolated protocol SteamLibraryLoading: Sendable {
    func loadLibrary() async throws -> [StoreLibraryGame]
    func loadDetails(for game: StoreLibraryGame) async -> StoreLibraryGame
    func loadCurrentPlayerCount(appID: String) async -> Int?
}

enum SteamLibraryError: LocalizedError {
    case steamNotInstalled
    case noSignedInAccount
    case libraryUnavailable

    var errorDescription: String? {
        switch self {
        case .steamNotInstalled:
            "Steam is not installed in this macOS account."
        case .noSignedInAccount:
            "Open Steam and sign in first, then import the Library again."
        case .libraryUnavailable:
            "Steam’s local Library data could not be read."
        }
    }
}

actor SteamLibraryService: SteamLibraryLoading {
    private struct CurrentPlayersResponse: Decodable {
        struct Response: Decodable {
            let playerCount: Int?
            let result: Int

            enum CodingKeys: String, CodingKey {
                case playerCount = "player_count"
                case result
            }
        }

        let response: Response
    }

    private struct LocalGame: Sendable {
        let appID: String
        var name: String?
        var developer: String?
        var summary: String?
        var playtimeMinutes = 0
        var lastPlayed: Date?
        var artworkPath: String?
        var isInstalled = false
        var installPath: String?
        var storageBytes: Int64?
        var buildID: String?
    }

    private struct StoreMetadata: Sendable {
        var name: String?
        var developer: String?
        var publisher: String?
        var releaseDate: String?
        var genres: [String]?
        var features: [String]?
        var summary: String?
        var portraitImageURL: String?
        var headerImageURL: String?
        var backgroundImageURL: String?
        var screenshotURLs: [String]?
        var videos: [StoreVideo]?
        var rating: StoreRating?
        var supportsWindows: Bool?
        var supportsNativeMacOS: Bool?
        var sizeEstimate: StoreGameSizeEstimate?
        var websiteURL: String?
        var supportURL: String?
        var minimumSystemRequirements: String?
        var recommendedSystemRequirements: String?
        var achievements: [StoreAchievement]?
        var achievementCount: Int?
        var patchNotes: [StorePatchNote]?
    }

    private let fileManager: FileManager
    private let steamRoot: URL
    private let session: URLSession
    private let compatibilityLoader: any ProtonCompatibilityLoading

    init(
        steamRoot: URL? = nil,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        compatibilityLoader: (any ProtonCompatibilityLoading)? = nil
    ) {
        self.fileManager = fileManager
        self.steamRoot = steamRoot ?? fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Steam", directoryHint: .isDirectory)
        self.session = session
        self.compatibilityLoader = compatibilityLoader ?? ProtonCompatibilityService(session: session)
    }

    func loadLibrary() async throws -> [StoreLibraryGame] {
        guard fileManager.fileExists(atPath: steamRoot.path) else { throw SteamLibraryError.steamNotInstalled }
        let users = try signedInUserDirectories()
        guard !users.isEmpty else { throw SteamLibraryError.noSignedInAccount }

        var localGames: [String: LocalGame] = [:]
        for userDirectory in users {
            try mergeUserLibrary(at: userDirectory, into: &localGames)
        }
        try mergeInstalledGames(into: &localGames)
        guard !localGames.isEmpty else { throw SteamLibraryError.libraryUnavailable }

        let sorted = localGames.values.sorted { numericAppID($0.appID) < numericAppID($1.appID) }
        var results: [StoreLibraryGame] = []
        results.reserveCapacity(sorted.count)

        for start in stride(from: 0, to: sorted.count, by: 8) {
            let end = min(start + 8, sorted.count)
            let chunk = Array(sorted[start..<end])
            let enriched = await withTaskGroup(of: StoreLibraryGame.self, returning: [StoreLibraryGame].self) { group in
                for game in chunk {
                    group.addTask { [session, compatibilityLoader] in
                        async let metadataRequest = Self.fetchMetadata(appID: game.appID, session: session)
                        async let compatibilityRequest = compatibilityLoader.profile(appID: game.appID)
                        let (metadata, compatibility) = await (metadataRequest, compatibilityRequest)
                        return StoreLibraryGame(
                            provider: .steam,
                            externalID: game.appID,
                            name: metadata?.name ?? game.name ?? "Steam App \(game.appID)",
                            developer: metadata?.developer ?? game.developer,
                            publisher: metadata?.publisher,
                            releaseDate: metadata?.releaseDate,
                            genres: metadata?.genres,
                            features: metadata?.features,
                            summary: metadata?.summary ?? game.summary,
                            artworkPath: game.artworkPath,
                            portraitImageURL: metadata?.portraitImageURL,
                            headerImageURL: metadata?.headerImageURL,
                            backgroundImageURL: metadata?.backgroundImageURL,
                            screenshotURLs: metadata?.screenshotURLs,
                            videos: metadata?.videos,
                            storeRating: metadata?.rating,
                            supportsWindows: metadata?.supportsWindows,
                            supportsNativeMacOS: metadata?.supportsNativeMacOS,
                            playtimeMinutes: game.playtimeMinutes,
                            lastPlayed: game.lastPlayed,
                            isInstalled: game.isInstalled,
                            installPath: game.installPath,
                            storageBytes: game.storageBytes,
                            sizeEstimate: metadata?.sizeEstimate,
                            compatibility: compatibility,
                            websiteURL: metadata?.websiteURL,
                            supportURL: metadata?.supportURL,
                            minimumSystemRequirements: metadata?.minimumSystemRequirements,
                            recommendedSystemRequirements: metadata?.recommendedSystemRequirements,
                            currentBuildID: game.buildID,
                            achievements: metadata?.achievements,
                            achievementCount: metadata?.achievementCount,
                            patchNotes: metadata?.patchNotes
                        )
                    }
                }
                var values: [StoreLibraryGame] = []
                for await value in group { values.append(value) }
                return values
            }
            results.append(contentsOf: enriched)
        }

        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func loadDetails(for game: StoreLibraryGame) async -> StoreLibraryGame {
        guard game.provider == .steam else { return game }
        async let metadataRequest = Self.fetchMetadata(appID: game.externalID, session: session)
        async let compatibilityRequest = compatibilityLoader.profile(appID: game.externalID)
        let (metadata, compatibility) = await (metadataRequest, compatibilityRequest)
        guard let metadata else {
            var value = game
            value.compatibility = compatibility ?? value.compatibility
            return value
        }

        var value = game
        value.name = metadata.name ?? value.name
        value.developer = metadata.developer ?? value.developer
        value.publisher = metadata.publisher ?? value.publisher
        value.releaseDate = metadata.releaseDate ?? value.releaseDate
        value.genres = metadata.genres?.isEmpty == false ? metadata.genres : value.genres
        value.features = metadata.features?.isEmpty == false ? metadata.features : value.features
        value.summary = metadata.summary ?? value.summary
        value.portraitImageURL = metadata.portraitImageURL ?? value.portraitImageURL
        value.headerImageURL = metadata.headerImageURL ?? value.headerImageURL
        value.backgroundImageURL = metadata.backgroundImageURL ?? value.backgroundImageURL
        value.screenshotURLs = metadata.screenshotURLs?.isEmpty == false ? metadata.screenshotURLs : value.screenshotURLs
        value.videos = metadata.videos?.isEmpty == false ? metadata.videos : value.videos
        value.storeRating = metadata.rating ?? value.storeRating
        value.supportsWindows = metadata.supportsWindows ?? value.supportsWindows
        value.supportsNativeMacOS = metadata.supportsNativeMacOS ?? value.supportsNativeMacOS
        value.sizeEstimate = metadata.sizeEstimate ?? value.sizeEstimate
        value.compatibility = compatibility ?? value.compatibility
        value.websiteURL = metadata.websiteURL ?? value.websiteURL
        value.supportURL = metadata.supportURL ?? value.supportURL
        value.minimumSystemRequirements = metadata.minimumSystemRequirements ?? value.minimumSystemRequirements
        value.recommendedSystemRequirements = metadata.recommendedSystemRequirements ?? value.recommendedSystemRequirements
        value.achievements = metadata.achievements ?? value.achievements
        value.achievementCount = metadata.achievementCount ?? value.achievementCount
        value.patchNotes = metadata.patchNotes ?? value.patchNotes
        return value
    }

    func loadCurrentPlayerCount(appID: String) async -> Int? {
        guard !appID.isEmpty, appID.allSatisfy(\.isNumber),
              var components = URLComponents(string: "https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "appid", value: appID)]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(CurrentPlayersResponse.self, from: data),
              payload.response.result == 1,
              let playerCount = payload.response.playerCount,
              playerCount >= 0 else {
            return nil
        }
        return playerCount
    }

    private func signedInUserDirectories() throws -> [URL] {
        let loginURL = steamRoot.appending(path: "config/loginusers.vdf")
        guard fileManager.fileExists(atPath: loginURL.path) else { return [] }
        let users = (try? ValveKeyValueDecoder.decode(url: loginURL).object("users")) ?? [:]
        let userdata = steamRoot.appending(path: "userdata", directoryHint: .isDirectory)
        let directories = (try? fileManager.contentsOfDirectory(
            at: userdata,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let candidates = directories.filter { directory in
            fileManager.fileExists(atPath: directory.appending(path: "config/localconfig.vdf").path)
        }
        let accountIDs = Set(users.keys.compactMap { steamID -> String? in
            guard let value = UInt64(steamID), value >= 76_561_197_960_265_728 else { return nil }
            return String(value - 76_561_197_960_265_728)
        })
        guard !accountIDs.isEmpty else { return candidates }
        let matched = candidates.filter { accountIDs.contains($0.lastPathComponent) }
        return matched.isEmpty ? candidates : matched
    }

    private func mergeUserLibrary(at userDirectory: URL, into games: inout [String: LocalGame]) throws {
        let localConfigURL = userDirectory.appending(path: "config/localconfig.vdf")
        guard let root = try? ValveKeyValueDecoder.decode(url: localConfigURL),
              let apps = root.object(path: ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"]) else {
            return
        }
        for (appID, value) in apps where appID.allSatisfy(\.isNumber) {
            var game = games[appID] ?? LocalGame(appID: appID)
            if let object = value.objectValue {
                game.playtimeMinutes = max(game.playtimeMinutes, Int(object.string("Playtime") ?? "") ?? 0)
                if let seconds = TimeInterval(object.string("LastPlayed") ?? ""), seconds > 0 {
                    game.lastPlayed = max(game.lastPlayed ?? .distantPast, Date(timeIntervalSince1970: seconds))
                }
            }
            mergeCachedDetails(appID: appID, userDirectory: userDirectory, into: &game)
            let cover = steamRoot.appending(path: "appcache/librarycache/\(appID)/library_600x900.jpg")
            if fileManager.fileExists(atPath: cover.path) { game.artworkPath = cover.path }
            games[appID] = game
        }
    }

    private func mergeCachedDetails(appID: String, userDirectory: URL, into game: inout LocalGame) {
        let url = userDirectory.appending(path: "config/librarycache/\(appID).json")
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return }
        for row in rows where row.count == 2 {
            guard let key = row[0] as? String,
                  let wrapper = row[1] as? [String: Any],
                  let payload = wrapper["data"] as? [String: Any] else { continue }
            if key == "descriptions" {
                game.summary = (payload["strSnippet"] as? String) ?? (payload["strFullDescription"] as? String)
            } else if key == "associations" {
                let developers = payload["rgDevelopers"] as? [[String: Any]]
                game.developer = developers?.first?["strName"] as? String
            }
        }
    }

    private func mergeInstalledGames(into games: inout [String: LocalGame]) throws {
        let defaultSteamApps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
        var steamAppsDirectories = [defaultSteamApps]
        let foldersURL = defaultSteamApps.appending(path: "libraryfolders.vdf")
        if let root = try? ValveKeyValueDecoder.decode(url: foldersURL),
           let folders = root.object("libraryfolders") {
            for value in folders.values {
                guard let path = value.objectValue?.string("path"), !path.isEmpty else { continue }
                let candidate = URL(fileURLWithPath: path).appending(path: "steamapps", directoryHint: .isDirectory)
                if !steamAppsDirectories.contains(candidate) { steamAppsDirectories.append(candidate) }
            }
        }

        for steamApps in steamAppsDirectories where fileManager.fileExists(atPath: steamApps.path) {
            let manifests = (try? fileManager.contentsOfDirectory(at: steamApps, includingPropertiesForKeys: nil)) ?? []
            for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                guard let root = try? ValveKeyValueDecoder.decode(url: manifest),
                      let state = root.object("AppState"),
                      let appID = state.string("appid") else { continue }
                var game = games[appID] ?? LocalGame(appID: appID)
                game.name = state.string("name") ?? game.name
                game.isInstalled = true
                if let value = state.string("SizeOnDisk"), let bytes = Int64(value), bytes > 0 {
                    game.storageBytes = bytes
                }
                game.buildID = state.string("buildid")
                if let installDirectory = state.string("installdir") {
                    let installationURL = steamApps.appending(path: "common/\(installDirectory)", directoryHint: .isDirectory)
                    game.installPath = installationURL.path
                    if game.storageBytes == nil {
                        game.storageBytes = GameStorage.allocatedSize(of: installationURL)
                    }
                }
                let cover = steamRoot.appending(path: "appcache/librarycache/\(appID)/library_600x900.jpg")
                if fileManager.fileExists(atPath: cover.path) { game.artworkPath = cover.path }
                games[appID] = game
            }
        }
    }

    private static func fetchMetadata(appID: String, session: URLSession) async -> StoreMetadata? {
        guard var components = URLComponents(string: "https://store.steampowered.com/api/appdetails") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "appids", value: appID),
            URLQueryItem(name: "l", value: Locale.current.language.languageCode?.identifier ?? "en")
        ]
        guard let url = components.url else { return nil }
        async let detailsRequest = session.data(from: url)
        async let reviewsRequest = fetchReviewRating(appID: appID, session: session)
        async let newsRequest = fetchPatchNotes(appID: appID, session: session)
        guard let (data, response) = try? await detailsRequest,
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelope = root[appID] as? [String: Any],
              envelope["success"] as? Bool == true,
              let details = envelope["data"] as? [String: Any] else { return nil }
        let developers = details["developers"] as? [String]
        let publishers = details["publishers"] as? [String]
        let genres = (details["genres"] as? [[String: Any]])?.compactMap { $0["description"] as? String }
        let categories = (details["categories"] as? [[String: Any]])?.compactMap { $0["description"] as? String }
        let releaseDate = (details["release_date"] as? [String: Any])?["date"] as? String
        let supportURL = (details["support_info"] as? [String: Any])?["url"] as? String
        let platforms = details["platforms"] as? [String: Bool]
        let preferredPlatform: StoreGameInstallationPlatform = platforms?["mac"] == true ? .nativeMacOS : .windows
        let requirementsKey = preferredPlatform == .nativeMacOS ? "mac_requirements" : "pc_requirements"
        let requirements = details[requirementsKey] as? [String: Any]
        let requirementBytes = storeRequirementBytes(from: details[requirementsKey])
        let requirementArchitecture = StoreArchitectureInference.fromSystemRequirements(details[requirementsKey])
        let screenshots = (details["screenshots"] as? [[String: Any]])?.compactMap {
            ($0["path_full"] as? String) ?? ($0["path_thumbnail"] as? String)
        }
        let movies = (details["movies"] as? [[String: Any]])?.compactMap { movie -> StoreVideo? in
            guard let id = movie["id"],
                  let name = movie["name"] as? String else { return nil }
            let legacyFormats = movie["mp4"] as? [String: Any]
            guard let videoURL = (movie["hls_h264"] as? String)
                ?? (legacyFormats?["max"] as? String)
                ?? (legacyFormats?["480"] as? String)
                ?? (movie["dash_h264"] as? String) else { return nil }
            return StoreVideo(
                id: String(describing: id),
                name: name,
                thumbnailURL: movie["thumbnail"] as? String,
                videoURL: videoURL
            )
        }
        let reviewRating = await reviewsRequest
        let patchNotes = await newsRequest
        let achievementPayload = details["achievements"] as? [String: Any]
        let highlightedAchievements = (achievementPayload?["highlighted"] as? [[String: Any]])?.compactMap { item -> StoreAchievement? in
            guard let name = item["name"] as? String else { return nil }
            return StoreAchievement(
                id: (item["path"] as? String) ?? name,
                name: name,
                description: nil,
                iconURL: item["path"] as? String
            )
        }
        let criticScore = (details["metacritic"] as? [String: Any])?["score"] as? Int
        var rating = reviewRating
        if rating == nil, criticScore != nil { rating = StoreRating(criticScore: criticScore) }
        else if criticScore != nil { rating?.criticScore = criticScore }
        return StoreMetadata(
            name: details["name"] as? String,
            developer: developers?.first ?? publishers?.first,
            publisher: publishers?.first,
            releaseDate: releaseDate,
            genres: genres,
            features: categories,
            summary: cleanDescription(details["short_description"] as? String),
            portraitImageURL: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(appID)/library_600x900_2x.jpg",
            headerImageURL: details["header_image"] as? String,
            backgroundImageURL: (details["background_raw"] as? String) ?? (details["background"] as? String),
            screenshotURLs: screenshots,
            videos: movies,
            rating: rating,
            supportsWindows: platforms?["windows"],
            supportsNativeMacOS: platforms?["mac"],
            sizeEstimate: (requirementBytes != nil || requirementArchitecture != nil) ?
                StoreGameSizeEstimate(
                    installedBytes: requirementBytes,
                    source: .steamStoreRequirement,
                    platform: preferredPlatform,
                    executableArchitecture: requirementArchitecture
                )
                : nil,
            websiteURL: details["website"] as? String,
            supportURL: supportURL,
            minimumSystemRequirements: cleanDescription(requirements?["minimum"] as? String),
            recommendedSystemRequirements: cleanDescription(requirements?["recommended"] as? String),
            achievements: highlightedAchievements,
            achievementCount: achievementPayload?["total"] as? Int,
            patchNotes: patchNotes
        )
    }

    private static func fetchPatchNotes(appID: String, session: URLSession) async -> [StorePatchNote]? {
        guard var components = URLComponents(string: "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "appid", value: appID),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(name: "maxlength", value: "0"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let appNews = root["appnews"] as? [String: Any],
              let items = appNews["newsitems"] as? [[String: Any]] else { return nil }
        let values = items.compactMap { item -> StorePatchNote? in
            guard let id = item["gid"], let title = item["title"] as? String,
                  let timestamp = item["date"] as? TimeInterval else { return nil }
            return StorePatchNote(
                id: String(describing: id), title: title,
                publishedAt: Date(timeIntervalSince1970: timestamp), url: item["url"] as? String
            )
        }
        return values.isEmpty ? nil : values
    }

    static func storeRequirementBytes(from value: Any?) -> Int64? {
        guard let requirements = value as? [String: Any] else { return nil }
        let candidates = [requirements["minimum"], requirements["recommended"]]
            .compactMap { $0 as? String }
            .compactMap(requirementBytes)
        return candidates.max()
    }

    private static func requirementBytes(in html: String) -> Int64? {
        let plain = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let pattern = #"(?i)(?:storage|disk space|miejsce na dysku|pamięć masowa)\s*:?\s*([0-9]+(?:[.,][0-9]+)?)\s*(TB|GB|MB)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: plain, range: NSRange(plain.startIndex..., in: plain)),
              let amountRange = Range(match.range(at: 1), in: plain),
              let unitRange = Range(match.range(at: 2), in: plain),
              let amount = Double(plain[amountRange].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let multiplier: Double
        switch plain[unitRange].uppercased() {
        case "TB": multiplier = 1_000_000_000_000
        case "GB": multiplier = 1_000_000_000
        default: multiplier = 1_000_000
        }
        let bytes = amount * multiplier
        guard bytes > 0, bytes <= Double(Int64.max) else { return nil }
        return Int64(bytes.rounded())
    }

    private static func fetchReviewRating(appID: String, session: URLSession) async -> StoreRating? {
        guard var components = URLComponents(string: "https://store.steampowered.com/appreviews/\(appID)") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "language", value: "all"),
            URLQueryItem(name: "purchase_type", value: "all"),
            URLQueryItem(name: "num_per_page", value: "0")
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = root["query_summary"] as? [String: Any] else { return nil }
        let positive = summary["total_positive"] as? Int ?? 0
        let negative = summary["total_negative"] as? Int ?? 0
        let total = summary["total_reviews"] as? Int ?? positive + negative
        let percent = total > 0 ? Int((Double(positive) / Double(total) * 100).rounded()) : nil
        return StoreRating(
            positivePercent: percent,
            reviewCount: total > 0 ? total : nil,
            label: summary["review_score_desc"] as? String
        )
    }

    private static func cleanDescription(_ value: String?) -> String? {
        guard var value, !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private func numericAppID(_ value: String) -> Int64 { Int64(value) ?? .max }
}

nonisolated enum ValveKeyValue: Sendable {
    case string(String)
    case object([String: ValveKeyValue])

    var objectValue: [String: ValveKeyValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    func object(_ key: String) -> [String: ValveKeyValue]? { objectValue?[key]?.objectValue }
    func string(_ key: String) -> String? {
        guard case .string(let value) = objectValue?[key] else { return nil }
        return value
    }
    func object(path: [String]) -> [String: ValveKeyValue]? {
        path.reduce(objectValue) { partial, key in partial?[key]?.objectValue }
    }
}

nonisolated enum ValveKeyValueDecoder {
    private enum Token { case value(String), open, close }

    static func decode(url: URL) throws -> ValveKeyValue {
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = Parser(tokens: tokenize(text))
        return .object(parser.parseObject(stopsAtClose: false))
    }

    private static func tokenize(_ text: String) -> [Token] {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                index += 2
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            }
            if character == "{" { tokens.append(.open); index += 1; continue }
            if character == "}" { tokens.append(.close); index += 1; continue }
            if character == "\"" {
                index += 1
                var value = ""
                while index < characters.count {
                    let next = characters[index]
                    if next == "\"" { index += 1; break }
                    if next == "\\", index + 1 < characters.count {
                        let escaped = characters[index + 1]
                        if escaped == "\"" || escaped == "\\" { value.append(escaped); index += 2; continue }
                    }
                    value.append(next)
                    index += 1
                }
                tokens.append(.value(value))
                continue
            }
            var value = ""
            while index < characters.count, !characters[index].isWhitespace, characters[index] != "{", characters[index] != "}" {
                value.append(characters[index])
                index += 1
            }
            if !value.isEmpty { tokens.append(.value(value)) }
        }
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0

        mutating func parseObject(stopsAtClose: Bool) -> [String: ValveKeyValue] {
            var result: [String: ValveKeyValue] = [:]
            while index < tokens.count {
                if case .close = tokens[index] {
                    index += 1
                    if stopsAtClose { return result }
                    continue
                }
                guard case .value(let key) = tokens[index] else { index += 1; continue }
                index += 1
                guard index < tokens.count else { break }
                switch tokens[index] {
                case .value(let value):
                    result[key] = .string(value)
                    index += 1
                case .open:
                    index += 1
                    result[key] = .object(parseObject(stopsAtClose: true))
                case .close:
                    index += 1
                }
            }
            return result
        }
    }
}

nonisolated extension Dictionary where Key == String, Value == ValveKeyValue {
    func string(_ key: String) -> String? {
        guard case .string(let value) = self[key] else { return nil }
        return value
    }
}
