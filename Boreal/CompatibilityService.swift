import Foundation

nonisolated protocol ProtonCompatibilityLoading: Sendable {
    func profile(appID: String) async -> CommunityCompatibility?
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
