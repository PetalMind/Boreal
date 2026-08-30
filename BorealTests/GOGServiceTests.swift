import Foundation
import Testing
@testable import Boreal

@Suite(.serialized)
struct GOGServiceTests {
    @Test func collapsesPromotionalDuplicateIntoRichCanonicalRelease() {
        let canonical = StoreLibraryGame(
            provider: .gog,
            externalID: "100",
            name: "Example Game",
            developer: "Studio",
            portraitImageURL: "https://example.com/cover.jpg",
            screenshotURLs: ["https://example.com/shot.jpg"],
            supportsWindows: true
        )
        let promotion = StoreLibraryGame(
            provider: .gog,
            externalID: "200",
            name: "Example Game - Amazon Prime",
            summary: "Promotional entitlement",
            supportsWindows: false
        )
        let distinctEdition = StoreLibraryGame(
            provider: .gog,
            externalID: "300",
            name: "Example Game: Definitive Edition"
        )

        let result = GOGReleaseNormalizer.deduplicate([promotion, distinctEdition, canonical])

        #expect(result.count == 2)
        let merged = result.first { $0.name == "Example Game" }
        #expect(merged?.externalID == "100")
        #expect(merged?.portraitImageURL == canonical.portraitImageURL)
        #expect(merged?.screenshotURLs == canonical.screenshotURLs)
        #expect(merged?.supportsWindows == true)
        #expect(result.contains { $0.name == distinctEdition.name })
    }

    @Test func retainsStandalonePromotionalReleaseWhenNoCanonicalReleaseExists() {
        let promotion = StoreLibraryGame(provider: .gog, externalID: "200", name: "Only Game - Amazon Luna")

        let result = GOGReleaseNormalizer.deduplicate([promotion])

        #expect(result == [promotion])
    }

    @Test func collapsesCanonicalReleasesWithTheSameNormalizedName() throws {
        let canonical = StoreLibraryGame(
            provider: .gog,
            externalID: "100",
            name: "Cyberpunk 2077",
            developer: "CD PROJEKT RED"
        )
        var installedDuplicate = StoreLibraryGame(
            provider: .gog,
            externalID: "200",
            name: "Cyberpunk 2077",
            developer: "CD PROJEKT RED",
            portraitImageURL: "https://example.com/cyberpunk.jpg"
        )
        installedDuplicate.isInstalled = true
        installedDuplicate.installPath = "/Games/Cyberpunk 2077"

        let result = GOGReleaseNormalizer.deduplicate([installedDuplicate, canonical])

        let merged = try #require(result.first)
        #expect(result.count == 1)
        #expect(merged.externalID == installedDuplicate.externalID)
        #expect(merged.name == canonical.name)
        #expect(merged.developer == canonical.developer)
        #expect(merged.portraitImageURL == installedDuplicate.portraitImageURL)
        #expect(merged.isInstalled)
    }

    @Test func authenticatesImportsRichPaginatedLibraryInstallsAndBuildsContainedLaunchPlan() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BorealGOGTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appending(path: "Tools/GOGDL/1.3.0/gogdl")
        let account = root.appending(path: "Accounts/GOG")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        try Data(Self.helperScript.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GOGURLProtocol.self]
        let service = GOGService(applicationSupportURL: root, session: URLSession(configuration: configuration))

        let displayName = try await service.authenticate(authorizationCode: "https://embed.gog.com/on_login_success?origin=client&code=one-time-code")
        #expect(displayName == "Boreal GOG Player")
        #expect(await service.connectionState() == .connected(displayName: "Boreal GOG Player"))

        let games = try await service.loadLibrary()
        #expect(games.count == 2)
        let game = try #require(games.first(where: { $0.externalID == "12345" }))
        #expect(game.provider == .gog)
        #expect(game.name == "Boreal GOG Game")
        #expect(game.developer == "Example Studio")
        #expect(game.summary == "A rich GOG library item")
        #expect(game.portraitImageURL == "https://images.example/portrait.jpg")
        #expect(game.backgroundImageURL == "https://images.example/background.jpg")
        #expect(game.screenshotURLs == ["https://images.example/screenshot.jpg"])
        #expect(game.storeRating?.criticScore == 88)
        #expect(game.supportsWindows == true)
        #expect(game.supportsNativeMacOS == false)
        #expect(!game.isInstalled)

        let size = try #require(try await service.loadSizeEstimate(appID: game.externalID, platform: .windows))
        #expect(size.downloadBytes == 4_500_000_000)
        #expect(size.installedBytes == 7_500_000_000)
        #expect(size.source == .gogManifest)
        #expect(size.buildID == "gog-build-42")

        try await service.install(appID: game.externalID) { _ in }
        let refreshed = try await service.loadLibrary()
        let installed = try #require(refreshed.first(where: { $0.externalID == game.externalID }))
        #expect(installed.isInstalled)
        #expect(installed.installPath?.hasSuffix("Games/GOG/12345") == true)

        let runtime = InstalledRuntime(
            id: "test-runtime",
            displayName: "Test Runtime",
            wineVersion: "test",
            rootURL: root.appending(path: "Runtime"),
            wineExecutable: root.appending(path: "Runtime/wine"),
            wineServerExecutable: root.appending(path: "Runtime/wineserver"),
            wineBootExecutable: root.appending(path: "Runtime/wineboot"),
            architecture: .x86_64,
            requirements: []
        )
        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "GOG"),
            runtimeID: runtime.id,
            rootURL: root.appending(path: "Environment"),
            prefixURL: root.appending(path: "Environment/prefix"),
            logsURL: root.appending(path: "Environment/Logs"),
            state: .ready
        )
        let plan = try await service.launchPlan(appID: game.externalID, runtime: runtime, environment: environment)
        #expect(plan.executable.path.hasSuffix("Games/GOG/12345/bin/BorealGame.exe"))
        #expect(plan.arguments == ["-windowed", "player one"])
        #expect(plan.workingDirectory.path.hasSuffix("Games/GOG/12345/bin"))

        let outside = root.appending(path: "outside.exe")
        try Data().write(to: outside)
        try FileManager.default.removeItem(at: plan.executable)
        try FileManager.default.createSymbolicLink(at: plan.executable, withDestinationURL: outside)
        await #expect(throws: GOGServiceError.self) {
            _ = try await service.launchPlan(appID: game.externalID, runtime: runtime, environment: environment)
        }
    }

    @Test func requestsNativeMacOSArtifactWhenSelected() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BorealGOGNativeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appending(path: "Tools/GOGDL/1.3.0/gogdl")
        let account = root.appending(path: "Accounts/GOG")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        try Data(Self.helperScript.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let service = GOGService(applicationSupportURL: root)
        _ = try await service.authenticate(authorizationCode: "native-test")

        let games = root.appending(path: "Games")
        try await service.install(appID: "12345", destinationRoot: games, platform: .nativeMacOS) { _ in }

        let arguments = try String(contentsOf: account.appending(path: "download-args.txt"), encoding: .utf8)
        #expect(arguments.contains("--platform osx"))
        let installation = await service.installationURL(
            appID: "12345",
            destinationRoot: games,
            platform: .nativeMacOS
        )
        #expect(installation?.lastPathComponent == "Boreal Native Game.app")
    }

    @Test func acceptsNestedGOGDLWindowsInstallationAndResolvesItsRealDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BorealGOGNestedTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appending(path: "Tools/GOGDL/1.3.0/gogdl")
        let account = root.appending(path: "Accounts/GOG")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        try Data(Self.nestedHelperScript.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let service = GOGService(applicationSupportURL: root)
        _ = try await service.authenticate(authorizationCode: "nested-test")
        let games = root.appending(path: "Games")

        try await service.install(appID: "1088641408", destinationRoot: games, platform: .windows) { _ in }

        let installation = await service.installationURL(appID: "1088641408", destinationRoot: games, platform: .windows)
        #expect(installation?.lastPathComponent == "18 Wheels of Steel Hard Truck")

        let runtime = InstalledRuntime(
            id: "test-runtime",
            displayName: "Test Runtime",
            wineVersion: "test",
            rootURL: root.appending(path: "Runtime"),
            wineExecutable: root.appending(path: "Runtime/wine"),
            wineServerExecutable: root.appending(path: "Runtime/wineserver"),
            wineBootExecutable: root.appending(path: "Runtime/wineboot"),
            architecture: .x86_64,
            requirements: []
        )
        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "GOG"),
            runtimeID: runtime.id,
            rootURL: root.appending(path: "Environment"),
            prefixURL: root.appending(path: "Environment/prefix"),
            logsURL: root.appending(path: "Environment/Logs"),
            state: .ready
        )
        let container = games.appending(path: "1088641408", directoryHint: .isDirectory)
        let plan = try await service.launchPlan(
            appID: "1088641408",
            installationURL: container,
            runtime: runtime,
            environment: environment
        )
        #expect(plan.executable.lastPathComponent == "Hard Truck 18 Wheels of Steel.exe")
    }

    private static let helperScript = #"""
    #!/bin/sh
    auth_path="$2"
    command="$3"
    if [ "$command" = "auth" ]; then
      if [ "$4" = "--code" ]; then
        printf '{}' > "$auth_path"
      fi
      printf '%s\n' '{"access_token":"private-test-token","user_id":"998877"}'
      exit 0
    fi
    if [ "$command" = "download" ]; then
      printf '%s\n' "$*" > "$(dirname "$auth_path")/download-args.txt"
      destination="$6"
      if [ "$8" = "osx" ]; then
        mkdir -p "$destination/Boreal Native Game.app/Contents/MacOS"
        : > "$destination/Boreal Native Game.app/Contents/MacOS/BorealGame"
        exit 0
      fi
      mkdir -p "$destination/bin"
      : > "$destination/bin/BorealGame.exe"
      printf '%s\n' '{"playTasks":[{"isPrimary":true,"type":"FileTask","path":"bin\\BorealGame.exe","workingDir":"bin","arguments":"-windowed \"player one\""}]}' > "$destination/goggame-$4.info"
      exit 0
    fi
    if [ "$command" = "info" ]; then
      printf '%s\n' '{"size":{"*":{"download_size":4000000000,"disk_size":7000000000},"en-US":{"download_size":500000000,"disk_size":500000000}},"buildId":"gog-build-42"}'
      exit 0
    fi
    exit 64
    """#

    private static let nestedHelperScript = #"""
    #!/bin/sh
    auth_path="$2"
    command="$3"
    if [ "$command" = "auth" ]; then
      if [ "$4" = "--code" ]; then
        printf '{}' > "$auth_path"
      fi
      printf '%s\n' '{"access_token":"private-test-token","user_id":"998877"}'
      exit 0
    fi
    if [ "$command" = "download" ]; then
      destination="$6/18 Wheels of Steel Hard Truck"
      mkdir -p "$destination"
      : > "$destination/Hard Truck 18 Wheels of Steel.exe"
      printf '%s\n' '{"playTasks":[{"category":"launcher","isPrimary":true,"path":"Hard Truck 18 Wheels of Steel.exe","type":"FileTask"}]}' > "$destination/goggame-$4.info"
      exit 0
    fi
    exit 64
    """#
}

private nonisolated final class GOGURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let data: Data
        if url.host == "users.gog.com" {
            data = Data(#"{"username":"Boreal GOG Player"}"#.utf8)
        } else if url.host == "galaxy-library.gog.com", URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "page_token" }) == true {
            data = Data(#"{"items":[{"platform_id":"gog","external_id":"67890","certificate":"second-cert"}]}"#.utf8)
        } else if url.host == "galaxy-library.gog.com" {
            data = Data(#"{"items":[{"platform_id":"gog","external_id":"12345","certificate":"first-cert"},{"platform_id":"other","external_id":"0"}],"next_page_token":"next"}"#.utf8)
        } else if url.path.hasSuffix("/12345") {
            data = Data(#"{"title":{"*":"Boreal GOG Game"},"summary":{"*":"A rich GOG library item"},"supported_operating_systems":[{"slug":"windows"}],"game":{"title":{"*":"Boreal GOG Game"},"developers":[{"name":"Example Studio"}],"aggregated_rating":{"score":88},"vertical_cover":{"url_format":"https://images.example/portrait.{ext}"},"logo":{"url_format":"https://images.example/wide.{ext}"},"background":{"url_format":"https://images.example/background.{ext}"},"screenshots":[{"url_format":"https://images.example/screenshot.{ext}"}]}}"#.utf8)
        } else {
            data = Data(#"{"title":{"*":"Second GOG Game"},"summary":{"*":"Second item"},"supported_operating_systems":[{"slug":"windows"},{"slug":"osx"}],"game":{"title":{"*":"Second GOG Game"},"developers":[],"vertical_cover":{"url_format":"https://images.example/second.{ext}"}}}"#.utf8)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
