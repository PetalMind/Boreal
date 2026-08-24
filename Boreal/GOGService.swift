import CryptoKit
import Darwin
import Foundation

private nonisolated final class GOGOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ value: Data) {
        lock.lock()
        data.append(value)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

nonisolated protocol GOGLibraryProviding: Sendable {
    func connectionState() async -> GOGConnectionState
    func prepareSupport() async throws
    func authenticate(authorizationCode: String) async throws -> String?
    func loadLibrary() async throws -> [StoreLibraryGame]
    func install(appID: String) async throws
    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan
    func disconnect() async throws
}

enum GOGServiceError: LocalizedError, Sendable {
    case unsupportedArchitecture
    case invalidAuthorizationCode
    case downloadFailed
    case verificationFailed
    case helperUnavailable
    case notAuthenticated
    case commandFailed(Int32)
    case invalidResponse
    case installationIncomplete
    case invalidLaunchPlan(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture: "GOG support is not available for this Mac architecture."
        case .invalidAuthorizationCode: "Paste the code from GOG’s successful sign-in page."
        case .downloadFailed: "Boreal couldn’t download the verified GOG support component."
        case .verificationFailed: "The downloaded GOG support component failed SHA-256 verification and was not installed."
        case .helperUnavailable: "Install GOG support before connecting your account."
        case .notAuthenticated: "Connect your GOG account, then refresh the Library."
        case .commandFailed(let code): "GOG support stopped with exit code \(code)."
        case .invalidResponse: "GOG returned Library data in an unsupported format."
        case .installationIncomplete: "GOG finished without creating a valid Windows game installation."
        case .invalidLaunchPlan(let detail): "The installed GOG game has an unsafe or incomplete launch task: \(detail)"
        }
    }
}

actor GOGService: GOGLibraryProviding {
    private struct ReleaseArtifact: Sendable {
        let url: URL
        let sha256: String
    }

    private struct Credentials: Decodable, Sendable {
        let accessToken: String
        let userID: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case userID = "user_id"
        }
    }

    private struct LibraryEntry: Sendable {
        let externalID: String
        let certificate: String?
    }

    private struct GameMetadata: Sendable {
        var name: String
        var developer: String?
        var summary: String?
        var portraitImageURL: String?
        var headerImageURL: String?
        var backgroundImageURL: String?
        var screenshotURLs: [String]?
        var videos: [StoreVideo]?
        var rating: StoreRating?
        var supportsWindows: Bool?
        var supportsNativeMacOS: Bool?
    }

    private let fileManager: FileManager
    private let session: URLSession
    private let rootURL: URL
    private let helperURL: URL
    private let accountURL: URL
    private let authURL: URL
    private let configURL: URL
    private let gamesURL: URL

    init(applicationSupportURL: URL, fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
        self.rootURL = applicationSupportURL.appending(path: "Tools/GOGDL/1.3.0", directoryHint: .isDirectory)
        self.helperURL = rootURL.appending(path: "gogdl")
        self.accountURL = applicationSupportURL.appending(path: "Accounts/GOG", directoryHint: .isDirectory)
        self.authURL = accountURL.appending(path: "auth.json")
        self.configURL = accountURL.appending(path: "gogdl", directoryHint: .isDirectory)
        self.gamesURL = applicationSupportURL.appending(path: "Games/GOG", directoryHint: .isDirectory)
    }

    func connectionState() async -> GOGConnectionState {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { return .supportNotInstalled }
        guard fileManager.fileExists(atPath: authURL.path) else { return .disconnected }
        do {
            let credentials = try await credentials()
            let displayName = try? await userDisplayName(credentials: credentials)
            return .connected(displayName: displayName ?? "GOG account •••\(credentials.userID.suffix(4))")
        } catch {
            return .disconnected
        }
    }

    func prepareSupport() async throws {
        if fileManager.isExecutableFile(atPath: helperURL.path) { return }
        guard let artifact = Self.artifact else { throw GOGServiceError.unsupportedArchitecture }
        guard let (data, response) = try? await session.data(from: artifact.url),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GOGServiceError.downloadFailed
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256 else { throw GOGServiceError.verificationFailed }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let candidate = rootURL.appending(path: "gogdl.download")
        try data.write(to: candidate, options: .atomic)
        guard chmod(candidate.path, S_IRUSR | S_IWUSR | S_IXUSR) == 0 else {
            try? fileManager.removeItem(at: candidate)
            throw GOGServiceError.helperUnavailable
        }
        if fileManager.fileExists(atPath: helperURL.path) { try fileManager.removeItem(at: helperURL) }
        try fileManager.moveItem(at: candidate, to: helperURL)
    }

    func authenticate(authorizationCode: String) async throws -> String? {
        let code = Self.normalizedAuthorizationCode(authorizationCode)
        guard !code.isEmpty else { throw GOGServiceError.invalidAuthorizationCode }
        let data = try await run(["auth", "--code", code])
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            throw GOGServiceError.notAuthenticated
        }
        return try? await userDisplayName(credentials: credentials)
    }

    func loadLibrary() async throws -> [StoreLibraryGame] {
        let credentials = try await credentials()
        let entries = try await libraryEntries(credentials: credentials)
        guard !entries.isEmpty else { return [] }

        var games: [StoreLibraryGame] = []
        games.reserveCapacity(entries.count)
        for start in stride(from: 0, to: entries.count, by: 6) {
            let end = min(start + 6, entries.count)
            let chunk = Array(entries[start..<end])
            let values = await withTaskGroup(of: StoreLibraryGame?.self, returning: [StoreLibraryGame].self) { group in
                for entry in chunk {
                    group.addTask { [session, gamesURL, fileManager] in
                        guard let metadata = await Self.metadata(
                            entry: entry,
                            accessToken: credentials.accessToken,
                            session: session
                        ) else { return nil }
                        let installURL = gamesURL.appending(path: entry.externalID, directoryHint: .isDirectory)
                        let infoURL = installURL.appending(path: "goggame-\(entry.externalID).info")
                        let installed = fileManager.fileExists(atPath: infoURL.path)
                        return StoreLibraryGame(
                            provider: .gog,
                            externalID: entry.externalID,
                            name: metadata.name,
                            developer: metadata.developer,
                            summary: metadata.summary,
                            portraitImageURL: metadata.portraitImageURL,
                            headerImageURL: metadata.headerImageURL,
                            backgroundImageURL: metadata.backgroundImageURL,
                            screenshotURLs: metadata.screenshotURLs,
                            videos: metadata.videos,
                            storeRating: metadata.rating,
                            supportsWindows: metadata.supportsWindows,
                            supportsNativeMacOS: metadata.supportsNativeMacOS,
                            isInstalled: installed,
                            installPath: installed ? installURL.path : nil
                        )
                    }
                }
                var result: [StoreLibraryGame] = []
                for await value in group { if let value { result.append(value) } }
                return result
            }
            games.append(contentsOf: values)
        }
        guard !games.isEmpty else { throw GOGServiceError.invalidResponse }
        return games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func install(appID: String) async throws {
        _ = try await credentials()
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.invalidResponse }
        let destination = gamesURL.appending(path: appID, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: gamesURL, withIntermediateDirectories: true)
        _ = try await run([
            "download", appID,
            "--path", destination.path,
            "--platform", "windows",
            "--skip-dlcs"
        ])
        guard fileManager.fileExists(atPath: destination.appending(path: "goggame-\(appID).info").path) else {
            throw GOGServiceError.installationIncomplete
        }
    }

    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan {
        _ = runtime
        _ = environment
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.invalidLaunchPlan("invalid game ID") }
        let gameDirectory = gamesURL.appending(path: appID, directoryHint: .isDirectory)
            .resolvingSymlinksInPath().standardizedFileURL
        let infoURL = gameDirectory.appending(path: "goggame-\(appID).info")
        guard let data = try? Data(contentsOf: infoURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tasks = root["playTasks"] as? [[String: Any]],
              let task = tasks.first(where: { ($0["isPrimary"] as? Bool) == true && ($0["type"] as? String) != "URLTask" })
                ?? tasks.first(where: { ($0["type"] as? String) != "URLTask" }),
              let relativeExecutable = task["path"] as? String,
              !relativeExecutable.isEmpty else {
            throw GOGServiceError.invalidLaunchPlan("no executable play task")
        }
        let executable = Self.safeChild(relativeExecutable, of: gameDirectory)
        guard let executable, fileManager.fileExists(atPath: executable.path) else {
            throw GOGServiceError.invalidLaunchPlan("the executable is missing or outside the installation")
        }
        let workingDirectory: URL
        if let relativeWorking = task["workingDir"] as? String, !relativeWorking.isEmpty {
            guard let value = Self.safeChild(relativeWorking, of: gameDirectory) else {
                throw GOGServiceError.invalidLaunchPlan("the working directory is outside the installation")
            }
            workingDirectory = value
        } else {
            workingDirectory = executable.deletingLastPathComponent()
        }
        guard fileManager.fileExists(atPath: workingDirectory.path) else {
            throw GOGServiceError.invalidLaunchPlan("the working directory is missing")
        }
        let arguments: [String]
        if let values = task["arguments"] as? [String] { arguments = values }
        else if let value = task["arguments"] as? String { arguments = Self.parseCommandLine(value) }
        else { arguments = [] }
        return WindowsLaunchPlan(executable: executable, arguments: arguments, environment: [:], workingDirectory: workingDirectory)
    }

    func disconnect() async throws {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { throw GOGServiceError.helperUnavailable }
        if fileManager.fileExists(atPath: authURL.path) { try fileManager.removeItem(at: authURL) }
    }

    private func credentials() async throws -> Credentials {
        guard fileManager.fileExists(atPath: authURL.path) else { throw GOGServiceError.notAuthenticated }
        let data = try await run(["auth"])
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              !credentials.accessToken.isEmpty, !credentials.userID.isEmpty else {
            throw GOGServiceError.notAuthenticated
        }
        return credentials
    }

    private func libraryEntries(credentials: Credentials) async throws -> [LibraryEntry] {
        var pageToken: String?
        var result: [LibraryEntry] = []
        repeat {
            var components = URLComponents(string: "https://galaxy-library.gog.com/users/\(credentials.userID)/releases")!
            if let pageToken { components.queryItems = [URLQueryItem(name: "page_token", value: pageToken)] }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = root["items"] as? [[String: Any]] else { throw GOGServiceError.invalidResponse }
            result.append(contentsOf: items.compactMap { item in
                guard (item["platform_id"] as? String) == "gog",
                      let id = Self.stringValue(item["external_id"]), Self.isSafeAppID(id) else { return nil }
                return LibraryEntry(externalID: id, certificate: item["certificate"] as? String)
            })
            pageToken = root["next_page_token"] as? String
            if pageToken?.isEmpty == true { pageToken = nil }
        } while pageToken != nil
        return Array(Dictionary(grouping: result, by: \.externalID).values.compactMap(\.first))
    }

    private func userDisplayName(credentials: Credentials) async throws -> String? {
        guard let url = URL(string: "https://users.gog.com/users/\(credentials.userID)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (root["username"] as? String) ?? (root["display_name"] as? String)
    }

    private static func metadata(entry: LibraryEntry, accessToken: String, session: URLSession) async -> GameMetadata? {
        guard let url = URL(string: "https://gamesdb.gog.com/platforms/gog/external_releases/\(entry.externalID)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let certificate = entry.certificate { request.setValue(certificate, forHTTPHeaderField: "X-GOG-Library-Cert") }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let game = root["game"] as? [String: Any] else { return nil }
        let title = localized(root["title"]) ?? localized(game["title"]) ?? "GOG Game \(entry.externalID)"
        let developers = (game["developers"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        let background = imageURL(game["background"])
        let wide = imageURL(game["logo"]) ?? background
        let portrait = imageURL(game["vertical_cover"]) ?? wide
        let screenshots = (game["screenshots"] as? [[String: Any]])?.compactMap { imageURL($0) }
        let systems = (root["supported_operating_systems"] as? [[String: Any]])?.compactMap { $0["slug"] as? String } ?? []
        let ratingValue = intValue(game["aggregated_rating"]) ?? intValue(game["rating"])
        return GameMetadata(
            name: title.trimmingCharacters(in: .whitespacesAndNewlines),
            developer: developers?.joined(separator: ", "),
            summary: localized(root["summary"]),
            portraitImageURL: portrait,
            headerImageURL: wide,
            backgroundImageURL: background,
            screenshotURLs: screenshots,
            videos: nil,
            rating: ratingValue.map { StoreRating(criticScore: $0) },
            supportsWindows: systems.contains("windows"),
            supportsNativeMacOS: systems.contains("osx")
        )
    }

    private func run(_ arguments: [String]) async throws -> Data {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { throw GOGServiceError.helperUnavailable }
        try fileManager.createDirectory(at: accountURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: configURL, withIntermediateDirectories: true)
        return try await Self.runProcess(
            executable: helperURL,
            arguments: ["--auth-config-path", authURL.path] + arguments,
            environment: ["GOGDL_CONFIG_PATH": configURL.path]
        )
    }

    private static var artifact: ReleaseArtifact? {
        #if arch(arm64)
        ReleaseArtifact(
            url: URL(string: "https://github.com/Heroic-Games-Launcher/heroic-gogdl/releases/download/v1.3.0/gogdl_macos_arm64")!,
            sha256: "a85ae9ef80a3e7840b19a416dd4b3c5db2054508c6147315f1c22faa63a29b38"
        )
        #elseif arch(x86_64)
        ReleaseArtifact(
            url: URL(string: "https://github.com/Heroic-Games-Launcher/heroic-gogdl/releases/download/v1.3.0/gogdl_macos_x86_64")!,
            sha256: "a3d1e20f09371eb9032a4837eb576b585456728a6f2f420e6877e5cccd4c434d"
        )
        #else
        nil
        #endif
    }

    private static func normalizedAuthorizationCode(_ input: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: value),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value { return code }
        if let data = value.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = (json["code"] as? String) ?? (json["authorizationCode"] as? String) { return code }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func safeChild(_ windowsPath: String, of root: URL) -> URL? {
        let normalized = windowsPath.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/"), !normalized.contains(":") else { return nil }
        let value = root.appending(path: normalized).resolvingSymlinksInPath().standardizedFileURL
        return value.path.hasPrefix(root.path + "/") ? value : nil
    }

    private static func parseCommandLine(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var escaping = false
        for character in input {
            if escaping { current.append(character); escaping = false }
            else if character == "\\" { escaping = true }
            else if character == "\"" { quoted.toggle() }
            else if character.isWhitespace && !quoted {
                if !current.isEmpty { result.append(current); current = "" }
            } else { current.append(character) }
        }
        if escaping { current.append("\\") }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func imageURL(_ value: Any?) -> String? {
        guard let object = value as? [String: Any],
              var format = object["url_format"] as? String else { return nil }
        format = format.replacingOccurrences(of: "{formatter}", with: "")
        format = format.replacingOccurrences(of: "{ext}", with: "jpg")
        return format
    }

    private static func localized(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        return (value as? [String: Any])?["*"] as? String
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let object = value as? [String: Any] { return intValue(object["score"]) }
        return nil
    }

    private static func isSafeAppID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }

    private nonisolated static func runProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let output = GOGOutputBuffer()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { output.append(data) }
            }
            process.terminationHandler = { process in
                stdout.fileHandleForReading.readabilityHandler = nil
                output.append(stdout.fileHandleForReading.readDataToEndOfFile())
                _ = stderr.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 { continuation.resume(returning: output.snapshot()) }
                else { continuation.resume(throwing: GOGServiceError.commandFailed(process.terminationStatus)) }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
    }
}
