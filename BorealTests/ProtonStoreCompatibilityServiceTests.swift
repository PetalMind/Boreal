import Foundation
import Testing
@testable import Boreal

@Suite(.serialized)
struct ProtonStoreCompatibilityServiceTests {
    @Test func resolvesExactStoreTitleAndLoadsProtonRating() async throws {
        ProtonStoreURLProtocol.responses = [
            "/api/storesearch/": #"{"total":1,"items":[{"id":1091500,"name":"Cyberpunk 2077"}]}"#,
            "/api/v1/reports/summaries/1091500.json": #"{"bestReportedTier":"platinum","confidence":"strong","score":0.88,"tier":"gold","total":2048,"trendingTier":"gold"}"#
        ]
        let service = makeService()
        let game = StoreLibraryGame(provider: .gog, externalID: "1423049311", name: "Cyberpunk 2077")

        let profile = try #require(await service.profile(for: game))

        #expect(profile.source == .protonDB)
        #expect(profile.tier == .gold)
        #expect(profile.reportCount == 2_048)
        #expect(profile.sourceURL == "https://www.protondb.com/app/1091500")
    }

    @Test func refusesPartialOrAmbiguousStoreMatches() async {
        ProtonStoreURLProtocol.responses = [
            "/api/storesearch/": #"{"total":2,"items":[{"id":1,"name":"DOOM"},{"id":2,"name":"DOOM"}]}"#
        ]
        let service = makeService()
        let partial = StoreLibraryGame(provider: .epic, externalID: "partial", name: "DOO")
        let ambiguous = StoreLibraryGame(provider: .epic, externalID: "ambiguous", name: "DOOM")

        #expect(await service.profile(for: partial) == nil)
        #expect(await service.profile(for: ambiguous) == nil)
    }

    @Test func usesDeveloperToResolveDuplicateExactTitles() async throws {
        ProtonStoreURLProtocol.responses = [
            "/api/storesearch/": #"{"total":2,"items":[{"id":10,"name":"The Game"},{"id":20,"name":"The Game"}]}"#,
            "/api/appdetails?appids=10": #"{"10":{"success":true,"data":{"name":"The Game","developers":["Other Studio"],"publishers":[]}}}"#,
            "/api/appdetails?appids=20": #"{"20":{"success":true,"data":{"name":"The Game","developers":["Right Studio"],"publishers":[]}}}"#,
            "/api/v1/reports/summaries/20.json": #"{"tier":"platinum","total":12}"#
        ]
        let service = makeService()
        let game = StoreLibraryGame(
            provider: .gog,
            externalID: "duplicate",
            name: "The Game",
            developer: "Right Studio"
        )

        #expect(await service.profile(for: game)?.tier == .platinum)
    }

    private func makeService() -> ProtonStoreCompatibilityService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProtonStoreURLProtocol.self]
        return ProtonStoreCompatibilityService(session: URLSession(configuration: configuration))
    }
}

private nonisolated final class ProtonStoreURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let absolute = request.url?.absoluteString ?? ""
        let path = request.url?.path ?? ""
        let match = Self.responses.first { key, _ in absolute.contains(key) || path.contains(key) }
        let status = match == nil ? 404 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((match?.value ?? "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
