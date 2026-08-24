import CryptoKit
import Darwin
import Foundation

private nonisolated final class LegendaryOutputBuffer: @unchecked Sendable {
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

nonisolated protocol EpicLibraryProviding: Sendable {
    func connectionState() async -> EpicConnectionState
    func prepareSupport() async throws
    func authenticate(authorizationCode: String) async throws -> String?
    func loadLibrary() async throws -> [StoreLibraryGame]
    func install(appID: String) async throws
    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan
    func disconnect() async throws
}

enum LegendaryEpicError: LocalizedError, Sendable {
    case unsupportedArchitecture
    case invalidAuthorizationCode
    case downloadFailed
    case verificationFailed
    case helperUnavailable
    case notAuthenticated
    case commandFailed(String)
    case invalidLibraryResponse
    case invalidLaunchPlan(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture: "Epic support is not available for this Mac architecture."
        case .invalidAuthorizationCode: "Paste the authorizationCode returned after signing in to Epic."
        case .downloadFailed: "Boreal couldn’t download the verified Epic support component."
        case .verificationFailed: "The downloaded Epic support component failed SHA-256 verification and was not installed."
        case .helperUnavailable: "Install Epic support before connecting your account."
        case .notAuthenticated: "Connect your Epic Games account, then refresh the Library."
        case .commandFailed(let detail): "Epic support returned an error: \(detail)"
        case .invalidLibraryResponse: "Epic returned Library data in an unsupported format."
        case .invalidLaunchPlan(let detail): "Epic returned an unsafe or incomplete launch plan: \(detail)"
        }
    }
}

actor LegendaryEpicService: EpicLibraryProviding {
    private struct ReleaseArtifact: Sendable {
        let url: URL
        let sha256: String
    }

    private struct InstalledGame: Decodable {
        let appName: String
        let installPath: String

        enum CodingKeys: String, CodingKey {
            case appName = "app_name"
            case installPath = "install_path"
        }
    }

    private struct LegendaryLaunchPlan: Decodable {
        let gameParameters: [String]
        let gameExecutable: String
        let gameDirectory: String
        let eglParameters: [String]
        let launchCommand: [String]
        let workingDirectory: String
        let userParameters: [String]
        let environment: [String: String]
        let preLaunchCommand: String

        enum CodingKeys: String, CodingKey {
            case gameParameters = "game_parameters"
            case gameExecutable = "game_executable"
            case gameDirectory = "game_directory"
            case eglParameters = "egl_parameters"
            case launchCommand = "launch_command"
            case workingDirectory = "working_directory"
            case userParameters = "user_parameters"
            case environment
            case preLaunchCommand = "pre_launch_command"
        }
    }

    private let fileManager: FileManager
    private let session: URLSession
    private let rootURL: URL
    private let helperURL: URL
    private let configURL: URL

    init(applicationSupportURL: URL, fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
        self.rootURL = applicationSupportURL.appending(path: "Tools/Legendary/0.21.0", directoryHint: .isDirectory)
        self.helperURL = rootURL.appending(path: "legendary")
        self.configURL = applicationSupportURL.appending(path: "Accounts/Epic", directoryHint: .isDirectory)
    }

    func connectionState() async -> EpicConnectionState {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { return .supportNotInstalled }
        guard let user = readUserData() else { return .disconnected }
        return .connected(displayName: user)
    }

    func prepareSupport() async throws {
        if fileManager.isExecutableFile(atPath: helperURL.path) { return }
        guard let artifact = Self.artifact else { throw LegendaryEpicError.unsupportedArchitecture }
        guard let (data, response) = try? await session.data(from: artifact.url),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LegendaryEpicError.downloadFailed
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256 else { throw LegendaryEpicError.verificationFailed }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let candidate = rootURL.appending(path: "legendary.download")
        try data.write(to: candidate, options: .atomic)
        guard chmod(candidate.path, S_IRUSR | S_IWUSR | S_IXUSR) == 0 else {
            try? fileManager.removeItem(at: candidate)
            throw LegendaryEpicError.helperUnavailable
        }
        if fileManager.fileExists(atPath: helperURL.path) { try fileManager.removeItem(at: helperURL) }
        try fileManager.moveItem(at: candidate, to: helperURL)
    }

    func authenticate(authorizationCode: String) async throws -> String? {
        let code = Self.normalizedAuthorizationCode(authorizationCode)
        guard !code.isEmpty else { throw LegendaryEpicError.invalidAuthorizationCode }
        _ = try await run(["auth", "--code", code])
        return readUserData()
    }

    func loadLibrary() async throws -> [StoreLibraryGame] {
        guard readUserData() != nil else { throw LegendaryEpicError.notAuthenticated }
        async let availableData = run(["list", "--platform", "Windows", "--json"])
        async let installedData = run(["list-installed", "--json", "--show-dirs"])
        let (libraryData, localData) = try await (availableData, installedData)
        guard let rows = try JSONSerialization.jsonObject(with: libraryData) as? [[String: Any]] else {
            throw LegendaryEpicError.invalidLibraryResponse
        }
        let installed = (try? JSONDecoder().decode([InstalledGame].self, from: localData)) ?? []
        let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.appName, $0.installPath) })
        return rows.compactMap { row in
            guard let appName = row["app_name"] as? String,
                  let title = row["app_title"] as? String,
                  !appName.isEmpty, !title.isEmpty else { return nil }
            let metadata = row["metadata"] as? [String: Any]
            let developer = (metadata?["developer"] as? String) ?? (metadata?["publisher"] as? String)
            let description = (metadata?["description"] as? String) ?? (metadata?["shortDescription"] as? String)
            let images = metadata?["keyImages"] as? [[String: Any]]
            let artwork = Self.imageURL(from: images, preferredTypes: ["DieselStoreFrontTall", "OfferImageTall", "Thumbnail"])
            let header = Self.imageURL(from: images, preferredTypes: ["DieselStoreFrontWide", "OfferImageWide", "DieselGameBoxWide"])
            let installPath = installedByID[appName]
            return StoreLibraryGame(
                provider: .epic,
                externalID: appName,
                name: title,
                developer: developer,
                summary: description,
                artworkPath: nil,
                headerImageURL: artwork ?? header,
                isInstalled: installPath != nil,
                installPath: installPath
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func disconnect() async throws {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { throw LegendaryEpicError.helperUnavailable }
        _ = try await run(["auth", "--delete"])
    }

    func install(appID: String) async throws {
        guard readUserData() != nil else { throw LegendaryEpicError.notAuthenticated }
        let gamesURL = configURL.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Games/Epic", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: gamesURL, withIntermediateDirectories: true)
        _ = try await run([
            "-y", "install", appID,
            "--platform", "Windows",
            "--base-path", gamesURL.path,
            "--skip-dlcs"
        ])
    }

    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan {
        guard readUserData() != nil else { throw LegendaryEpicError.notAuthenticated }
        let data = try await run([
            "launch", appID,
            "--json",
            "--wine", runtime.wineExecutable.path,
            "--wine-prefix", environment.prefixURL.path
        ])
        guard let value = try? JSONDecoder().decode(LegendaryLaunchPlan.self, from: data) else {
            throw LegendaryEpicError.invalidLaunchPlan("JSON could not be decoded")
        }
        guard value.preLaunchCommand.isEmpty else {
            throw LegendaryEpicError.invalidLaunchPlan("pre-launch shell commands are not executed by Boreal")
        }
        guard value.launchCommand.first == runtime.wineExecutable.path else {
            throw LegendaryEpicError.invalidLaunchPlan("the runtime executable does not match Boreal’s selected runtime")
        }
        let gameDirectory = URL(fileURLWithPath: value.gameDirectory, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let executable = gameDirectory.appending(path: value.gameExecutable)
            .resolvingSymlinksInPath().standardizedFileURL
        guard executable.path.hasPrefix(gameDirectory.path + "/"),
              fileManager.fileExists(atPath: executable.path) else {
            throw LegendaryEpicError.invalidLaunchPlan("the game executable is missing or outside its installation directory")
        }
        let workingDirectory = value.workingDirectory.isEmpty
            ? executable.deletingLastPathComponent()
            : URL(fileURLWithPath: value.workingDirectory, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard workingDirectory == gameDirectory || workingDirectory.path.hasPrefix(gameDirectory.path + "/") else {
            throw LegendaryEpicError.invalidLaunchPlan("the working directory is outside the game installation")
        }
        var providerEnvironment = value.environment
        providerEnvironment["WINEPREFIX"] = nil
        providerEnvironment["PATH"] = nil
        return WindowsLaunchPlan(
            executable: executable,
            arguments: value.gameParameters + value.userParameters + value.eglParameters,
            environment: providerEnvironment,
            workingDirectory: workingDirectory
        )
    }

    private func run(_ arguments: [String]) async throws -> Data {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { throw LegendaryEpicError.helperUnavailable }
        try fileManager.createDirectory(at: configURL, withIntermediateDirectories: true)
        return try await Self.runProcess(
            executable: helperURL,
            arguments: arguments,
            environment: ["LEGENDARY_CONFIG_PATH": configURL.path]
        )
    }

    private func readUserData() -> String? {
        let url = configURL.appending(path: "user.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (root["displayName"] as? String) ?? (root["account_id"] as? String).map { "Epic account \($0.suffix(6))" }
    }

    private static var artifact: ReleaseArtifact? {
        #if arch(arm64)
        ReleaseArtifact(
            url: URL(string: "https://github.com/legendary-gl/legendary/releases/download/0.21.0/legendary_macOS_arm64")!,
            sha256: "28f5f7d0eb8c029679d4faaa483ec85888af17a9a75977ae9170c21d8ce3428b"
        )
        #elseif arch(x86_64)
        ReleaseArtifact(
            url: URL(string: "https://github.com/legendary-gl/legendary/releases/download/0.21.0/legendary_macOS_x64")!,
            sha256: "1352dac6940cdfd4b28ce46dc7ac1f496cd9d49417b5d9d69ce462db27399665"
        )
        #else
        nil
        #endif
    }

    private static func normalizedAuthorizationCode(_ input: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = value.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["authorizationCode"] as? String {
            return code.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func imageURL(from images: [[String: Any]]?, preferredTypes: [String]) -> String? {
        for type in preferredTypes {
            if let url = images?.first(where: { ($0["type"] as? String) == type })?["url"] as? String { return url }
        }
        return images?.first?["url"] as? String
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
            let outputBuffer = LegendaryOutputBuffer()
            let errorBuffer = LegendaryOutputBuffer()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { outputBuffer.append(data) }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { errorBuffer.append(data) }
            }
            process.terminationHandler = { process in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                outputBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
                errorBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
                let output = outputBuffer.snapshot()
                let error = errorBuffer.snapshot()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let detail = String(data: error.isEmpty ? output : error, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: LegendaryEpicError.commandFailed(detail?.isEmpty == false ? detail! : "exit code \(process.terminationStatus)"))
                }
            }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
    }
}
