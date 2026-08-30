import Foundation
import Testing
@testable import Boreal

@Suite(.serialized)
struct CodeWeaversCompatibilityServiceTests {
    @Test func loadsExactMacRatingAndSourceDetails() async throws {
        let service = makeService(html: """
        <table id="teTable-app"><tbody>
        <tr id="key_16940">
          <td><a href="/compatibility/crossover/cyberpunk-2077">Cyberpunk 2077</a></td>
          <td>CD Projekt Red</td><td>2026-01-15 09:36</td>
          <td><ul class="star-rating-table">
            <li class="active"></li><li class="active"></li><li class="active"></li><li class="active"></li><li class="active"></li>
          </ul></td>
        </tr>
        </tbody></table>
        """)

        let profile = try #require(await service.profile(named: "Cyberpunk 2077"))

        #expect(profile.source == .codeWeavers)
        #expect(profile.platform == "macOS")
        #expect(profile.tier == .runsGreat)
        #expect(profile.tier.rating == .excellent)
        #expect(profile.score == 5)
        #expect(profile.sourceURL == "https://www.codeweavers.com/compatibility/crossover/cyberpunk-2077")
        #expect(profile.sourceUpdatedAt != nil)
    }

    @Test func refusesPartialAndAmbiguousTitleMatches() async {
        let service = makeService(html: """
        <table><tbody>
          \(row(name: "DOOM", path: "doom", stars: 5))
          \(row(name: "DOOM Eternal", path: "doom-eternal", stars: 4))
        </tbody></table>
        """)

        #expect(await service.profile(named: "DOOM")?.tier == .runsGreat)
        #expect(await service.profile(named: "DOOM Eterna") == nil)
    }

    @Test func mapsOfficialFiveStarScale() async throws {
        for (stars, expected) in [
            (1, CompatibilityTier.willNotInstall),
            (2, .installsButDoesNotRun),
            (3, .limitedFunctionality),
            (4, .runsWell),
            (5, .runsGreat)
        ] {
            let service = makeService(html: "<table><tbody>\(row(name: "Test \(stars)", path: "test-\(stars)", stars: stars))</tbody></table>")
            #expect(await service.profile(named: "Test \(stars)")?.tier == expected)
        }
    }

    private func makeService(html: String) -> CodeWeaversCompatibilityService {
        CodeWeaversURLProtocol.html = html
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodeWeaversURLProtocol.self]
        return CodeWeaversCompatibilityService(session: URLSession(configuration: configuration))
    }

    private func row(name: String, path: String, stars: Int) -> String {
        let rating = String(repeating: #"<li class="active"></li>"#, count: stars)
        return #"<tr><td><a href="/compatibility/crossover/\#(path)">\#(name)</a></td><td>2026-08-25 12:00</td><td><ul>\#(rating)</ul></td></tr>"#
    }
}

private nonisolated final class CodeWeaversURLProtocol: URLProtocol {
    nonisolated(unsafe) static var html = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.html.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
