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
    func loadSizeEstimate(appID: String, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate?
    func install(appID: String, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func install(appID: String, destinationRoot: URL, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func install(appID: String, destinationRoot: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func installationURL(appID: String, destinationRoot: URL, platform: StoreGameInstallationPlatform) async -> URL?
    func update(appID: String, installationURL: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func verify(appID: String, installationURL: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan
    func launchPlan(appID: String, installationURL: URL, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan
    func disconnect() async throws
}

extension GOGLibraryProviding {
    func update(appID: String, installationURL: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        _ = appID
        _ = installationURL
        _ = platform
        _ = progress
        throw CocoaError(.featureUnsupported)
    }

    func verify(appID: String, installationURL: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        _ = appID
        _ = installationURL
        _ = platform
        _ = progress
        throw CocoaError(.featureUnsupported)
    }

    func installationURL(appID: String, destinationRoot: URL, platform: StoreGameInstallationPlatform) async -> URL? {
        _ = platform
        let candidate = destinationRoot.appending(path: appID, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    func loadSizeEstimate(appID: String, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate? {
        _ = appID
        _ = platform
        return nil
    }

    func install(appID: String, destinationRoot: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        _ = platform
        try await install(appID: appID, destinationRoot: destinationRoot, progress: progress)
    }

    func install(appID: String, destinationRoot: URL, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        _ = destinationRoot
        try await install(appID: appID, progress: progress)
    }

    func launchPlan(appID: String, installationURL: URL, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan {
        _ = installationURL
        return try await launchPlan(appID: appID, runtime: runtime, environment: environment)
    }
}

enum GOGServiceError: LocalizedError, Sendable, Equatable {
    case unsupportedArchitecture
    case invalidAuthorizationCode
    case downloadFailed
    case verificationFailed
    case helperUnavailable
    case notAuthenticated
    case commandFailed(Int32)
    case noBuildsFound
    case invalidResponse
    case installationIncomplete(StoreGameInstallationPlatform)
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
        case .noBuildsFound: "GOG does not provide a downloadable build for the selected platform."
        case .invalidResponse: "GOG returned Library data in an unsupported format."
        case .installationIncomplete(let platform):
            "GOG finished without creating a valid \(platform == .nativeMacOS ? "macOS" : "Windows") game installation."
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
                        let containerURL = gamesURL.appending(path: entry.externalID, directoryHint: .isDirectory)
                        let installation = Self.findInstallation(appID: entry.externalID, containerURL: containerURL, fileManager: fileManager)
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
                            isInstalled: installation != nil,
                            installPath: installation?.url.path,
                            installedPlatform: installation?.platform,
                            storageBytes: installation.flatMap { GameStorage.allocatedSize(of: $0.url, fileManager: fileManager) }
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
        return GOGReleaseNormalizer.deduplicate(games)
    }

    func install(appID: String, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        try await install(appID: appID, destinationRoot: gamesURL, progress: progress)
    }

    func loadSizeEstimate(appID: String, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate? {
        _ = try await credentials()
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.invalidResponse }
        let data = try await run([
            "info", appID,
            "--platform", platform == .nativeMacOS ? "osx" : "windows",
            "--lang", "en-US",
            "--skip-dlcs"
        ])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let size = root["size"] as? [String: Any] else {
            throw GOGServiceError.invalidResponse
        }
        let common = Self.sizeValues(size["*"])
        let language = Self.sizeValues(size["en-US"])
            ?? Self.sizeValues(size["en"])
            ?? size.first(where: { $0.key != "*" }).flatMap { Self.sizeValues($0.value) }
        let downloadBytes = Self.positiveSum(common?.downloadBytes, language?.downloadBytes)
        let installedBytes = Self.positiveSum(common?.installedBytes, language?.installedBytes)
        guard downloadBytes != nil || installedBytes != nil else { throw GOGServiceError.invalidResponse }
        return StoreGameSizeEstimate(
            downloadBytes: downloadBytes,
            installedBytes: installedBytes,
            source: .gogManifest,
            platform: platform,
            buildID: Self.stringValue(root["buildId"]),
            executableArchitecture: StoreArchitectureInference.fromManifest(root)
        )
    }

    func install(appID: String, destinationRoot: URL, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        try await install(appID: appID, destinationRoot: destinationRoot, platform: .windows, progress: progress)
    }

    func install(appID: String, destinationRoot: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        _ = try await credentials()
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.invalidResponse }
        // GOG metadata can advertise a legacy macOS release even when Galaxy
        // has no macOS build for gogdl to download. Check the actual build
        // catalogue before creating a download directory or starting a job.
        if platform == .nativeMacOS {
            _ = try await loadSizeEstimate(appID: appID, platform: platform)
        }
        let destination = destinationRoot.appending(path: appID, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let platformName = platform == .nativeMacOS ? "macOS" : "Windows"
        await progress(StoreGameOperationProgress(message: "Preparing GOG \(platformName) download…", fractionCompleted: nil))
        _ = try await run([
            "download", appID,
            "--path", destination.path,
            "--platform", platform == .nativeMacOS ? "osx" : "windows",
            "--skip-dlcs"
        ], progress: progress)
        try Task.checkCancellation()
        guard Self.findInstallation(appID: appID, containerURL: destination, platform: platform, fileManager: fileManager) != nil else {
            throw GOGServiceError.installationIncomplete(platform)
        }
    }

    func installationURL(appID: String, destinationRoot: URL, platform: StoreGameInstallationPlatform) async -> URL? {
        guard Self.isSafeAppID(appID) else { return nil }
        let container = destinationRoot.appending(path: appID, directoryHint: .isDirectory)
        return Self.findInstallation(appID: appID, containerURL: container, platform: platform, fileManager: fileManager)?.url
    }

    func update(appID: String, installationURL: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        try await maintain(command: "update", appID: appID, installationURL: installationURL, platform: platform, progress: progress)
    }

    func verify(appID: String, installationURL: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        try await maintain(command: "repair", appID: appID, installationURL: installationURL, platform: platform, progress: progress)
    }

    private func maintain(
        command: String,
        appID: String,
        installationURL: URL,
        platform: StoreGameInstallationPlatform,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        _ = try await credentials()
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.invalidResponse }
        let path = installationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
            ? installationURL.deletingLastPathComponent()
            : installationURL
        guard fileManager.fileExists(atPath: path.path) else {
            throw GOGServiceError.installationIncomplete(platform)
        }
        await progress(StoreGameOperationProgress(
            message: command == "repair" ? "Verifying GOG game files…" : "Checking GOG for updates…",
            fractionCompleted: nil,
            phase: command == "repair" ? .verifying : .preparing
        ))
        _ = try await run([
            command, appID,
            "--path", path.path,
            "--platform", platform == .nativeMacOS ? "osx" : "windows",
            "--skip-dlcs",
        ], progress: progress)
        try Task.checkCancellation()
    }

    private static func findInstallation(
        appID: String,
        containerURL: URL,
        platform: StoreGameInstallationPlatform? = nil,
        fileManager: FileManager
    ) -> (url: URL, platform: StoreGameInstallationPlatform)? {
        guard fileManager.fileExists(atPath: containerURL.path) else { return nil }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var directories = [containerURL]
        var nativeApplication: URL?
        var index = 0
        while index < directories.count {
            let directory = directories[index]
            index += 1
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for candidate in children {
                if candidate.lastPathComponent == "goggame-\(appID).info" {
                    if platform != .nativeMacOS { return (directory, .windows) }
                    continue
                }
                let values = try? candidate.resourceValues(forKeys: Set(keys))
                if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                   values?.isPackage == true,
                   fileManager.fileExists(
                       atPath: candidate
                           .appending(path: "Contents/MacOS", directoryHint: .isDirectory)
                           .path
                   ) {
                    nativeApplication = candidate
                    if platform == .nativeMacOS { return (candidate, .nativeMacOS) }
                } else if directory == containerURL, values?.isDirectory == true {
                    directories.append(candidate)
                }
            }
        }
        return nativeApplication.map { ($0, .nativeMacOS) }
    }

    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan {
        try await launchPlan(
            appID: appID,
            installationURL: gamesURL.appending(path: appID, directoryHint: .isDirectory),
            runtime: runtime,
            environment: environment
        )
    }

    func launchPlan(appID: String, installationURL: URL, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan {
        _ = runtime
        _ = environment
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.invalidLaunchPlan("invalid game ID") }
        let requestedDirectory = installationURL.resolvingSymlinksInPath().standardizedFileURL
        let gameDirectory: URL
        if fileManager.fileExists(atPath: requestedDirectory.appending(path: "goggame-\(appID).info").path) {
            gameDirectory = requestedDirectory
        } else if let discovered = Self.findInstallation(
            appID: appID,
            containerURL: requestedDirectory,
            platform: .windows,
            fileManager: fileManager
        )?.url {
            gameDirectory = discovered.resolvingSymlinksInPath().standardizedFileURL
        } else {
            gameDirectory = requestedDirectory
        }
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
        var arguments: [String]
        if let values = task["arguments"] as? [String] { arguments = values }
        else if let value = task["arguments"] as? String { arguments = Self.parseCommandLine(value) }
        else { arguments = [] }

        let configuration = Self.compatibilityLaunchConfiguration(
            appID: appID,
            runtimeEngine: runtime.resolvedEngine,
            arguments: arguments
        )
        return WindowsLaunchPlan(executable: executable, arguments: configuration.arguments, environment: configuration.environment, workingDirectory: workingDirectory)
    }

    nonisolated static func compatibilityLaunchConfiguration(
        appID: String,
        runtimeEngine: RuntimeEngine,
        arguments: [String]
    ) -> (arguments: [String], environment: [String: String]) {
        var arguments = arguments
        var environment: [String: String] = [:]

        if appID == "1196955511", runtimeEngine == .wine {
            // GOG marks Titan Quest's DirectX 11 task as primary, but the same
            // installation includes an official DirectX 9 launch mode. The
            // 32-bit game reaches WineD3D successfully and then rejects its
            // DX11 device, so use the publisher-provided fallback with Wine.
            arguments.removeAll {
                ["/dx11", "-dx11", "/dx9", "-dx9"].contains($0.lowercased())
            }
            arguments.append("/dx9")
            environment["WINED3D_RENDERER"] = "vulkan"
            return (arguments, environment)
        }

        guard appID == "2022341186" else { return (arguments, environment) }

        switch runtimeEngine {
        case .gamePortingToolkit:
            arguments.removeAll { $0.caseInsensitiveCompare("-dx9") == .orderedSame }
            if !arguments.contains(where: { $0.caseInsensitiveCompare("-dx10") == .orderedSame }) {
                arguments.append("-dx10")
            }
        case .wine:
            arguments.removeAll { $0.caseInsensitiveCompare("-dx10") == .orderedSame }
            if !arguments.contains(where: { $0.caseInsensitiveCompare("-dx9") == .orderedSame }) {
                arguments.append("-dx9")
            }
            // WineD3D's OpenGL card selector does not recognize Apple GPUs
            // on the affected runtime. Its Vulkan backend avoids that path.
            environment["WINED3D_RENDERER"] = "vulkan"
        }
        return (arguments, environment)
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

    private static func sizeValues(_ value: Any?) -> (downloadBytes: Int64?, installedBytes: Int64?)? {
        guard let value = value as? [String: Any] else { return nil }
        return (int64Value(value["download_size"]), int64Value(value["disk_size"]))
    }

    private static func positiveSum(_ first: Int64?, _ second: Int64?) -> Int64? {
        let values = [first, second].compactMap { value in value.flatMap { $0 > 0 ? $0 : nil } }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
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

    private func run(
        _ arguments: [String],
        progress: (@Sendable (StoreGameOperationProgress) async -> Void)? = nil
    ) async throws -> Data {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else { throw GOGServiceError.helperUnavailable }
        try fileManager.createDirectory(at: accountURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: configURL, withIntermediateDirectories: true)
        return try await Self.runProcess(
            executable: helperURL,
            arguments: ["--auth-config-path", authURL.path] + arguments,
            environment: ["GOGDL_CONFIG_PATH": configURL.path],
            progress: progress
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
        environment: [String: String],
        progress: (@Sendable (StoreGameOperationProgress) async -> Void)? = nil
    ) async throws -> Data {
        let processBox = CancellableStoreProcess()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let output = GOGOutputBuffer()
            let errorOutput = GOGOutputBuffer()
            let stdoutProgressBuffer = StoreProgressAccumulator(provider: "GOG")
            let stderrProgressBuffer = StoreProgressAccumulator(provider: "GOG")
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    output.append(data)
                    if let progress, let update = stdoutProgressBuffer.update(from: data) {
                        Task { await progress(update) }
                    }
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { errorOutput.append(data) }
                if !data.isEmpty, let progress, let update = stderrProgressBuffer.update(from: data) {
                    Task { await progress(update) }
                }
            }
            process.terminationHandler = { process in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                output.append(stdout.fileHandleForReading.readDataToEndOfFile())
                errorOutput.append(stderr.fileHandleForReading.readDataToEndOfFile())
                let capturedOutput = output.snapshot()
                let diagnosticOutput = capturedOutput + errorOutput.snapshot()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: capturedOutput)
                } else if String(data: diagnosticOutput, encoding: .utf8)?.localizedCaseInsensitiveContains("No builds found") == true {
                    continuation.resume(throwing: GOGServiceError.noBuildsFound)
                } else {
                    continuation.resume(throwing: GOGServiceError.commandFailed(process.terminationStatus))
                }
            }
            do { try process.run(); processBox.attach(process) }
            catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            processBox.cancel()
        }
        try Task.checkCancellation()
        return result
    }
}

nonisolated enum GOGReleaseNormalizer {
    private static let promotionalSuffixes = [
        " - Amazon Prime",
        " - Amazon Luna",
        " - Prime Giveaway"
    ]

    static func deduplicate(_ games: [StoreLibraryGame]) -> [StoreLibraryGame] {
        let baseNames = Set(games.compactMap { game -> String? in
            guard promotionalBaseName(game.name) == nil else { return nil }
            return comparisonKey(game.name)
        })
        let grouped = Dictionary(grouping: games) { game -> String in
            if let base = promotionalBaseName(game.name), baseNames.contains(comparisonKey(base)) {
                return "title:\(comparisonKey(base))"
            }
            let key = comparisonKey(game.name)
            return baseNames.contains(key) ? "title:\(key)" : "id:\(game.externalID)"
        }

        return grouped.values.map { candidates in
            guard candidates.count > 1,
                  let canonical = candidates.first(where: { promotionalBaseName($0.name) == nil }) else {
                return candidates[0]
            }
            let identity = candidates.first(where: { $0.isInstalled }) ?? canonical
            let metadata = candidates.max { metadataScore($0) < metadataScore($1) } ?? canonical
            var result = identity
            result.name = canonical.name
            result.developer = metadata.developer ?? result.developer
            result.summary = metadata.summary ?? result.summary
            result.artworkPath = metadata.artworkPath ?? result.artworkPath
            result.portraitImageURL = metadata.portraitImageURL ?? result.portraitImageURL
            result.headerImageURL = metadata.headerImageURL ?? result.headerImageURL
            result.backgroundImageURL = metadata.backgroundImageURL ?? result.backgroundImageURL
            result.screenshotURLs = metadata.screenshotURLs?.isEmpty == false ? metadata.screenshotURLs : result.screenshotURLs
            result.videos = metadata.videos?.isEmpty == false ? metadata.videos : result.videos
            result.storeRating = metadata.storeRating ?? result.storeRating
            result.supportsWindows = metadata.supportsWindows ?? result.supportsWindows
            result.supportsNativeMacOS = metadata.supportsNativeMacOS ?? result.supportsNativeMacOS
            return result
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func promotionalBaseName(_ name: String) -> String? {
        let lowercased = name.lowercased()
        for suffix in promotionalSuffixes where lowercased.hasSuffix(suffix.lowercased()) {
            return String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func comparisonKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func metadataScore(_ game: StoreLibraryGame) -> Int {
        (game.portraitImageURL == nil ? 0 : 4)
            + (game.headerImageURL == nil ? 0 : 2)
            + (game.backgroundImageURL == nil ? 0 : 2)
            + min(game.screenshotURLs?.count ?? 0, 10)
            + (game.summary?.isEmpty == false ? 2 : 0)
            + (game.developer?.isEmpty == false ? 1 : 0)
    }
}
