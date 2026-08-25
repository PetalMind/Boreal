import Foundation
import Testing
@testable import Boreal

@Suite(.serialized)
struct LegendaryEpicServiceTests {
    @Test func readsConnectedAccountAndImportsEpicLibraryWithInstalledStateAndArtwork() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BorealEpicTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appending(path: "Tools/Legendary/0.21.0/legendary")
        let accountDirectory = root.appending(path: "Accounts/Epic")
        let gameDirectory = root.appending(path: "Games/Boreal Epic Game", directoryHint: .isDirectory)
        let executable = gameDirectory.appending(path: "BorealGame.exe")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: accountDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        try Data().write(to: executable)
        try Data("{\"displayName\":\"Boreal Player\"}".utf8).write(to: accountDirectory.appending(path: "user.json"))
        try Data(Self.helperScript(gameDirectory: gameDirectory).utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        let service = LegendaryEpicService(applicationSupportURL: root)
        #expect(await service.connectionState() == .connected(displayName: "Boreal Player"))

        let games = try await service.loadLibrary()

        #expect(games.count == 1)
        let game = try #require(games.first)
        #expect(game.provider == .epic)
        #expect(game.externalID == "BorealEpicApp")
        #expect(game.name == "Boreal Epic Game")
        #expect(game.developer == "Example Studio")
        #expect(game.summary == "A real Epic library item")
        #expect(game.portraitImageURL == "https://example.com/portrait.jpg")
        #expect(game.headerImageURL == "https://example.com/header.jpg")
        #expect(game.screenshotURLs == ["https://example.com/screenshot.jpg"])
        #expect(game.supportsWindows == true)
        #expect(game.supportsNativeMacOS == false)
        #expect(game.isInstalled)
        #expect(game.installPath == gameDirectory.path)

        try await service.install(appID: "BorealEpicApp") { _ in }
        let installArguments = try String(contentsOf: accountDirectory.appending(path: "install-args.txt"), encoding: .utf8)
        #expect(installArguments.contains("install BorealEpicApp"))
        #expect(installArguments.contains("--platform Windows"))
        #expect(installArguments.contains("--skip-dlcs"))

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
            configuration: EnvironmentConfiguration(name: "Epic"),
            runtimeID: runtime.id,
            rootURL: root.appending(path: "Environment"),
            prefixURL: root.appending(path: "Environment/prefix"),
            logsURL: root.appending(path: "Environment/Logs"),
            state: .ready
        )
        let plan = try await service.launchPlan(appID: "BorealEpicApp", runtime: runtime, environment: environment)
        #expect(plan.executable == executable.resolvingSymlinksInPath())
        #expect(plan.arguments == ["-windowed", "-epicusername=player"])
        #expect(plan.environment["EOS_USE_ANTICHEATCLIENTNULL"] == "1")
        #expect(plan.environment["WINEPREFIX"] == nil)
        #expect(plan.workingDirectory == gameDirectory.resolvingSymlinksInPath())

        let outsideExecutable = root.appending(path: "Outside.exe")
        try Data().write(to: outsideExecutable)
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: outsideExecutable)
        var rejectedEscapingExecutable = false
        do {
            _ = try await service.launchPlan(appID: "BorealEpicApp", runtime: runtime, environment: environment)
        } catch LegendaryEpicError.invalidLaunchPlan {
            rejectedEscapingExecutable = true
        }
        #expect(rejectedEscapingExecutable)
    }

    private static func helperScript(gameDirectory: URL) -> String { #"""
    #!/bin/sh
    if [ "$1" = "-y" ]; then
      printf '%s\n' "$*" > "$LEGENDARY_CONFIG_PATH/install-args.txt"
      exit 0
    fi
    if [ "$1" = "list-installed" ]; then
      printf '%s\n' '[{"app_name":"BorealEpicApp","install_path":"\#(gameDirectory.path)"}]'
      exit 0
    fi
    if [ "$1" = "list" ]; then
      printf '%s\n' '[{"app_name":"BorealEpicApp","app_title":"Boreal Epic Game","metadata":{"developer":"Example Studio","description":"A real Epic library item","releaseInfo":[{"platform":["Windows"]}],"keyImages":[{"type":"DieselStoreFrontTall","url":"https://example.com/portrait.jpg"},{"type":"DieselGameBox","url":"https://example.com/header.jpg"},{"type":"Screenshot","url":"https://example.com/screenshot.jpg"}]}}]'
      exit 0
    fi
    if [ "$1" = "launch" ]; then
      printf '{"game_parameters":["-windowed"],"game_executable":"BorealGame.exe","game_directory":"\#(gameDirectory.path)","egl_parameters":["-epicusername=player"],"launch_command":["%s"],"working_directory":"\#(gameDirectory.path)","user_parameters":[],"environment":{"WINEPREFIX":"/unsafe","PATH":"/unsafe","EOS_USE_ANTICHEATCLIENTNULL":"1"},"pre_launch_command":""}\n' "$5"
      exit 0
    fi
    exit 64
    """# }
}
