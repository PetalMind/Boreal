import Foundation
import Testing
@testable import Boreal

@Suite(.serialized)
struct SteamWindowsServiceTests {
    @Test func buildsSteamClientLaunchPlans() {
        let steam = URL(fileURLWithPath: "/tmp/Steam/steam.exe")
        let play = SteamWindowsService.playPlan(appID: "606880", steamExecutable: steam)
        #expect(play.executable == steam)
        #expect(play.arguments == ["-applaunch", "606880"])
        #expect(play.workingDirectory == steam.deletingLastPathComponent())

        let bootstrap = SteamWindowsService.bootstrapPlan(steamExecutable: steam)
        #expect(bootstrap.arguments == ["-silent"])
    }

    @Test func findsInstalledWindowsSteamGameFromManifest() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BorealSteamClientTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appending(path: "prefix", directoryHint: .isDirectory)
        let steamRoot = prefix.appending(path: "drive_c/Program Files (x86)/Steam", directoryHint: .isDirectory)
        let game = steamRoot.appending(path: "steamapps/common/Example Game", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        let manifest = steamRoot.appending(path: "steamapps/appmanifest_606880.acf")
        try Data("\"AppState\" { \"appid\" \"606880\" \"installdir\" \"Example Game\" }".utf8).write(to: manifest)

        let environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "Steam for Windows"),
            runtimeID: "runtime",
            rootURL: root,
            prefixURL: prefix,
            logsURL: root.appending(path: "Logs"),
            state: .ready
        )
        #expect(SteamWindowsService.installedGameDirectory(appID: "606880", in: environment) == game)
        #expect(SteamWindowsService.installedGameDirectory(appID: "not-an-app", in: environment) == nil)
    }
}
