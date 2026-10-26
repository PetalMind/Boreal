import CryptoKit
import Darwin
import Foundation

/// A separate native process owns the game and its Steam ticket. Closing
/// Boreal must not cancel a ticket while the game is still running.
@main
struct DrakensangLauncher {
    static let fm = FileManager.default

    static func main() async {
        umask(0o077)
        do { try await run() } catch {
            let message =
                (error as? DrakensangLaunchError)?.errorDescription
                ?? "Drakensang could not start. Check its installed files and reconnect the game volume."
            print("ERROR: " + message)
            exit(1)
        }
    }

    static func run() async throws {
        let values = Array(CommandLine.arguments.dropFirst())
        guard values.count == 16 else { throw failure("Drakensang's launch configuration is incomplete.") }
        var config: [String: String] = [:]
        for i in stride(from: 0, to: values.count, by: 2) { config[values[i]] = values[i + 1] }
        func path(_ key: String) throws -> URL {
            guard let value = config[key], value.hasPrefix("/") else {
                throw failure("Drakensang's launch configuration is invalid.")
            }
            return URL(fileURLWithPath: value)
        }
        let root = try path("--root")
        let steamPrefix = try path("--steam-prefix")
        let steamWine = try path("--steam-wine")
        let gameWine = try path("--game-wine")
        let gameRoot = try path("--game-root")
        let helper = try path("--ticket-helper")
        let cursor = try path("--cursor-library")
        guard let runtimeID = config["--runtime-id"], !runtimeID.isEmpty else {
            throw failure("Select the compatible Drakensang runtime.")
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = open(root.appending(path: "launch.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw failure("Drakensang's launch folder is unavailable.") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            ready()
            return
        }
        let client = gameRoot.appending(path: "DSOClient/dlcache/dro_client64.exe")
        let steamAPI = gameRoot.appending(path: "steam_api.dll")
        for file in [client, steamAPI, steamWine, gameWine, helper, cursor] {
            guard fm.isReadableFile(atPath: file.path) else {
                throw failure(
                    "Drakensang's game files or compatibility components are missing. Reconnect the game volume or repair the installation."
                )
            }
        }
        let runtimeReceipt = root.appending(path: "runtime-id.txt")
        if let pinned = try? String(contentsOf: runtimeReceipt, encoding: .utf8), pinned != runtimeID {
            throw failure(
                "Drakensang's environment belongs to another runtime. Restore that runtime before starting the game.")
        }
        var environment = ProcessInfo.processInfo.environment
        for key in [
            "WINEARCH", "WINEPREFIX", "WINESERVER", "WINELOADER", "WINEDLLPATH", "WINEDLLDIR", "WINEESYNC", "WINEMSYNC",
            "WINEDLLOVERRIDES", "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES",
            "DYLD_FRAMEWORK_PATH", "WINE_D3D_CONFIG", "WINED3D_RENDERER", "DXVK_CONFIG_FILE", "VK_ICD_FILENAMES",
            "MTL_HUD_ENABLED",
        ] {
            environment.removeValue(forKey: key)
        }
        environment["WINEDEBUG"] = "-all"
        let prefix = root.appending(path: "prefix")
        var gameEnvironment = environment
        gameEnvironment["WINEPREFIX"] = prefix.path
        gameEnvironment["WINEDLLOVERRIDES"] = "d3d9=n,b;gameoverlayrenderer,gameoverlayrenderer64=d"
        try preparePrefix(
            prefix, wine: gameWine, environment: gameEnvironment, receipt: runtimeReceipt, runtimeID: runtimeID)
        try prepareSettings(prefix: prefix)
        try deployCursor(
            cursor, target: client.deletingLastPathComponent().appending(path: "d3d9.dll"),
            receipt: root.appending(path: "cursor.sha256"))

        var steamEnvironment = environment
        steamEnvironment["WINEPREFIX"] = steamPrefix.path
        steamEnvironment["SteamAppId"] = "2067850"
        steamEnvironment["SteamGameId"] = "2067850"
        steamEnvironment["WINEDLLOVERRIDES"] = "gameoverlayrenderer,gameoverlayrenderer64=d"
        let steam = steamPrefix.appending(path: "drive_c/Program Files (x86)/Steam/Steam.exe")
        guard fm.isReadableFile(atPath: steam.path) else {
            throw failure("Open Steam and sign in before starting Drakensang.")
        }
        let bootstrap = try start(
            wine: steamWine,
            arguments: [steam.path, "-silent", "-no-cef-sandbox", "-cef-single-process", "-noverifyfiles"],
            environment: steamEnvironment,
            directory: steam.deletingLastPathComponent())
        // Steam can perform an update before its API becomes available. Retry
        // sign-in initialization, without launching the broken Qt launcher.
        let done = root.appending(path: "ticket-\(UUID().uuidString).done")
        var ticketProcess: Process?
        defer {
            try? Data().write(to: done)
            if let ticketProcess { finishTicket(ticketProcess) }
            try? fm.removeItem(at: done)
            _ = bootstrap
        }
        var ticket: Data?
        let signInDeadline = Date().addingTimeInterval(75)
        while Date() < signInDeadline {
            let pipe = Pipe()
            let process = try start(
                wine: steamWine,
                arguments: [helper.path, windowsPath(steamAPI), windowsPath(done)],
                environment: steamEnvironment, directory: steamAPI.deletingLastPathComponent(), output: pipe)
            let data = try readTicket(pipe: pipe, process: process, timeout: 22)
            if let data {
                ticket = data
                ticketProcess = process
                break
            }
            if process.isRunning { process.terminate() }
            try await Task.sleep(for: .seconds(2))
        }
        guard let ticket else {
            throw failure(
                "Drakensang could not connect to the signed-in Steam account. Finish signing in to Steam, then click Play again."
            )
        }
        let arguments = try await DrakensangPortal().launchArguments(ticket: ticket)
        let game = try start(
            wine: gameWine, arguments: [client.path] + arguments,
            environment: gameEnvironment, directory: client.deletingLastPathComponent())
        try await Task.sleep(for: .seconds(2))
        guard game.isRunning else {
            throw failure("Drakensang closed during startup. Repair the installed game files and try again.")
        }
        ready()
        game.waitUntilExit()
    }

    static func ready() {
        print("READY")
        fflush(stdout)
        try? FileHandle.standardOutput.close()
    }

    static func failure(_ message: String) -> DrakensangLaunchError { .unavailable(message) }
    static func windowsPath(_ url: URL) -> String { "Z:" + url.path.replacingOccurrences(of: "/", with: "\\") }

    static func finishTicket(_ process: Process) {
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
    }

    static func start(
        wine: URL, arguments: [String], environment: [String: String], directory: URL, output: Pipe? = nil
    ) throws -> Process {
        let process = Process()
        process.executableURL = wine
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output ?? FileHandle.nullDevice as Any
        // The game prints its full command line, including the ephemeral SID.
        // Never store that output in Boreal logs or diagnostics.
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    static func readTicket(pipe: Pipe, process: Process, timeout: TimeInterval) throws -> Data? {
        let handle = pipe.fileHandleForReading
        defer { try? handle.close() }
        let fd = handle.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else {
            throw failure("Could not create the private Steam sign-in channel.")
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                result.append(contentsOf: buffer.prefix(count))
            } else if count == 0 || (!process.isRunning && count < 0) {
                break
            } else if errno != EAGAIN && errno != EINTR {
                break
            }
            if result.count >= 4 {
                let size = result.prefix(4).enumerated().reduce(UInt32(0)) {
                    $0 | (UInt32($1.element) << ($1.offset * 8))
                }
                guard size > 0, size <= 4096 else { return nil }
                if result.count == 4 + Int(size) { return Data(result.dropFirst(4)) }
                if result.count > 4 + Int(size) { return nil }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    static func preparePrefix(_ prefix: URL, wine: URL, environment: [String: String], receipt: URL, runtimeID: String)
        throws
    {
        if fm.fileExists(atPath: prefix.appending(path: "system.reg").path) {
            guard fm.fileExists(atPath: receipt.path) else {
                throw failure("Drakensang's existing environment could not be verified. Its files were preserved.")
            }
            return
        }
        guard !fm.fileExists(atPath: prefix.path) else {
            throw failure("Drakensang's environment is incomplete. Its existing files were preserved.")
        }
        let staging = prefix.deletingLastPathComponent().appending(path: ".prefix-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var setup = environment
        setup["WINEPREFIX"] = staging.path
        setup.removeValue(forKey: "WINEDLLOVERRIDES")
        let server = wine.deletingLastPathComponent().appending(path: "wineserver")
        var stopped = false
        defer {
            if !stopped { stopped = stopStagingPrefix(server: server, environment: setup, directory: staging) }
            // An unconfirmed shutdown leaves the staging files intact.
            if stopped { try? fm.removeItem(at: staging) }
        }
        let boot = try start(wine: wine, arguments: ["wineboot.exe", "-u"], environment: setup, directory: staging)
        let deadline = Date().addingTimeInterval(90)
        while boot.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if boot.isRunning {
            boot.terminate()
            throw failure("Preparing Drakensang's environment timed out. Try Play again.")
        }
        guard boot.terminationStatus == 0,
            ["system.reg", "user.reg", "drive_c", "dosdevices"].allSatisfy({
                fm.fileExists(atPath: staging.appending(path: $0).path)
            })
        else {
            throw failure("Could not prepare Drakensang's compatible environment.")
        }
        // Stop only this staging prefix before publishing it under its stable path.
        stopped = stopStagingPrefix(server: server, environment: setup, directory: staging)
        guard stopped else {
            throw failure(
                "Drakensang's environment is still finishing setup. Its files were preserved; try Play again.")
        }
        try runtimeID.write(to: receipt, atomically: true, encoding: .utf8)
        try fm.moveItem(at: staging, to: prefix)
    }

    static func stopStagingPrefix(server: URL, environment: [String: String], directory: URL) -> Bool {
        for argument in ["-k", "-w"] {
            guard
                let process = try? start(
                    wine: server, arguments: [argument], environment: environment, directory: directory)
            else { return false }
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning {
                process.terminate()
                return false
            }
            if process.terminationStatus != 0 { return false }
        }
        return true
    }

    static func prepareSettings(prefix: URL) throws {
        let users = prefix.appending(path: "drive_c/users")
        for user in try fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil) {
            let temp = user.appending(path: "Temp")
            guard fm.fileExists(atPath: temp.path) else { continue }
            let directory = temp.appending(path: "DSOClient")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appending(path: "settings.xml")
            let document: XMLDocument
            if fm.fileExists(atPath: file.path) {
                document = try XMLDocument(contentsOf: file, options: .nodeLoadExternalEntitiesNever)
            } else {
                document = try XMLDocument(
                    xmlString:
                        "<Settings><Audio enabled=\"true\" effectVolume=\"1.000000\" musicVolume=\"1.000000\" languageVolume=\"1.000000\" masterVolume=\"1.000000\"/></Settings>",
                    options: [])
            }
            guard let root = document.rootElement() else { throw failure("Drakensang's settings could not be read.") }
            let cursor = root.elements(forName: "Cursor").first ?? XMLElement(name: "Cursor")
            if cursor.parent == nil { root.addChild(cursor) }
            cursor.removeAttribute(forName: "classiccursor")
            cursor.addAttribute(XMLNode.attribute(withName: "classiccursor", stringValue: "false") as! XMLNode)
            try document.xmlData(options: .nodePrettyPrint).write(to: file, options: .atomic)
        }
    }

    static func deployCursor(_ source: URL, target: URL, receipt: URL) throws {
        let desired = try Data(contentsOf: source)
        func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let targetInfo = try? fm.attributesOfItem(atPath: target.path)
        if let targetInfo, targetInfo[.type] as? FileAttributeType != .typeRegular {
            throw failure("Drakensang already contains a different d3d9.dll. Its file was preserved.")
        }
        if let current = try? Data(contentsOf: target), current != desired {
            let oldHash = digest(current)
            let approvedOriginal = "1295bfbca35449211d5bf86072e000173d89e3fe3d00494bc0b894b8fed64657"
            guard oldHash == approvedOriginal || (try? String(contentsOf: receipt, encoding: .utf8)) == oldHash else {
                throw failure("Drakensang already contains a different d3d9.dll. Its file was preserved.")
            }
        }
        try desired.write(to: target, options: .atomic)
        try digest(desired).write(to: receipt, atomically: true, encoding: .utf8)
    }
}
