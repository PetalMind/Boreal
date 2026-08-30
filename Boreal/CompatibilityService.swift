import Foundation

nonisolated protocol ProtonCompatibilityLoading: Sendable {
    func profile(appID: String) async -> CommunityCompatibility?
}

nonisolated protocol CommunityCompatibilityLoading: Sendable {
    func profile(named applicationName: String) async -> CommunityCompatibility?
}

actor CodeWeaversCompatibilityService: CommunityCompatibilityLoading {
    private let session: URLSession
    private var cachedProfiles: [String: CommunityCompatibility] = [:]
    private var missingProfiles: Set<String> = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    func profile(named applicationName: String) async -> CommunityCompatibility? {
        let key = Self.normalized(applicationName)
        guard !key.isEmpty else { return nil }
        if let cached = cachedProfiles[key] { return cached }
        if missingProfiles.contains(key) { return nil }

        guard var components = URLComponents(string: "https://www.codeweavers.com/compatibility") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "name", value: applicationName),
            URLQueryItem(name: "search", value: "app")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Boreal/1.0 macOS compatibility lookup", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8),
              let match = Self.exactMatch(in: html, normalizedName: key) else {
            missingProfiles.insert(key)
            return nil
        }

        let profile = CommunityCompatibility(
            source: .codeWeavers,
            tier: Self.tier(forStars: match.stars),
            confidence: "macOS rating",
            score: Double(match.stars),
            reportCount: 0,
            fetchedAt: .now,
            sourceURL: "https://www.codeweavers.com\(match.path)",
            platform: "macOS",
            sourceUpdatedAt: match.updatedAt
        )
        cachedProfiles[key] = profile
        return profile
    }

    private struct Match {
        let path: String
        let stars: Int
        let updatedAt: Date?
    }

    private static func exactMatch(in html: String, normalizedName: String) -> Match? {
        let pattern = #"(?s)<tr\b[^>]*>(.*?)</tr>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let fullRange = NSRange(html.startIndex..., in: html)
        let rows = expression.matches(in: html, range: fullRange).compactMap { result -> Match? in
            guard let range = Range(result.range(at: 1), in: html) else { return nil }
            return match(inRow: String(html[range]), normalizedName: normalizedName)
        }
        return rows.count == 1 ? rows[0] : nil
    }

    private static func match(inRow row: String, normalizedName: String) -> Match? {
        let linkPattern = #"<a\s+href=\"(/compatibility/crossover/[^\"]+)\"[^>]*>(.*?)</a>"#
        guard let expression = try? NSRegularExpression(pattern: linkPattern, options: [.dotMatchesLineSeparators]),
              let result = expression.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)),
              let pathRange = Range(result.range(at: 1), in: row),
              let nameRange = Range(result.range(at: 2), in: row),
              normalized(stripMarkup(String(row[nameRange]))) == normalizedName else { return nil }
        let stars = row.components(separatedBy: #"<li class="active">"#).count - 1
        guard (1...5).contains(stars) else { return nil }
        return Match(path: String(row[pathRange]), stars: stars, updatedAt: updatedDate(in: row))
    }

    private static func updatedDate(in row: String) -> Date? {
        let pattern = #"\b(\d{4}-\d{2}-\d{2})\s+\d{2}:\d{2}\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)),
              let range = Range(result.range(at: 1), in: row) else { return nil }
        return try? Date(String(row[range]), strategy: .iso8601.year().month().day())
    }

    private static func tier(forStars stars: Int) -> CompatibilityTier {
        switch stars {
        case 5: .runsGreat
        case 4: .runsWell
        case 3: .limitedFunctionality
        case 2: .installsButDoesNotRun
        default: .willNotInstall
        }
    }

    private static func stripMarkup(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&trade;", with: "™")
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
