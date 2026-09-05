import Foundation

nonisolated struct ITADPrice: Codable, Hashable, Sendable {
    let amount: Double
    let amountInt: Int?
    let currency: String

    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = .current
        return formatter.string(from: amount as NSNumber) ?? "\(amount) \(currency)"
    }
}

nonisolated struct ITADShop: Codable, Hashable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct ITADNamedValue: Codable, Hashable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct ITADOffer: Codable, Hashable, Sendable, Identifiable {
    let shop: ITADShop
    let price: ITADPrice
    let regular: ITADPrice?
    let cut: Int?
    let storeLow: ITADPrice?
    let drm: [ITADNamedValue]
    let platforms: [ITADNamedValue]
    let timestamp: Date
    let expiry: Date?
    let url: String

    var id: String { "\(shop.id)-\(url)" }
    var discountLabel: String? { cut.map { "-\($0)%" }.flatMap { $0 == "-0%" ? nil : $0 } }
}

nonisolated struct ITADHistoricalDeal: Codable, Hashable, Sendable {
    let shop: ITADShop
    let price: ITADPrice
    let regular: ITADPrice?
    let cut: Int?
    let timestamp: Date
}

nonisolated struct ITADPriceHistoryPoint: Codable, Hashable, Sendable, Identifiable {
    let timestamp: Date
    let shop: ITADShop
    let deal: ITADHistoricalDeal

    var id: String { "\(timestamp.timeIntervalSince1970)-\(shop.id)" }
}

nonisolated struct DiscoveryPriceSummary: Hashable, Sendable {
    let itadGameID: String
    var bestOffer: ITADOffer?
    var historicalLow: ITADHistoricalDeal?
    var offers: [ITADOffer] = []
    let fetchedAt: Date

    var dealQuality: DiscoveryDealQuality? {
        guard let current = bestOffer?.price,
              let low = historicalLow?.price,
              current.currency == low.currency,
              low.amount > 0 else { return nil }
        switch current.amount / low.amount {
        case ...1.10: return .great
        case ...1.35: return .nearHistoricalLow
        case ...2.0: return .average
        default: return .poor
        }
    }
}

nonisolated enum DiscoveryDealQuality: String, Hashable, Sendable {
    case great
    case nearHistoricalLow
    case average
    case poor

    var title: String {
        switch self {
        case .great: "Great price"
        case .nearHistoricalLow: "Near historical low"
        case .average: "Average price"
        case .poor: "Poor deal"
        }
    }

    var symbol: String {
        switch self {
        case .great, .nearHistoricalLow: "checkmark.circle.fill"
        case .average: "minus.circle.fill"
        case .poor: "exclamationmark.triangle.fill"
        }
    }
}

nonisolated enum DiscoveryPriceHistoryRange: String, CaseIterable, Hashable, Sendable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"

    var since: Date? {
        switch self {
        case .threeMonths: Calendar.current.date(byAdding: .month, value: -3, to: .now)
        case .sixMonths: Calendar.current.date(byAdding: .month, value: -6, to: .now)
        case .year: Calendar.current.date(byAdding: .year, value: -1, to: .now)
        case .all: nil
        }
    }
}

nonisolated protocol DiscoveryPricingLoading: Sendable {
    func loadOverview(for game: AppleGamingWikiGame) async -> DiscoveryPriceSummary?
    func loadOffers(for itadGameID: String) async -> [ITADOffer]?
    func loadHistory(for itadGameID: String, since: Date?) async -> [ITADPriceHistoryPoint]?
}

actor ITADPriceService: DiscoveryPricingLoading {
    static let apiKeyDefaultsKey = "itadAPIKey"
    static let countryCodeDefaultsKey = "itadCountryCode"
    static let steamShopID = 61
    private static let baseURL = URL(string: "https://api.isthereanydeal.com")!

    private struct PriceOverviewResponse: Decodable {
        let prices: [PriceOverviewEntry]
    }

    private struct PriceOverviewEntry: Decodable {
        let id: String
        let current: ITADOffer?
        let lowest: ITADHistoricalDeal?
    }

    private struct PriceListEntry: Decodable {
        let id: String
        let deals: [ITADOffer]
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static var isConfigured: Bool {
        let value = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? ProcessInfo.processInfo.environment["ITAD_API_KEY"]
        return !((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func loadOverview(for game: AppleGamingWikiGame) async -> DiscoveryPriceSummary? {
        guard let id = await resolveGameID(for: game), let response: PriceOverviewResponse = await post(
            [id],
            endpoint: "/games/overview/v2"
        ), let entry = response.prices.first(where: { $0.id == id }) else { return nil }
        return DiscoveryPriceSummary(
            itadGameID: id,
            bestOffer: entry.current,
            historicalLow: entry.lowest,
            fetchedAt: .now
        )
    }

    func loadOffers(for itadGameID: String) async -> [ITADOffer]? {
        guard let response: [PriceListEntry] = await post(
            [itadGameID],
            endpoint: "/games/prices/v3"
        ) else { return nil }
        return response.first(where: { $0.id == itadGameID })?.deals ?? []
    }

    func loadHistory(for itadGameID: String, since: Date?) async -> [ITADPriceHistoryPoint]? {
        guard var components = URLComponents(
            url: Self.baseURL.appending(path: "/games/history/v2"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "id", value: itadGameID),
            URLQueryItem(name: "country", value: countryCode)
        ]
        if let since {
            let formatter = ISO8601DateFormatter()
            components.queryItems?.append(.init(name: "since", value: formatter.string(from: since)))
        }
        guard let url = components.url, let data = await requestData(url: url, method: "GET") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ITADPriceHistoryPoint].self, from: data)
    }

    private func resolveGameID(for game: AppleGamingWikiGame) async -> String? {
        if let steamAppID = game.steamAppID {
            let steamStoreID = "app/\(steamAppID)"
            if let mapping: [String: String?] = await post([steamStoreID], endpoint: "/lookup/id/shop/\(Self.steamShopID)/v1"),
               let id = mapping[steamStoreID] ?? nil {
                return id
            }
        }
        let mapping: [String: String?]? = await post([game.title], endpoint: "/lookup/id/title/v1")
        return mapping?[game.title] ?? nil
    }

    private func post<Request: Encodable, Response: Decodable>(_ body: Request, endpoint: String) async -> Response? {
        guard let apiKey = configuredAPIKey,
              let url = URL(string: endpoint, relativeTo: Self.baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "ITAD-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = body
        guard let data = await requestData(request: request) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Response.self, from: data)
    }

    private func requestData(url: URL, method: String) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(configuredAPIKey, forHTTPHeaderField: "ITAD-API-Key")
        return await requestData(request: request)
    }

    private func requestData(request: URLRequest) async -> Data? {
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private var configuredAPIKey: String? {
        let stored = UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey)
        let value = stored ?? ProcessInfo.processInfo.environment["ITAD_API_KEY"]
        let key = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    private var countryCode: String {
        let configured = UserDefaults.standard.string(forKey: Self.countryCodeDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let configured, configured.count == 2 { return configured }
        return Locale.current.region?.identifier ?? "PL"
    }
}
