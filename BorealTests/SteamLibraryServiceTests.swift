import Foundation
import Testing
@testable import Boreal

@Suite(.serialized)
struct SteamLibraryServiceTests {
    @Test func importsSignedInLibraryMetadataArtworkPlaytimeAndInstallState() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BorealSteamTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeDirectory(root.appending(path: "config"))
        try makeDirectory(root.appending(path: "userdata/1234/config"))
        try makeDirectory(root.appending(path: "appcache/librarycache/730"))
        try makeDirectory(root.appending(path: "steamapps/common/Counter-Strike Global Offensive"))

        try write("""
        "users" { "76561197960266962" { "AccountName" "not-read-by-boreal" } }
        """, to: root.appending(path: "config/loginusers.vdf"))
        try write("""
        "UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" {
            "730" { "LastPlayed" "1700000000" "Playtime" "120" }
        } } } } }
        """, to: root.appending(path: "userdata/1234/config/localconfig.vdf"))
        try write("""
        "libraryfolders" { "0" { "path" "\(root.path)" } }
        """, to: root.appending(path: "steamapps/libraryfolders.vdf"))
        try write("""
        "AppState" { "appid" "730" "name" "Local Name" "installdir" "Counter-Strike Global Offensive" }
        """, to: root.appending(path: "steamapps/appmanifest_730.acf"))
        try Data([0xFF, 0xD8, 0xFF]).write(to: root.appending(path: "appcache/librarycache/730/library_600x900.jpg"))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SteamMetadataURLProtocol.self]
        SteamMetadataURLProtocol.responseData = Data("""
        {"730":{"success":true,"data":{"name":"Counter-Strike 2","developers":["Valve"],"short_description":"A &amp; B <b>game</b>","header_image":"https://example.com/header.jpg","background_raw":"https://example.com/background.jpg","platforms":{"windows":true,"mac":false},"metacritic":{"score":82},"screenshots":[{"path_full":"https://example.com/shot.jpg"}],"movies":[{"id":7,"name":"Trailer","thumbnail":"https://example.com/trailer.jpg","hls_h264":"https://example.com/trailer.m3u8"}]}}}
        """.utf8)
        let service = SteamLibraryService(steamRoot: root, session: URLSession(configuration: configuration))

        let games = try await service.loadLibrary()

        #expect(games.count == 1)
        let game = try #require(games.first)
        #expect(game.externalID == "730")
        #expect(game.name == "Counter-Strike 2")
        #expect(game.developer == "Valve")
        #expect(game.summary == "A & B game")
        #expect(game.playtimeMinutes == 120)
        #expect(game.lastPlayed == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(game.isInstalled)
        #expect(game.installPath?.hasSuffix("Counter-Strike Global Offensive") == true)
        #expect(game.artworkPath?.hasSuffix("library_600x900.jpg") == true)
        #expect(game.backgroundImageURL == "https://example.com/background.jpg")
        #expect(game.screenshotURLs == ["https://example.com/shot.jpg"])
        #expect(game.videos?.first?.videoURL == "https://example.com/trailer.m3u8")
        #expect(game.storeRating?.positivePercent == 90)
        #expect(game.storeRating?.reviewCount == 100)
        #expect(game.storeRating?.criticScore == 82)
        #expect(game.supportsWindows == true)
        #expect(game.supportsNativeMacOS == false)
        #expect(game.compatibility?.tier == .gold)
        #expect(game.compatibility?.trendingTier == .platinum)
        #expect(game.compatibility?.reportCount == 2_029)
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func write(_ value: String, to url: URL) throws {
        try Data(value.utf8).write(to: url)
    }
}

private nonisolated final class SteamMetadataURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data: Data
        if request.url?.path.contains("/reports/summaries/") == true {
            data = Data("""
            {"bestReportedTier":"platinum","confidence":"strong","score":0.71,"tier":"gold","total":2029,"trendingTier":"platinum"}
            """.utf8)
        } else if request.url?.path.contains("/appreviews/") == true {
            data = Data("""
            {"query_summary":{"review_score_desc":"Very Positive","total_positive":90,"total_negative":10,"total_reviews":100}}
            """.utf8)
        } else {
            data = Self.responseData
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
