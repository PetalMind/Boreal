import Foundation

nonisolated protocol ProtonCompatibilityLoading: Sendable {
    func profile(appID: String) async -> CommunityCompatibility?
}

nonisolated protocol CommunityCompatibilityLoading: Sendable {
    func profile(for game: StoreLibraryGame) async -> CommunityCompatibility?
}

actor ProtonStoreCompatibilityService: CommunityCompatibilityLoading {
    private struct SearchResponse: Decodable {
        struct Item: Decodable { let id: Int; let name: String }
        let items: [Item]
    }

    private struct DetailsResponse: Decodable {
        struct Payload: Decodable {
            let name: String
            let developers: [String]?
            let publishers: [String]?
        }
        let success: Bool
        let data: Payload?
    }

    private let session: URLSession
    private let proton: any ProtonCompatibilityLoading
    private var cachedProfiles: [String: CommunityCompatibility] = [:]
    private var missingProfiles: Set<String> = []

    init(session: URLSession = .shared) {
        self.session = session
        proton = ProtonCompatibilityService(session: session)
    }

    func profile(for game: StoreLibraryGame) async -> CommunityCompatibility? {
        let key = "\(game.provider.rawValue)|\(game.externalID)|\(Self.normalized(game.name))"
        if let cached = cachedProfiles[key] { return cached }
        if missingProfiles.contains(key) { return nil }

        let appID: String?
        if game.provider == .steam, game.externalID.allSatisfy(\.isNumber) {
            appID = game.externalID
        } else {
            appID = await resolveSteamAppID(for: game)
        }
        guard let appID, var profile = await proton.profile(appID: appID) else {
            missingProfiles.insert(key)
            return nil
        }
        profile.sourceURL = "https://www.protondb.com/app/\(appID)"
        profile.platform = "Linux / Proton"
        cachedProfiles[key] = profile
        return profile
    }

    private func resolveSteamAppID(for game: StoreLibraryGame) async -> String? {
        guard var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: game.name),
            URLQueryItem(name: "l", value: "english"),
            URLQueryItem(name: "cc", value: "US")
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let search = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
        let normalizedName = Self.normalized(game.name)
        let exact = search.items.filter { Self.normalized($0.name) == normalizedName }
        guard !exact.isEmpty else { return nil }
        if exact.count == 1 { return String(exact[0].id) }
        guard let expectedDeveloper = game.developer, !Self.normalized(expectedDeveloper).isEmpty else { return nil }
        var verified: [Int] = []
        for candidate in exact.prefix(5) {
            if await matchesDeveloper(candidate.id, expected: expectedDeveloper, normalizedName: normalizedName) {
                verified.append(candidate.id)
            }
        }
        return verified.count == 1 ? String(verified[0]) : nil
    }

    private func matchesDeveloper(_ appID: Int, expected: String, normalizedName: String) async -> Bool {
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=english&cc=US"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONDecoder().decode([String: DetailsResponse].self, from: data),
              let result = root[String(appID)], result.success, let details = result.data,
              Self.normalized(details.name) == normalizedName else { return false }
        let expectedValue = Self.normalized(expected)
        return (details.developers ?? [])
            .map(Self.normalized)
            .contains(expectedValue)
            || (details.publishers ?? []).map(Self.normalized).contains(expectedValue)
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        return folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { result, character in
                if character != " " || result.last != " " { result.append(character) }
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor ProtonCompatibilityService: ProtonCompatibilityLoading {
    private struct Response: Decodable {
        let bestReportedTier: String?
        let confidence: String?
        let score: Double?
        let tier: String?
        let total: Int?
        let trendingTier: String?
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func profile(appID: String) async -> CommunityCompatibility? {
        guard appID.allSatisfy(\.isNumber),
              let url = URL(string: "https://www.protondb.com/api/v1/reports/summaries/\(appID).json"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(Response.self, from: data),
              let tier = Self.tier(payload.tier) else { return nil }
        return CommunityCompatibility(
            source: .protonDB,
            tier: tier,
            trendingTier: Self.tier(payload.trendingTier),
            bestReportedTier: Self.tier(payload.bestReportedTier),
            confidence: payload.confidence,
            score: payload.score,
            reportCount: payload.total ?? 0,
            fetchedAt: .now
        )
    }

    private static func tier(_ value: String?) -> CompatibilityTier? {
        guard let value else { return nil }
        return CompatibilityTier(rawValue: value.lowercased()) ?? .unknown
    }
}
