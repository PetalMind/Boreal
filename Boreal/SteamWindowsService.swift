import Foundation
import CryptoKit

nonisolated struct SteamWindowsClientCommit: Sendable {
    let installation: InstallationCommit
    let steamExecutable: URL
    let poolKey: String
}

nonisolated protocol SteamWindowsProviding: Sendable {
    func prepareClient(progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsClientCommit
    func prepareClient(poolKey: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsClientCommit
}

extension SteamWindowsProviding {
    func prepareClient(poolKey: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsClientCommit {
        var result = try await prepareClient(progress: progress)
        return SteamWindowsClientCommit(installation: result.installation, steamExecutable: result.steamExecutable, poolKey: poolKey)
    }
}

enum SteamWindowsError: LocalizedError, Sendable {
    case downloadFailed
    case invalidInstaller
    case clientExecutableMissing
    case gameNotInstalled(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed: "Boreal couldn’t download Valve’s official Steam for Windows installer."
        case .invalidInstaller: "Valve’s download did not contain a valid Windows installer."
        case .clientExecutableMissing: "Steam setup finished, but steam.exe was not found in the isolated environment."
        case .gameNotInstalled(let appID): "Steam AppID \(appID) is not installed in the Windows Steam bottle yet. Open Steam and finish the download first."
        }
    }
}

actor SteamWindowsService: SteamWindowsProviding {
    nonisolated static let expectedInstallerSHA256DefaultsKey = "steamSetup.expectedSHA256"
    private let fileManager: FileManager
    private let session: URLSession
    private let installer: any Installing
    private let installerURL: URL
    private let expectedInstallerSHA256: String?
    private static let setupURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!

    init(
        applicationSupportURL: URL,
        installer: any Installing,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        expectedInstallerSHA256: String? = UserDefaults.standard.string(forKey: expectedInstallerSHA256DefaultsKey)
    ) {
        self.installer = installer
        self.fileManager = fileManager
        self.session = session
        self.installerURL = applicationSupportURL.appending(path: "Installers/Steam/SteamSetup.exe")
        self.expectedInstallerSHA256 = expectedInstallerSHA256
    }

    func prepareClient(progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsClientCommit {
        try await prepareClient(poolKey: "shared", progress: progress)
    }

    func prepareClient(poolKey: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsClientCommit {
        try await downloadCurrentInstaller()
        let installation = try await installer.install(installerURL, name: "Steam for Windows", progress: progress)
        guard installation.firstLaunch != nil else { throw SteamWindowsError.clientExecutableMissing }
        guard let steamExecutable = Self.steamExecutable(
            in: installation.environment,
            discovered: installation.executable,
            fileManager: fileManager
        ) else {
            throw SteamWindowsError.clientExecutableMissing
        }
        return SteamWindowsClientCommit(installation: installation, steamExecutable: steamExecutable, poolKey: poolKey)
    }

    private func downloadCurrentInstaller() async throws {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: Self.setupURL)
        } catch {
            throw SteamWindowsError.downloadFailed
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url?.scheme == "https",
              http.url?.host == Self.setupURL.host,
              data.count > 1_000_000,
              data.prefix(2) == Data([0x4D, 0x5A]) else {
            throw SteamWindowsError.invalidInstaller
        }
        // SteamSetup.exe is a PE file, so Apple's code-signing APIs cannot
        // validate its Authenticode chain. A deployment can provide the
        // expected publisher-supplied digest; without it we still enforce
        // HTTPS, Valve's download host, a successful response and PE format.
        if let expectedInstallerSHA256 {
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest.caseInsensitiveCompare(expectedInstallerSHA256) == .orderedSame else {
                throw SteamWindowsError.invalidInstaller
            }
        }
        try fileManager.createDirectory(at: installerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: installerURL, options: .atomic)
    }

    static func steamExecutable(
        in environment: ManagedBorealEnvironment,
        discovered: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let driveC = environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory).standardizedFileURL
        let candidates = [
            driveC.appending(path: "Program Files (x86)/Steam/steam.exe"),
            driveC.appending(path: "Program Files/Steam/steam.exe"),
            discovered
        ]
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(driveC.path + "/") else { continue }
            if fileManager.fileExists(atPath: resolved.path),
               resolved.lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame {
                return resolved
            }
        }
        let snapshot = ExecutableDiscovery.snapshot(at: driveC, fileManager: fileManager)
        return snapshot.entries.first(where: {
            ($0.relativePath as NSString).lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame
        }).map {
            driveC.appending(path: $0.relativePath).resolvingSymlinksInPath().standardizedFileURL
        }
    }

    static func playPlan(
        appID: String,
        steamExecutable: URL,
        gameExecutableName: String? = nil,
        gameExecutablePath: String? = nil,
        sessionScope: SessionScope = .processGroup
    ) -> WindowsLaunchPlan {
        WindowsLaunchPlan(
            executable: steamExecutable,
            arguments: ["-applaunch", appID],
            environment: [:],
            workingDirectory: steamExecutable.deletingLastPathComponent(),
            sessionScope: sessionScope,
            processExecutableName: gameExecutableName,
            processExecutablePath: gameExecutablePath
        )
    }

    /// Finds the executable that should define a Steam game's user-visible
    /// session. Steam itself is deliberately excluded from this decision.
    static func primaryExecutable(
        in directory: URL,
        applicationName: String? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let root = directory.standardizedFileURL
        let snapshot = ExecutableDiscovery.snapshot(at: root, fileManager: fileManager)
        let candidates = ExecutableDiscovery.rankedCandidates(
            before: ExecutableFilesystemSnapshot(rootURL: root, entries: []),
            after: snapshot,
            applicationName: applicationName ?? root.lastPathComponent
        )
        return candidates.first(where: {
            $0.score >= ExecutableDiscovery.minimumLaunchCandidateScore
                && fileManager.fileExists(atPath: $0.url.path)
        })?.url.standardizedFileURL
    }

    static func bootstrapPlan(steamExecutable: URL) -> WindowsLaunchPlan {
        WindowsLaunchPlan(
            executable: steamExecutable,
            arguments: ["-silent"],
            environment: [:],
            workingDirectory: steamExecutable.deletingLastPathComponent()
        )
    }

    static func protocolPlan(_ value: String, steamExecutable: URL) -> WindowsLaunchPlan {
        WindowsLaunchPlan(
            executable: steamExecutable,
            arguments: [value],
            environment: [:],
            workingDirectory: steamExecutable.deletingLastPathComponent()
        )
    }

    static func installedGameDirectory(
        appID: String,
        in environment: ManagedBorealEnvironment,
        fileManager: FileManager = .default
    ) -> URL? {
        guard !appID.isEmpty, appID.allSatisfy(\.isNumber) else { return nil }
        let driveC = environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory)
        let steamRoots = [
            driveC.appending(path: "Program Files (x86)/Steam", directoryHint: .isDirectory),
            driveC.appending(path: "Program Files/Steam", directoryHint: .isDirectory)
        ]
        var manifests = steamRoots.map { $0.appending(path: "steamapps/appmanifest_\(appID).acf") }
        if let enumerator = fileManager.enumerator(at: environment.prefixURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let candidate as URL in enumerator where candidate.lastPathComponent == "appmanifest_\(appID).acf" {
                manifests.append(candidate)
            }
        }
        for manifest in manifests {
            let steamRoot = manifest.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
            guard fileManager.fileExists(atPath: manifest.path),
                  let root = try? ValveKeyValueDecoder.decode(url: manifest),
                  let state = root.object("AppState"),
                  let installDirectory = state.string("installdir"),
                  !installDirectory.isEmpty else { continue }
            let gameDirectory = steamRoot.appending(path: "steamapps/common/\(installDirectory)").standardizedFileURL
            guard gameDirectory.path.hasPrefix(steamRoot.standardizedFileURL.path + "/"),
                  fileManager.fileExists(atPath: gameDirectory.path) else { continue }
            return gameDirectory
        }
        return nil
    }
}


/// An externally maintained Steam installation owns its prefix, Wine and DXMT.
/// Never import this prefix into EnvironmentManager or reconfigure its DLLs.
nonisolated enum SteamOnM1Wine {
    struct Installation: Sendable {
        let appURL: URL
        let repositoryURL: URL
        let prefixURL: URL

        var steamRoot: URL {
            prefixURL.appending(path: "drive_c/Program Files (x86)/Steam", directoryHint: .isDirectory)
        }
    }

    static var appURL: URL? {
        let fm = FileManager.default
        return [fm.homeDirectoryForCurrentUser.appending(path: "Applications/Steam on M1 Wine.app"),
                URL(fileURLWithPath: "/Applications/Steam on M1 Wine.app")].first {
            guard let info = NSDictionary(contentsOf: $0.appending(path: "Contents/Info.plist")) else { return false }
            return info["CFBundleIdentifier"] as? String == "com.github.notpop.steam-on-m1-wine"
        }
    }

    static var steamRoot: URL? {
        guard appURL != nil else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".wine-steam/drive_c/Program Files (x86)/Steam", directoryHint: .isDirectory)
    }

    static func installation() throws -> Installation {
        guard let appURL else {
            throw ProcessRunnerError.launchFailed("Steam on M1 Wine is not installed.")
        }
        let launcher = try String(contentsOf: appURL.appending(path: "Contents/MacOS/launcher"), encoding: .utf8)
        // Read the literal path emitted by upstream's macOS app installer.
        // Do not evaluate the launcher as shell code just to discover a path.
        guard let line = launcher.components(separatedBy: .newlines).first(where: { $0.hasPrefix("REPO_ROOT=\"") }),
              line.hasSuffix("\"") else {
            throw ProcessRunnerError.launchFailed("Steam on M1 Wine has an unsupported launcher. Reinstall its macOS app.")
        }
        let path = String(line.dropFirst("REPO_ROOT=\"".count).dropLast())
        guard path.hasPrefix("/"), !path.contains("$"), !path.contains("`"),
              FileManager.default.isReadableFile(atPath: path + "/scripts/lib/common.sh") else {
            throw ProcessRunnerError.launchFailed("The Steam on M1 Wine repository is unavailable. Reconnect its volume.")
        }
        return Installation(appURL: appURL, repositoryURL: URL(fileURLWithPath: path),
                            prefixURL: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".wine-steam"))
    }

    /// Valve stores Windows paths in libraryfolders.vdf even on a Unix host.
    static func libraryURL(_ path: String, steamRoot: URL) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        guard path.count >= 3 else { return nil }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let characters = Array(normalized)
        guard characters[1] == ":", characters[2] == "/" else { return nil }
        // .../prefix/drive_c/Program Files (x86)/Steam
        let prefix = steamRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return prefix.appending(path: "dosdevices/\(String(characters[0]).lowercased()):").resolvingSymlinksInPath()
            .appending(path: String(normalized.dropFirst(3))).resolvingSymlinksInPath()
    }

    static func libraryDirectories(steamRoot: URL) -> [URL] {
        var roots = [steamRoot.appending(path: "steamapps")]
        if let root = try? ValveKeyValueDecoder.decode(url: roots[0].appending(path: "libraryfolders.vdf")),
           let folders = root.object("libraryfolders") {
            for value in folders.values {
                guard let path = value.objectValue?.string("path"),
                      let library = libraryURL(path, steamRoot: steamRoot) else { continue }
                let directory = library.appending(path: "steamapps")
                if !roots.contains(directory) { roots.append(directory) }
            }
        }
        return roots
    }

    static func installedGameDirectory(appID: String) -> URL? {
        guard !appID.isEmpty, appID.allSatisfy(\.isNumber), let steamRoot else { return nil }
        for directory in libraryDirectories(steamRoot: steamRoot) {
            guard let root = try? ValveKeyValueDecoder.decode(url: directory.appending(path: "appmanifest_\(appID).acf")),
                  let state = root.object("AppState"), state.string("appid") == appID,
                  let flags = Int(state.string("StateFlags") ?? ""), flags & 4 != 0,
                  let name = state.string("installdir"), !name.isEmpty else { continue }
            let common = directory.appending(path: "common").resolvingSymlinksInPath().standardizedFileURL
            let game = common.appending(path: name).resolvingSymlinksInPath().standardizedFileURL
            var isDirectory: ObjCBool = false
            if game.path.hasPrefix(common.path + "/"),
               FileManager.default.fileExists(atPath: game.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return game
            }
        }
        return nil
    }

    static func launchScript(from upstream: String) throws -> String {
        var script = upstream
        let source = "source \"$(dirname \"$0\")/lib/common.sh\""
        // Upstream 0.6 kills all Wine processes and clears browser locks on
        // every click. Remove that reset for Boreal's reusable client: a
        // second AppID request must leave existing games and prefixes alive.
        guard script.contains(source),
              let resetStart = script.range(of: "# -- 1. Stop lingering processes"),
              let resetEnd = script.range(of: "# -- 2b. Defensive:"),
              resetStart.lowerBound < resetEnd.lowerBound,
              script.contains("log_step \"Launching Steam\"") else {
            throw ProcessRunnerError.launchFailed("Unsupported Steam on M1 Wine launch script; expected the v0.6 launcher.")
        }
        script.removeSubrange(resetStart.lowerBound..<resetEnd.lowerBound)
        script = script.replacingOccurrences(of: source, with: "source \"$BOREAL_STEAM_COMMON\"")
        script = script.replacingOccurrences(of: "log_step \"Launching Steam\"", with: "STEAM_ARGS+=(\"${@:2}\")\nlog_step \"Launching Steam\"")
        script = script.replacingOccurrences(of: ": > \"$LOG_FILE\"", with: ": # Keep the current session log")
        return script
    }

    static func open(_ url: URL, launchArguments: [String] = [], wineAppURL: URL? = nil) async throws {
        guard url.scheme == "steam", let action = url.host,
              ["openmain", "rungameid", "install", "uninstall", "store"].contains(action) else {
            throw ProcessRunnerError.launchFailed("Unsupported Steam action.")
        }
        let appID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard action == "openmain" || (!appID.isEmpty && appID.allSatisfy(\.isNumber)) else {
            throw ProcessRunnerError.launchFailed("Invalid Steam AppID.")
        }
        let installation = try installation()
        try await Task.detached(priority: .userInitiated) {
            let upstream = try String(contentsOf: installation.repositoryURL.appending(path: "scripts/launch-steam.sh"), encoding: .utf8)
            let script = try launchScript(from: upstream)
            let fm = FileManager.default
            let logDirectory = fm.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Boreal", directoryHint: .isDirectory)
            try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let logURL = logDirectory.appending(path: "steam-on-m1-wine-launcher.log")
            if !fm.fileExists(atPath: logURL.path) { _ = fm.createFile(atPath: logURL.path, contents: nil) }
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }
            try log.seekToEnd()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            let arguments = action == "rungameid" ? ["-applaunch", appID] + launchArguments
                : (action == "openmain" ? [] : [url.absoluteString])
            process.arguments = ["-c", script, "boreal-steam-on-m1-wine", "--detach"] + arguments
            var environment = ProcessInfo.processInfo.environment
            // Use this installation's defaults, never an inherited Boreal bottle.
            for key in ["WINEARCH", "WINE_BIN", "WINE_APP", "WINESERVER_BIN", "WINEDLLOVERRIDES", "DYLD_LIBRARY_PATH"] {
                environment.removeValue(forKey: key)
            }
            if let wineAppURL {
                environment["WINE_APP"] = wineAppURL.path
                environment["WINE_VIRTUAL_DESKTOP"] = ""
            }
            environment["WINEPREFIX"] = installation.prefixURL.path
            environment["BOREAL_STEAM_COMMON"] = installation.repositoryURL.appending(path: "scripts/lib/common.sh").path
            environment["STEAM_LAUNCH_LOG"] = logDirectory.appending(path: "steam-on-m1-wine.log").path
            process.environment = environment
            process.currentDirectoryURL = installation.repositoryURL
            process.standardOutput = log
            process.standardError = log
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ProcessRunnerError.launchFailed("Steam on M1 Wine could not start (exit \(process.terminationStatus)). Log: \(logURL.path)")
            }
        }.value
    }
}


/// Sacred 2's DX12 renderer cannot use DXMT's DXGI with Wine's VKD3D.
/// Keep a complete D3DMetal host in its own prefix and retain Steam/AppID
/// launching. A fresh prefix deliberately requires its own Steam sign-in.
actor SteamD3DMetalCompatibility {
    static let shared = SteamD3DMetalCompatibility()
    nonisolated static let sacred2AppID = "3906660"
    private var preparing = false

    nonisolated static func applies(to url: URL) -> Bool {
        url.scheme == "steam" && url.host == "rungameid"
            && url.path == "/\(sacred2AppID)"
    }

    nonisolated static func preferredRuntime(in runtimes: [InstalledRuntime], prefixRoot: URL? = nil) -> InstalledRuntime? {
        let candidates = runtimes.filter {
            $0.architecture == .x86_64 && $0.features?.d3dmetal == true
                && $0.features?.d3dmetalVerified == true
        }
        // A private prefix is tied to the Wine/D3DMetal host that initialized it.
        // Reuse that verified host when available; silently selecting a newer host
        // makes the later ownership check reject an otherwise usable prefix.
        if let prefixRoot,
           let pinnedID = try? String(contentsOf: prefixRoot.appending(path: "runtime-id.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pinned = candidates.first(where: { $0.id == pinnedID }) {
            return pinned
        }
        return candidates.sorted {
            let graphicsOrder = ($0.features?.d3dmetalVersion ?? "0").compare(
                $1.features?.d3dmetalVersion ?? "0", options: .numeric
            )
            if graphicsOrder != .orderedSame { return graphicsOrder == .orderedDescending }
            return $0.wineVersion.compare($1.wineVersion, options: .numeric) == .orderedDescending
        }.first
    }

    func open(
        installation: SteamOnM1Wine.Installation,
        runtime: InstalledRuntime,
        root: URL,
        launchArguments: [String],
        startupShim: URL? = Bundle.main.url(forResource: "BorealSteamCompatibility", withExtension: "dll")
    ) async throws -> Bool {
        guard !preparing else {
            throw ProcessRunnerError.launchFailed("Sacred 2's Steam environment is already being prepared.")
        }
        preparing = true
        defer { preparing = false }
        return try await Task.detached(priority: .userInitiated) {
            guard let startupShim else {
                throw ProcessRunnerError.launchFailed("Boreal's Steam startup compatibility library is missing from the app bundle.")
            }
            return try Self.prepareAndLaunch(installation: installation, runtime: runtime, root: root.appending(path: runtime.id),
                                             launchArguments: launchArguments, startupShim: startupShim)
        }.value
    }

    private nonisolated static func prepareAndLaunch(
        installation: SteamOnM1Wine.Installation,
        runtime: InstalledRuntime,
        root: URL,
        launchArguments: [String],
        startupShim: URL
    ) throws -> Bool {
        let fm = FileManager.default
        let libraries = runtime.wineExecutable.deletingLastPathComponent().deletingLastPathComponent().appending(path: "lib")
        let framework = libraries.appending(path: "external/D3DMetal.framework/D3DMetal")
        let required = [runtime.wineExecutable, runtime.wineServerExecutable, framework,
                        libraries.appending(path: "wine/x86_64-unix/d3d12.so"),
                        libraries.appending(path: "wine/x86_64-unix/dxgi.so")]
        guard runtime.features?.d3dmetal == true, runtime.features?.d3dmetalVerified == true,
              required.allSatisfy({ fm.isReadableFile(atPath: $0.path) }) else {
            throw ProcessRunnerError.launchFailed("Sacred 2 requires a complete, verified D3DMetal runtime with matching DXGI and D3D12 libraries.")
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let prefix = root.appending(path: "prefix")
        let receipt = root.appending(path: "runtime-id.txt")
        if fm.fileExists(atPath: prefix.path) {
            guard (try? String(contentsOf: receipt, encoding: .utf8)) == runtime.id else {
                throw ProcessRunnerError.launchFailed("Sacred 2's private Steam prefix belongs to another runtime or an interrupted setup. Its data has been preserved at \(root.path).")
            }
        } else {
            // Record ownership before initialization. A retry uses the same
            // host even when wineboot was interrupted; no other prefix is touched.
            try runtime.id.write(to: receipt, atomically: true, encoding: .utf8)
        }
        let logURL = root.appending(path: "launch.log")
        if !fm.fileExists(atPath: logURL.path) { _ = fm.createFile(atPath: logURL.path, contents: nil) }
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        try log.seekToEnd()
        var environment = ProcessInfo.processInfo.environment
        for key in ["WINEARCH", "WINEDLLPATH", "DYLD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES", "WINE_D3D_CONFIG", "WINED3D_RENDERER", "DXMT_CONFIG", "DXVK_CONFIG_FILE", "D3DM_MTL4"] {
            environment.removeValue(forKey: key)
        }
        environment["WINEPREFIX"] = prefix.path
        environment["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["WINEDEBUG"] = "-all,err+all"
        // Modern Wine implements the required RNG and realtime APIs directly.
        // Keep the old host's process hooks out of newer Steam environments.
        let needsLegacyCompatibility = runtime.wineVersion.compare("10.0", options: .numeric) == .orderedAscending
        environment["WINEDLLOVERRIDES"] = (needsLegacyCompatibility ? "version=n,b;" : "")
            + "dxgi,d3d11,d3d12=b;bcrypt,ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"
        environment["D3DMETAL_FRAMEWORK_PATH"] = framework.path
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = libraries.appending(path: "external").path + ":" + libraries.path + ":/usr/lib"
        environment["BOREAL_STEAM_LOG"] = logURL.path
        let initialized = root.appending(path: "prefix-initialized")
        if !fm.fileExists(atPath: initialized.path) {
            do {
                try runAndWait(executable: runtime.wineExecutable, arguments: ["wineboot", "--init"], environment: environment, log: log, timeout: 120)
                try Data().write(to: initialized, options: .atomic)
            } catch {
                // This is the freshly created, private prefix. Stop only its
                // server after a failed initialization so retry cannot race it.
                try? runAndWait(executable: runtime.wineServerExecutable, arguments: ["-k"], environment: environment, log: log, timeout: 10)
                throw error
            }
        }
        let steamRoot = prefix.appending(path: "drive_c/Program Files (x86)/Steam")
        let ready = root.appending(path: "client-provisioned-v2")
        if !fm.fileExists(atPath: ready.path) {
            try fm.createDirectory(at: steamRoot, withIntermediateDirectories: true)
            // Only redistribute locally installed PROGRAM FILES into the new
            // prefix. Never copy config, userdata, appcache, ssfn*, registry,
            // browser caches, loginusers.vdf or the source prefix itself.
            let rootFiles = try fm.contentsOfDirectory(at: installation.steamRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let codeFiles = rootFiles.filter {
                let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values?.isRegularFile == true && values?.isSymbolicLink != true
                    && (["exe", "dll"].contains($0.pathExtension.lowercased())
                        || $0.lastPathComponent.hasPrefix("ThirdPartyLegalNotices"))
            }.map(\.lastPathComponent)
            let codeDirectories = ["bin", "clientui", "steamui", "win64", "controller_base",
                                   "public", "resource", "friends", "graphics", "tenfoot", "servers"]
            for name in codeFiles + codeDirectories {
                let source = installation.steamRoot.appending(path: name)
                let destination = steamRoot.appending(path: name)
                guard fm.fileExists(atPath: source.path) else { continue }
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                // ditto handles Steam's cross-volume client tree without
                // requiring source filesystem metadata on the destination.
                try runAndWait(executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                               arguments: ["--norsrc", "--noextattr", "--noacl", source.path, destination.path],
                               environment: environment, log: log, timeout: 120)
            }
            let sourcePackage = installation.steamRoot.appending(path: "package")
            let package = steamRoot.appending(path: "package")
            try fm.createDirectory(at: package, withIntermediateDirectories: true)
            for file in (try? fm.contentsOfDirectory(at: sourcePackage, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "installed" || file.pathExtension == "manifest" {
                let destination = package.appending(path: file.lastPathComponent)
                if !fm.fileExists(atPath: destination.path) { try fm.copyItem(at: file, to: destination) }
            }
            guard fm.isReadableFile(atPath: steamRoot.appending(path: "Steam.exe").path) else {
                throw SteamWindowsError.clientExecutableMissing
            }
            try Data().write(to: ready, options: .atomic)
        }
        if needsLegacyCompatibility {
            try deployStartupShim(from: startupShim, to: steamRoot.appending(path: "version.dll"),
                                  receipt: root.appending(path: "startup-shim.sha256"))
            let realtimeShim = startupShim.deletingLastPathComponent().appending(path: "BorealRealtimeCompatibility.dll")
            try deployStartupShim(from: realtimeShim,
                                  to: prefix.appending(path: "drive_c/windows/system32/BorealRealtimeCompatibility.dll"),
                                  receipt: root.appending(path: "realtime-shim.sha256"))
        }
        environment["PATH"] = steamRoot.path + ":" + (environment["PATH"] ?? "")
        // Preserve independently authenticated sessions on subsequent launches.
        // The private client repairs its own CEF wrapper, never the shared client.
        try deployWrapper(from: installation.repositoryURL, steamRoot: steamRoot)
        let cefDirectories = try fm.contentsOfDirectory(at: steamRoot.appending(path: "bin/cef"), includingPropertiesForKeys: nil)
        for directory in cefDirectories where needsLegacyCompatibility && directory.lastPathComponent.hasPrefix("cef.win") {
            try deployStartupShim(from: startupShim, to: directory.appending(path: "version.dll"),
                                  receipt: root.appending(path: "startup-shim-\(directory.lastPathComponent).sha256"))
        }
        let steamApps = steamRoot.appending(path: "steamapps")
        try fm.createDirectory(at: steamApps, withIntermediateDirectories: true)
        let folders = steamApps.appending(path: "libraryfolders.vdf")
        if !fm.fileExists(atPath: folders.path) {
            var text = "\"libraryfolders\"\n{\n"
            let externalLibraries = SteamOnM1Wine.libraryDirectories(steamRoot: installation.steamRoot)
                .filter { $0.standardizedFileURL != installation.steamRoot.appending(path: "steamapps").standardizedFileURL }
            let libraryRoots = [steamRoot] + externalLibraries.map { $0.deletingLastPathComponent() }
            for (index, library) in libraryRoots.enumerated() {
                let path = "Z:" + library.path.replacingOccurrences(of: "/", with: "\\")
                let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                text += "\t\"\(index)\" { \"path\" \"\(escaped)\" }\n"
            }
            text += "}\n"
            try text.write(to: folders, atomically: true, encoding: .utf8)
        }
        let needsSignIn = !fm.fileExists(atPath: steamRoot.appending(path: "config/loginusers.vdf").path)
        let arguments = ["-x86_64", runtime.wineExecutable.path, "explorer.exe",
                         "/desktop=Boreal-Sacred2-D3DMetal,1280x800",
                         "C:\\Program Files (x86)\\Steam\\Steam.exe",
                         "-no-cef-sandbox", "-cef-single-process", "-noverifyfiles",
                         "-applaunch", sacred2AppID] + launchArguments
        // Bootstrap acceptance is a handoff, not proof that the game is running.
        try runAndWait(executable: URL(fileURLWithPath: "/bin/bash"),
                       arguments: ["-c", "nohup \"$@\" >>\"$BOREAL_STEAM_LOG\" 2>&1 </dev/null &", "boreal-steam-d3dmetal", "/usr/bin/arch"] + arguments,
                       environment: environment, log: log, timeout: 10)
        return needsSignIn
    }

    private nonisolated static func deployStartupShim(from source: URL, to target: URL, receipt: URL) throws {
        let expected = try Data(contentsOf: source)
        let digest = { (data: Data) in SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        if let current = try? Data(contentsOf: target), current != expected {
            guard (try? String(contentsOf: receipt, encoding: .utf8)) == digest(current) else {
                throw ProcessRunnerError.launchFailed("A different compatibility library is present at \(target.path). It was preserved.")
            }
        }
        try expected.write(to: target, options: .atomic)
        try digest(expected).write(to: receipt, atomically: true, encoding: .utf8)
    }

    private nonisolated static func deployWrapper(from repository: URL, steamRoot: URL) throws {
        let fm = FileManager.default
        let wrapper = repository.appending(path: "wrapper/steamwebhelper.exe")
        guard fm.isReadableFile(atPath: wrapper.path) else {
            throw ProcessRunnerError.launchFailed("Steam on M1 Wine's compiled CEF wrapper is missing.")
        }
        let cef = steamRoot.appending(path: "bin/cef")
        let directories = try fm.contentsOfDirectory(at: cef, includingPropertiesForKeys: nil)
        let wrapperData = try Data(contentsOf: wrapper)
        for directory in directories where directory.lastPathComponent.hasPrefix("cef.win") {
            let target = directory.appending(path: "steamwebhelper.exe")
            let real = directory.appending(path: "steamwebhelper_real.exe")
            let current = try Data(contentsOf: target)
            if current == wrapperData { continue }
            // Preserve Valve's original helper when Steam replaces the wrapper.
            guard current.count > 500_000 else {
                throw ProcessRunnerError.launchFailed("The private Steam CEF helper could not be identified safely.")
            }
            if fm.fileExists(atPath: real.path) { try fm.removeItem(at: real) }
            try fm.moveItem(at: target, to: real)
            try wrapperData.write(to: target, options: .atomic)
        }
    }

    private nonisolated static func runAndWait(
        executable: URL, arguments: [String], environment: [String: String], log: FileHandle, timeout: TimeInterval
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = log
        process.standardError = log
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard !process.isRunning else {
            process.terminate()
            throw ProcessRunnerError.launchFailed("Sacred 2's Steam preparation timed out. See its private launch.log.")
        }
        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.launchFailed("Sacred 2's Steam preparation failed (exit \(process.terminationStatus)). See its private launch.log.")
        }
    }
}
