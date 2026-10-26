import Foundation

actor DrakensangSteamLauncher {
    static let shared = DrakensangSteamLauncher()
    nonisolated static let appID = "2067850"
    private var preparing = false

    nonisolated static func applies(to url: URL) -> Bool {
        url.scheme == "steam" && url.host == "rungameid" && url.path == "/\(appID)"
    }

    nonisolated static func preferredRuntime(in runtimes: [InstalledRuntime]) -> InstalledRuntime? {
        // This is the host verified with this game's CoreAudio and D3D9 path.
        // Selecting another Wine host silently would reintroduce missing sound.
        runtimes.first {
            $0.architecture == .x86_64 && $0.resolvedEngine == .gamePortingToolkit && $0.wineVersion == "3.0-2"
                && FileManager.default.isExecutableFile(atPath: $0.wineExecutable.path)
        }
    }

    nonisolated static func steamWine(installation: SteamOnM1Wine.Installation) throws -> URL {
        let text = try String(
            contentsOf: installation.appURL.appending(path: "Contents/MacOS/launcher"), encoding: .utf8)
        let prefix = "export WINE_APP=\""
        guard let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix(prefix) }),
            line.hasSuffix("\"")
        else {
            throw DrakensangLaunchError.unavailable(
                "Reinstall the Steam on M1 Wine app so Boreal can identify Steam's Wine runtime.")
        }
        let path = String(line.dropFirst(prefix.count).dropLast())
        guard path.hasPrefix("/"), !path.contains("$"), !path.contains("`"), !path.contains("\0"), !path.contains("\"")
        else {
            throw DrakensangLaunchError.unavailable("Steam's Wine runtime path could not be identified safely.")
        }
        let wine = URL(fileURLWithPath: path).appending(path: "Contents/Resources/wine/bin/wine")
        guard FileManager.default.isExecutableFile(atPath: wine.path) else {
            throw DrakensangLaunchError.unavailable(
                "Steam's Wine runtime is unavailable. Reconnect its volume and try again.")
        }
        return wine
    }

    func open(installation: SteamOnM1Wine.Installation, runtime: InstalledRuntime, root: URL) async throws {
        guard !preparing else { return }
        preparing = true
        defer { preparing = false }
        guard let game = SteamOnM1Wine.installedGameDirectory(appID: Self.appID) else {
            throw SteamWindowsError.gameNotInstalled(Self.appID)
        }
        guard let launcher = Bundle.main.url(forResource: "BorealDrakensangLauncher", withExtension: nil),
            let helper = Bundle.main.url(forResource: "BorealDrakensangTicket", withExtension: "exe"),
            let cursor = Bundle.main.url(forResource: "BorealDrakensangCursor", withExtension: "dll")
        else {
            throw DrakensangLaunchError.unavailable(
                "Drakensang's compatibility components are missing from Boreal. Reinstall Boreal and try again.")
        }
        let wine = try Self.steamWine(installation: installation)
        var wineApp = wine
        for _ in 0..<5 { wineApp.deleteLastPathComponent() }
        // Retain upstream's CEF-wrapper repair and validated Steam flags.
        // The generated app can select a Wine host outside /Applications.
        try await SteamOnM1Wine.open(URL(string: "steam://openmain")!, wineAppURL: wineApp)
        let arguments = [
            "--root", root.path, "--steam-prefix", installation.prefixURL.path,
            "--steam-wine", wine.path, "--game-wine", runtime.wineExecutable.path,
            "--game-root", game.path, "--ticket-helper", helper.path,
            "--cursor-library", cursor.path, "--runtime-id", runtime.id,
        ]
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = launcher
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            WineProcessEnvironment.removeInheritedRuntimeConfiguration(from: &environment)
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            // The native controller closes this pipe after startup, while it
            // continues owning the game/Steam ticket independently of Boreal.
            let response = pipe.fileHandleForReading.readDataToEndOfFile()
            try? pipe.fileHandleForReading.close()
            guard String(data: response, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "READY"
            else {
                let message = String(data: response, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "ERROR: ", with: "")
                throw DrakensangLaunchError.unavailable(
                    message?.isEmpty == false ? message! : "Drakensang's game controller could not start.")
            }
        }.value
    }
}
