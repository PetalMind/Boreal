import CryptoKit
import Darwin
import Foundation

nonisolated struct GOGInstalledGameIdentity: Equatable, Sendable {
    let externalID: String
    let name: String?
    let buildID: String?
    let installationURL: URL
}

nonisolated struct GOGContentSystemBuild: Hashable, Sendable {
    let buildID: String
    let installedBuildID: String?
    let updateAvailable: Bool?
    let versionName: String?
    let publishedAt: String?
    let platform: StoreGameInstallationPlatform
}

nonisolated struct GOGContentSystemFile: Identifiable, Hashable, Sendable {
    let path: String
    let sizeBytes: Int64?
    let checksum: String?

    var id: String { path.lowercased() }
}

nonisolated struct GOGAdditionalContentItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String?
    let sizeBytes: Int64?
    let fileCount: Int
    let files: [GOGAdditionalContentFile]
}

nonisolated struct GOGAdditionalContentFile: Identifiable, Hashable, Sendable {
    let id: String
    let fileName: String
    let sizeBytes: Int64?
    let downlink: URL?
    let packageID: String?
    let category: String?
}

nonisolated struct GOGAdditionalContentGroup: Identifiable, Hashable, Sendable {
    let id: String
    let items: [GOGAdditionalContentItem]
}

nonisolated struct GOGAdditionalContentDownloadState: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case downloading
        case downloaded
        case failed
        case cancelled
    }

    var phase: Phase
    var transferredBytes: Int64 = 0
    var totalBytes: Int64?
    var networkBytesPerSecond: Double?
    var error: String?
    var startedAt: Date = .now
}

nonisolated enum GOGInstalledGameDetector {
    static func detect(executable: URL, fileManager: FileManager = .default) -> GOGInstalledGameIdentity? {
        let directory = executable.deletingLastPathComponent().standardizedFileURL
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for infoURL in entries where infoURL.lastPathComponent.hasPrefix("goggame-") && infoURL.pathExtension == "info" {
            guard let data = try? Data(contentsOf: infoURL),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let externalID = (root["gameId"] as? String) ?? (root["rootGameId"] as? String),
                  !externalID.isEmpty, externalID.allSatisfy(\.isNumber) else { continue }
            return GOGInstalledGameIdentity(
                externalID: externalID,
                name: root["name"] as? String,
                buildID: root["buildId"] as? String,
                installationURL: directory
            )
        }
        return nil
    }

    static func buildID(
        appID: String,
        installationURL: URL?,
        fileManager: FileManager = .default
    ) -> String? {
        guard let installationURL,
              appID.allSatisfy(\.isNumber),
              !appID.isEmpty else { return nil }
        let infoURL = installationURL.appending(path: "goggame-\(appID).info")
        guard fileManager.isReadableFile(atPath: infoURL.path),
              let data = try? Data(contentsOf: infoURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (root["buildId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func isDLCInstalled(
        productID: String,
        installationURL: URL?,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let installationURL,
              !productID.isEmpty,
              productID.allSatisfy(\.isNumber) else { return false }
        // GOG's SDK checks for this per-DLC mini-manifest in the game root.
        let miniManifestURL = installationURL.appending(path: "goggame-\(productID).info")
        return fileManager.fileExists(atPath: miniManifestURL.path)
    }
}

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

private nonisolated final class GOGAdditionalContentProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let transferredBytesBeforeFile: Int64
    private let knownTotalBytes: Int64?
    private let usesResponseTotal: Bool
    private let startedAt = Date()
    private let progress: @Sendable (Int64, Int64?, Double?) async -> Void

    init(
        transferredBytesBeforeFile: Int64,
        knownTotalBytes: Int64?,
        usesResponseTotal: Bool,
        progress: @escaping @Sendable (Int64, Int64?, Double?) async -> Void
    ) {
        self.transferredBytesBeforeFile = transferredBytesBeforeFile
        self.knownTotalBytes = knownTotalBytes
        self.usesResponseTotal = usesResponseTotal
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expectedBytes = knownTotalBytes
            ?? (usesResponseTotal && totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
        let totalTransferred = transferredBytesBeforeFile + totalBytesWritten
        let elapsed = Date.now.timeIntervalSince(startedAt)
        let speed = elapsed > 0 && totalBytesWritten > 0 ? Double(totalBytesWritten) / elapsed : nil
        Task { await progress(totalTransferred, expectedBytes, speed) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

nonisolated protocol GOGLibraryProviding: Sendable {
    func connectionState() async -> GOGConnectionState
    func prepareSupport() async throws
    func authenticate(authorizationCode: String) async throws -> String?
    func loadLibrary() async throws -> [StoreLibraryGame]
    func importPlaytimeMinutes(appID: String) async throws -> Int
    func additionalContent(appID: String) async throws -> [GOGAdditionalContentGroup]
    func downloadAdditionalContent(
        appID: String,
        groupID: String,
        item: GOGAdditionalContentItem,
        destinationRoot: URL,
        progress: @escaping @Sendable (Int64, Int64?, Double?) async -> Void
    ) async throws -> [URL]
    func contentSystemBuild(appID: String, platform: StoreGameInstallationPlatform, installationURL: URL?) async throws -> GOGContentSystemBuild
    func contentSystemFiles(appID: String, platform: StoreGameInstallationPlatform, buildID: String, installationURL: URL?) async throws -> [GOGContentSystemFile]
    func loadSizeEstimate(appID: String, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate?
    func availableLanguages(appID: String) async throws -> [String]
    func install(appID: String, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func install(appID: String, destinationRoot: URL, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func install(appID: String, destinationRoot: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func installationURL(appID: String, destinationRoot: URL, platform: StoreGameInstallationPlatform) async -> URL?
    func update(appID: String, installationURL: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func verify(appID: String, installationURL: URL, platform: StoreGameInstallationPlatform, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws
    func installLanguage(
        appID: String,
        installationURL: URL,
        platform: StoreGameInstallationPlatform,
        languageCode: String,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws
    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan
    func launchPlan(appID: String, installationURL: URL, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan
    func disconnect() async throws
}

extension GOGLibraryProviding {
    func importPlaytimeMinutes(appID: String) async throws -> Int {
        _ = appID
        throw CocoaError(.featureUnsupported)
    }

    func contentSystemBuild(appID: String, platform: StoreGameInstallationPlatform, installationURL: URL?) async throws -> GOGContentSystemBuild {
        _ = appID
        _ = platform
        _ = installationURL
        throw CocoaError(.featureUnsupported)
    }

    func contentSystemFiles(appID: String, platform: StoreGameInstallationPlatform, buildID: String, installationURL: URL?) async throws -> [GOGContentSystemFile] {
        _ = appID
        _ = platform
        _ = buildID
        _ = installationURL
        throw CocoaError(.featureUnsupported)
    }

    func additionalContent(appID: String) async throws -> [GOGAdditionalContentGroup] {
        _ = appID
        throw CocoaError(.featureUnsupported)
    }

    func downloadAdditionalContent(
        appID: String,
        groupID: String,
        item: GOGAdditionalContentItem,
        destinationRoot: URL,
        progress: @escaping @Sendable (Int64, Int64?, Double?) async -> Void
    ) async throws -> [URL] {
        _ = appID
        _ = groupID
        _ = item
        _ = destinationRoot
        _ = progress
        throw CocoaError(.featureUnsupported)
    }

    func availableLanguages(appID: String) async throws -> [String] {
        _ = appID
        throw CocoaError(.featureUnsupported)
    }

    func installLanguage(
        appID: String,
        installationURL: URL,
        platform: StoreGameInstallationPlatform,
        languageCode: String,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        _ = appID
        _ = installationURL
        _ = platform
        _ = languageCode
        _ = progress
        throw CocoaError(.featureUnsupported)
    }

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
    case cloudRefreshTokenUnavailable
    case cloudAuthorizationRejected
    case cloudAuthorizationFailed(Int)
    case cloudBuildsRequestFailed(Int)
    case cloudBuildsResponseInvalid
    case cloudMetadataRequestFailed(Int)
    case cloudMetadataResponseInvalid
    case cloudMetadataCredentialsMissing
    case cloudTokenResponseInvalid
    case credentialPersistenceFailed
    case additionalContentRequestFailed(Int)
    case additionalContentResponseInvalid
    case additionalContentDownloadUnavailable
    case additionalContentDownloadLinkInvalid
    case additionalContentDownloadFailed(Int)
    case playtimeRequestFailed(Int)
    case playtimeResponseInvalid
    case contentSystemRequestFailed(Int)
    case contentSystemResponseInvalid
    case contentSystemManifestInvalid
    case localManifestUnavailable
    case languageUpdateRequiresManifest
    case languageUnavailable(String)
    case commandFailed(Int32)
    case noBuildsFound
    case invalidResponse
    case installationIncomplete(StoreGameInstallationPlatform)
    case installationFolderMissing(String)
    case launchManifestMissing(String)
    case launchManifestInvalid(String)
    case invalidLaunchPlan(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture: "GOG support is not available for this Mac architecture."
        case .invalidAuthorizationCode: "Paste the code from GOG’s successful sign-in page."
        case .downloadFailed: "Boreal couldn’t download the verified GOG support component."
        case .verificationFailed: "The downloaded GOG support component failed SHA-256 verification and was not installed."
        case .helperUnavailable: "Install GOG support before connecting your account."
        case .notAuthenticated: "Connect your GOG account, then refresh the Library."
        case .cloudRefreshTokenUnavailable:
            "Your GOG account is connected, but Cloud Saves needs a refresh token. Reconnect the account in Boreal."
        case .cloudAuthorizationRejected:
            "GOG rejected the Cloud Saves authorization. Reconnect your GOG account in Boreal."
        case .cloudAuthorizationFailed(let status):
            "GOG could not refresh Cloud Saves authorization (HTTP \(status)). Try again later."
        case .cloudBuildsRequestFailed(let status):
            "GOG could not load Cloud Saves build information (HTTP \(status))."
        case .cloudBuildsResponseInvalid:
            "GOG returned Cloud Saves build information in an unsupported format."
        case .cloudMetadataRequestFailed(let status):
            "GOG could not load Cloud Saves metadata (HTTP \(status))."
        case .cloudMetadataResponseInvalid:
            "GOG returned Cloud Saves metadata in an unsupported format."
        case .cloudMetadataCredentialsMissing:
            "GOG’s Cloud Saves metadata did not include the game authorization credentials."
        case .cloudTokenResponseInvalid:
            "GOG returned an unsupported Cloud Saves authorization response."
        case .credentialPersistenceFailed:
            "Boreal could not save the refreshed GOG credentials. Reconnect your GOG account and try again."
        case .additionalContentRequestFailed(let status):
            "GOG could not load the additional content list (HTTP \(status))."
        case .additionalContentResponseInvalid:
            "GOG returned an unsupported additional content list."
        case .additionalContentDownloadUnavailable:
            "GOG does not provide downloadable files for this item."
        case .additionalContentDownloadLinkInvalid:
            "GOG returned an unsafe or unsupported additional content download link."
        case .additionalContentDownloadFailed(let status):
            "GOG could not download this additional content (HTTP \(status))."
        case .playtimeRequestFailed(let status):
            "GOG could not read account playtime (HTTP \(status)). The unofficial endpoint may be unavailable."
        case .playtimeResponseInvalid:
            "GOG returned account playtime in an unsupported format."
        case .contentSystemRequestFailed(let status):
            "GOG could not load Content System build information (HTTP \(status))."
        case .contentSystemResponseInvalid:
            "GOG returned unsupported Content System build information."
        case .contentSystemManifestInvalid:
            "GOG returned an unsupported Content System file manifest."
        case .localManifestUnavailable: "This offline GOG installation has not been adopted by Boreal yet."
        case .languageUpdateRequiresManifest: "Boreal can add a GOG language only when this installation has a managed GOG manifest."
        case .languageUnavailable(let code): "GOG does not offer the (code) language for this game build."
        case .commandFailed(let code): "GOG support stopped with exit code \(code)."
        case .noBuildsFound: "GOG does not provide a downloadable build for the selected platform."
        case .invalidResponse: "GOG returned data in an unsupported format."
        case .installationIncomplete(let platform):
            "GOG finished without creating a valid \(platform == .nativeMacOS ? "macOS" : "Windows") game installation."
        case .installationFolderMissing(let path):
            "The GOG installation folder is missing. Reconnect the disk or locate the installed game again: \(path)"
        case .launchManifestMissing(let path):
            "The GOG launch manifest is missing or unreadable. Locate the correct installation or verify the game files: \(path)"
        case .launchManifestInvalid(let path):
            "The GOG launch manifest contains invalid data. Verify the game files: \(path)"
        case .invalidLaunchPlan(let detail): "The installed GOG game has an unsafe or incomplete launch task: \(detail)"
        }
    }

    var requiresReauthentication: Bool {
        switch self {
        case .notAuthenticated, .cloudRefreshTokenUnavailable, .cloudAuthorizationRejected, .credentialPersistenceFailed:
            true
        default:
            false
        }
    }
}

actor GOGService: GOGLibraryProviding, GOGCloudAuthorizing {
    private struct ReleaseArtifact: Sendable {
        let url: URL
        let sha256: String
    }

    private struct Credentials: Decodable, Sendable {
        let accessToken: String
        let userID: String
        var refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case userID = "user_id"
            case refreshToken = "refresh_token"
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

    private struct ContentSystemBuildRecord: Sendable {
        let buildID: String
        let versionName: String?
        let publishedAt: String?
        let branch: String?
        let isPublic: Bool
        let generation: Int
        let link: URL
        let legacyBuildID: String?

        var localBuildID: String { legacyBuildID ?? buildID }
    }

    private let fileManager: FileManager
    private let session: URLSession
    private let rootURL: URL
    private let helperURL: URL
    private let accountURL: URL
    private let authURL: URL
    private let configURL: URL
    private let gamesURL: URL
    private var cloudAuthorizationCache: [String: GOGCloudAuthorization] = [:]

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
        cloudAuthorizationCache.removeAll()
        if let refreshToken = credentials.refreshToken, !refreshToken.isEmpty {
            try? GOGCredentialKeychain.store(refreshToken: refreshToken)
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

    func importPlaytimeMinutes(appID: String) async throws -> Int {
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.playtimeResponseInvalid }
        let credentials = try await credentials()
        guard Self.isSafeAppID(credentials.userID),
              let baseURL = URL(string: "https://gameplay.gog.com/clients/\(appID)/users/\(credentials.userID)/sessions") else {
            throw GOGServiceError.playtimeResponseInvalid
        }

        var totalMinutes = 0
        var pageToken: String?
        var seenPageTokens: Set<String> = []
        for _ in 0..<100 {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            if let pageToken {
                components?.queryItems = [URLQueryItem(name: "page_token", value: pageToken)]
            }
            guard let url = components?.url else { throw GOGServiceError.playtimeResponseInvalid }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GOGServiceError.playtimeResponseInvalid
            }
            guard httpResponse.statusCode == 200 else {
                throw GOGServiceError.playtimeRequestFailed(httpResponse.statusCode)
            }
            let page = try Self.playtimePage(from: data)
            totalMinutes += page.minutes
            guard let nextPageToken = page.nextPageToken else { return totalMinutes }
            guard seenPageTokens.insert(nextPageToken).inserted else {
                throw GOGServiceError.playtimeResponseInvalid
            }
            pageToken = nextPageToken
        }
        throw GOGServiceError.playtimeResponseInvalid
    }

    func install(appID: String, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        try await install(appID: appID, destinationRoot: gamesURL, progress: progress)
    }

    func contentSystemBuild(
        appID: String,
        platform: StoreGameInstallationPlatform,
        installationURL: URL?
    ) async throws -> GOGContentSystemBuild {
        let credentials = try await credentials()
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.contentSystemResponseInvalid }
        let builds = try await contentSystemBuilds(appID: appID, platform: platform, accessToken: credentials.accessToken)
        guard let latest = builds
            .filter({ $0.isPublic && Self.isMasterContentSystemBuild($0) })
            .sorted(by: Self.isNewerContentSystemBuild)
            .first else { throw GOGServiceError.noBuildsFound }

        let installedBuildID = GOGInstalledGameDetector.buildID(
            appID: appID,
            installationURL: installationURL,
            fileManager: fileManager
        )
        let installedBuild = installedBuildID.flatMap { buildID in
            builds.first(where: {
                $0.isPublic && Self.isMasterContentSystemBuild($0) && $0.localBuildID == buildID
            })
        }
        let updateAvailable: Bool? = {
            guard let installedBuildID, let installedBuild else { return nil }
            guard installedBuildID != latest.localBuildID else { return false }
            guard let latestPublishedAt = latest.publishedAt,
                  let installedPublishedAt = installedBuild.publishedAt else { return nil }
            return latestPublishedAt > installedPublishedAt
        }()

        return GOGContentSystemBuild(
            buildID: latest.localBuildID,
            installedBuildID: installedBuildID,
            updateAvailable: updateAvailable,
            versionName: latest.versionName,
            publishedAt: latest.publishedAt,
            platform: platform
        )
    }

    func contentSystemFiles(
        appID: String,
        platform: StoreGameInstallationPlatform,
        buildID: String,
        installationURL: URL?
    ) async throws -> [GOGContentSystemFile] {
        let credentials = try await credentials()
        guard Self.isSafeAppID(appID), !buildID.isEmpty else {
            throw GOGServiceError.contentSystemResponseInvalid
        }
        let builds = try await contentSystemBuilds(appID: appID, platform: platform, accessToken: credentials.accessToken)
        guard let build = builds.first(where: {
            $0.isPublic
                && Self.isMasterContentSystemBuild($0)
                && ($0.localBuildID == buildID || $0.buildID == buildID)
        }) else { throw GOGServiceError.contentSystemResponseInvalid }

        let repositoryData = try await contentSystemData(at: build.link, accessToken: credentials.accessToken)
        guard let repository = GOGCloudMetadataDecoder.object(from: repositoryData) as? [String: Any] else {
            throw GOGServiceError.contentSystemManifestInvalid
        }
        let isGenerationTwo = build.generation >= 2
        let depotList: [[String: Any]]
        if isGenerationTwo {
            depotList = repository["depots"] as? [[String: Any]] ?? []
        } else {
            depotList = (repository["product"] as? [String: Any])?["depots"] as? [[String: Any]] ?? []
        }
        guard !depotList.isEmpty else { throw GOGServiceError.contentSystemManifestInvalid }

        let installedLanguages = Self.installedLanguages(appID: appID, installationURL: installationURL)
        var filesByPath: [String: GOGContentSystemFile] = [:]
        for depot in depotList {
            if isGenerationTwo {
                if let productID = Self.stringValue(depot["productId"]), productID != appID { continue }
            } else if let gameIDs = depot["gameIDs"] as? [String], !gameIDs.isEmpty, !gameIDs.contains(appID) {
                continue
            }
            guard Self.contentDepotMatchesInstalledLanguage(depot, installedLanguages: installedLanguages),
                  let manifest = Self.stringValue(depot["manifest"]) else { continue }

            let manifestURL: URL?
            if isGenerationTwo {
                manifestURL = Self.contentSystemV2MetadataURL(hash: manifest)
            } else if let legacyBuildID = build.legacyBuildID ?? Int(build.buildID).map(String.init),
                      manifest.range(of: #"^[A-Fa-f0-9-]+\.json$"#, options: .regularExpression) != nil {
                manifestURL = URL(string: "https://cdn.gog.com/content-system/v1/manifests/\(appID)/\(platform == .nativeMacOS ? "osx" : "windows")/\(legacyBuildID)/\(manifest)")
            } else {
                manifestURL = nil
            }
            guard let manifestURL else { throw GOGServiceError.contentSystemManifestInvalid }
            let manifestData = try await contentSystemData(at: manifestURL, accessToken: credentials.accessToken)
            guard let root = GOGCloudMetadataDecoder.object(from: manifestData) as? [String: Any],
                  let depotRoot = root["depot"] as? [String: Any] else {
                throw GOGServiceError.contentSystemManifestInvalid
            }
            let manifestFiles: [[String: Any]]
            if isGenerationTwo {
                manifestFiles = depotRoot["items"] as? [[String: Any]] ?? []
            } else {
                manifestFiles = depotRoot["files"] as? [[String: Any]] ?? []
            }
            for item in manifestFiles {
                guard let path = Self.stringValue(item["path"]), !path.isEmpty else { continue }
                let chunks = item["chunks"] as? [[String: Any]] ?? []
                let chunkSize = chunks.compactMap { Self.int64Value($0["size"]) }.reduce(0, +)
                let size = Self.int64Value(item["size"]) ?? (chunkSize > 0 ? chunkSize : nil)
                let file = GOGContentSystemFile(
                    path: path.replacingOccurrences(of: "\\", with: "/"),
                    sizeBytes: size,
                    checksum: Self.stringValue(item[isGenerationTwo ? "md5" : "hash"])
                )
                filesByPath[file.id] = file
            }
        }
        guard !filesByPath.isEmpty else { throw GOGServiceError.contentSystemManifestInvalid }
        return filesByPath.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
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

    func additionalContent(appID: String) async throws -> [GOGAdditionalContentGroup] {
        let credentials = try await credentials()
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.additionalContentResponseInvalid }

        var components = URLComponents(string: "https://api.gog.com/products/\(appID)")!
        components.queryItems = [URLQueryItem(name: "expand", value: "downloads,expanded_dlcs")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GOGServiceError.additionalContentResponseInvalid
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw GOGServiceError.notAuthenticated
            }
            throw GOGServiceError.additionalContentRequestFailed(httpResponse.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GOGServiceError.additionalContentResponseInvalid
        }

        var groups: [GOGAdditionalContentGroup] = []
        let downloads = root["downloads"] as? [String: Any] ?? [:]
        for key in ["bonus_content", "language_packs", "patches"] {
            guard let entries = downloads[key] as? [[String: Any]] else { continue }
            let items = entries.enumerated().compactMap { index, entry in
                Self.additionalContentItem(entry, fallbackPrefix: key, index: index)
            }
            if !items.isEmpty {
                groups.append(GOGAdditionalContentGroup(id: key, items: items))
            }
        }

        if let dlcs = root["expanded_dlcs"] as? [[String: Any]] {
            let items = dlcs.enumerated().compactMap { index, dlc in
                Self.additionalContentItem(dlc, fallbackPrefix: "dlc", index: index)
            }
            if !items.isEmpty {
                groups.append(GOGAdditionalContentGroup(id: "dlc", items: items))
            }
        }
        return groups
    }

    func downloadAdditionalContent(
        appID: String,
        groupID: String,
        item: GOGAdditionalContentItem,
        destinationRoot: URL,
        progress: @escaping @Sendable (Int64, Int64?, Double?) async -> Void
    ) async throws -> [URL] {
        let credentials = try await credentials()
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.additionalContentResponseInvalid }

        var productID = appID
        var files = item.files
        if groupID == "dlc" {
            guard Self.isSafeAppID(item.id) else { throw GOGServiceError.additionalContentResponseInvalid }
            productID = item.id
            let dlc = try await productMetadata(appID: productID, expand: "downloads", credentials: credentials)
            let downloads = dlc["downloads"] as? [String: Any] ?? [:]
            let dlcFiles = ["installers", "bonus_content", "language_packs", "patches"].flatMap { category in
                let entries = downloads[category] as? [[String: Any]] ?? []
                return entries.enumerated().flatMap { packageIndex, entry in
                    let packageID = "\(category)-\(Self.stringValue(entry["id"]) ?? String(packageIndex + 1))"
                    let packageFiles = entry["files"] as? [[String: Any]] ?? []
                    return packageFiles.enumerated().compactMap { fileIndex, value in
                        Self.additionalContentFile(
                            value,
                            fallbackPrefix: packageID,
                            index: fileIndex,
                            packageID: packageID,
                            category: category
                        )
                    }
                }
            }
            if !dlcFiles.isEmpty { files = dlcFiles }
        }
        guard !files.isEmpty else { throw GOGServiceError.additionalContentDownloadUnavailable }

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let completionMarker = destinationRoot.appending(path: ".boreal-gog-content-complete")
        try? fileManager.removeItem(at: completionMarker)
        let expectedSizes = files.map(\.sizeBytes)
        let knownTotalBytes = !expectedSizes.isEmpty && expectedSizes.allSatisfy { $0 != nil }
            ? expectedSizes.compactMap { $0 }.reduce(Int64(0), +)
            : nil
        var downloadedURLs: [URL] = []
        var transferredBytes: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let packageDirectory = file.packageID.map(Self.safePathComponent)
                .map { destinationRoot.appending(path: $0, directoryHint: .isDirectory) }
                ?? destinationRoot
            try fileManager.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            let indexURL = packageDirectory.appending(path: ".boreal-gog-content.json")
            var downloadedFileNames = (try? Data(contentsOf: indexURL))
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            var destinationName = Self.safeAdditionalContentFilename(downloadedFileNames[file.id] ?? file.fileName)
            var destination = packageDirectory.appending(path: destinationName)

            if Self.isCompleteAdditionalContentFile(destination, expectedSize: file.sizeBytes) {
                downloadedURLs.append(destination)
                let fileBytes = file.sizeBytes ?? Self.additionalContentFileSize(destination)
                transferredBytes += fileBytes
                await progress(transferredBytes, knownTotalBytes, nil)
                continue
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            let category = file.category ?? (groupID == "dlc" ? "installers" : groupID)
            let downlinkEndpoint = try Self.additionalContentDownlinkEndpoint(
                file.downlink,
                productID: productID,
                category: category,
                fileID: file.id
            )
            var downlinkRequest = URLRequest(url: downlinkEndpoint)
            downlinkRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            downlinkRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            let (linkData, linkResponse) = try await session.data(for: downlinkRequest)
            guard let linkHTTPResponse = linkResponse as? HTTPURLResponse else {
                throw GOGServiceError.additionalContentResponseInvalid
            }
            if linkHTTPResponse.statusCode == 401 || linkHTTPResponse.statusCode == 403 {
                throw GOGServiceError.notAuthenticated
            }
            guard (200..<300).contains(linkHTTPResponse.statusCode),
                  let linkRoot = try? JSONSerialization.jsonObject(with: linkData) as? [String: Any],
                  let signedLink = Self.stringValue(linkRoot["downlink"]),
                  let downloadURL = URL(string: signedLink),
                  downloadURL.scheme?.lowercased() == "https",
                  downloadURL.host != nil else {
                throw GOGServiceError.additionalContentDownloadLinkInvalid
            }

            let progressDelegate = GOGAdditionalContentProgressDelegate(
                transferredBytesBeforeFile: transferredBytes,
                knownTotalBytes: knownTotalBytes,
                usesResponseTotal: files.count == 1,
                progress: progress
            )
            let downloadRequest = URLRequest(url: downloadURL)
            let (temporaryURL, response) = try await session.download(for: downloadRequest, delegate: progressDelegate)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GOGServiceError.additionalContentResponseInvalid
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw GOGServiceError.additionalContentDownloadFailed(httpResponse.statusCode)
            }
            if URL(fileURLWithPath: destinationName).pathExtension.isEmpty,
               let suggestedFilename = httpResponse.suggestedFilename,
               !URL(fileURLWithPath: suggestedFilename).pathExtension.isEmpty {
                destinationName = Self.safeAdditionalContentFilename(suggestedFilename)
                destination = packageDirectory.appending(path: destinationName)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            downloadedFileNames[file.id] = destinationName
            if let indexData = try? JSONEncoder().encode(downloadedFileNames) {
                try? indexData.write(to: indexURL, options: .atomic)
            }
            downloadedURLs.append(destination)
            let fileBytes = file.sizeBytes ?? Self.additionalContentFileSize(destination)
            transferredBytes += fileBytes
            await progress(transferredBytes, knownTotalBytes, nil)
        }
        let relativePaths = downloadedURLs.map { String($0.path.dropFirst(destinationRoot.path.count + 1)) }
        try JSONEncoder().encode(relativePaths).write(to: completionMarker, options: .atomic)
        return downloadedURLs
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
        var arguments = [
            "download", appID,
            "--path", destination.path,
            "--platform", platform == .nativeMacOS ? "osx" : "windows",
            "--max-workers", String(StoreDownloadConcurrency.maxWorkers),
        ]
        if platform == .windows, let languageCode = preferredLanguage(appID: appID) {
            arguments += ["--lang", languageCode]
        }
        arguments.append("--skip-dlcs")
        _ = try await run(arguments, progress: progress)
        try Task.checkCancellation()
        if platform == .windows,
           Self.findInstallation(appID: appID, containerURL: destination, platform: platform, fileManager: fileManager) == nil,
           let recoveryURL = incompleteInstallationRecoveryURL(appID: appID, containerURL: destination) {
            // A retained gogdl manifest can make download report "Nothing to do"
            // even after the installation has been removed. Repair checks the
            // actual files. Unlike download, it needs the game directory itself.
            await progress(StoreGameOperationProgress(
                message: "Restoring missing GOG game files…",
                fractionCompleted: nil,
                phase: .verifying
            ))
            _ = try await run([
                "repair", appID,
                "--path", recoveryURL.path,
                "--platform", "windows",
                "--max-workers", String(StoreDownloadConcurrency.maxWorkers),
                "--skip-dlcs"
            ], progress: progress)
            try Task.checkCancellation()
        }
        guard Self.findInstallation(appID: appID, containerURL: destination, platform: platform, fileManager: fileManager) != nil else {
            throw GOGServiceError.installationIncomplete(platform)
        }
    }

    private func incompleteInstallationRecoveryURL(appID: String, containerURL: URL) -> URL? {
        let manifestURL = configURL.appending(path: "heroic_gogdl/manifests/\(appID)")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["platform"] as? String == "windows",
              manifest["baseProductId"] as? String == appID,
              let directory = manifest["installDirectory"] as? String,
              !directory.isEmpty,
              directory != ".", directory != "..",
              !directory.contains("/"), !directory.contains("\\") else { return nil }
        let container = containerURL.standardizedFileURL.resolvingSymlinksInPath()
        let recoveryURL = container.appending(path: directory, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard recoveryURL.path.hasPrefix(container.path + "/") else { return nil }
        return recoveryURL
    }

    func availableLanguages(appID: String) async throws -> [String] {
        _ = try await credentials()
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.invalidResponse }
        let manifestURL = configURL.appending(path: "heroic_gogdl/manifests/\(appID)")
        guard fileManager.isReadableFile(atPath: manifestURL.path) else {
            throw GOGServiceError.languageUpdateRequiresManifest
        }
        let data = try await run([
            "info", appID,
            "--platform", "windows",
            "--lang", "pl-PL",
            "--skip-dlcs"
        ])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let languages = root["languages"] as? [String] else {
            throw GOGServiceError.invalidResponse
        }
        return Array(Set(languages.filter { !$0.isEmpty })).sorted { lhs, rhs in
            let left = Locale.current.localizedString(forIdentifier: lhs) ?? lhs
            let right = Locale.current.localizedString(forIdentifier: rhs) ?? rhs
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    func installLanguage(
        appID: String,
        installationURL: URL,
        platform: StoreGameInstallationPlatform,
        languageCode: String,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        _ = try await credentials()
        guard Self.isSafeAppID(appID), platform == .windows else { throw GOGServiceError.invalidResponse }
        let path = installationURL.standardizedFileURL
        guard fileManager.fileExists(atPath: path.path) else {
            throw GOGServiceError.installationIncomplete(platform)
        }
        let manifestURL = configURL.appending(path: "heroic_gogdl/manifests/\(appID)")
        guard fileManager.isReadableFile(atPath: manifestURL.path) else {
            throw GOGServiceError.languageUpdateRequiresManifest
        }
        let available = try await availableLanguages(appID: appID)
        guard available.contains(languageCode) else { throw GOGServiceError.languageUnavailable(languageCode) }

        await progress(StoreGameOperationProgress(
            message: "Preparing the GOG \(languageCode) language files…",
            fractionCompleted: nil,
            phase: .preparing
        ))
        _ = try await run([
            "update", appID,
            "--path", path.path,
            "--platform", "windows",
            "--lang", languageCode,
            "--skip-dlcs"
        ], progress: progress)
        try Task.checkCancellation()
        try savePreferredLanguage(languageCode, appID: appID)
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
        let platformArgument = platform == .nativeMacOS ? "osx" : "windows"
        var arguments = [
            command, appID,
            "--path", path.path,
            "--platform", platformArgument,
            "--max-workers", String(StoreDownloadConcurrency.maxWorkers),
        ]
        if command == "update", let languageCode = preferredLanguage(appID: appID) {
            arguments += ["--lang", languageCode]
        }
        arguments.append("--skip-dlcs")
        do {
            _ = try await run(arguments, progress: progress)
        } catch GOGServiceError.localManifestUnavailable where command == "repair" {
            // Offline installers ship GOG's hash database, not gogdl's local
            // manifest. The first managed download adopts the existing path,
            // compares it with the current store build, and establishes the
            // manifest used by subsequent lightweight repair operations.
            await progress(StoreGameOperationProgress(
                message: "Adopting the offline GOG installation and restoring its files…",
                fractionCompleted: nil,
                phase: .verifying
            ))
            var adoptionArguments = [
                "download", appID,
                "--path", path.path,
                "--platform", platformArgument,
                "--max-workers", String(StoreDownloadConcurrency.maxWorkers),
            ]
            if let languageCode = preferredLanguage(appID: appID) {
                adoptionArguments += ["--lang", languageCode]
            }
            adoptionArguments.append("--skip-dlcs")
            _ = try await run(adoptionArguments, progress: progress)
        }
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
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: requestedDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GOGServiceError.installationFolderMissing(requestedDirectory.path)
        }
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
        guard let data = try? Data(contentsOf: infoURL) else {
            throw GOGServiceError.launchManifestMissing(infoURL.path)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GOGServiceError.launchManifestInvalid(infoURL.path)
        }
        guard let tasks = root["playTasks"] as? [[String: Any]],
              let primaryTask = tasks.first(where: { ($0["isPrimary"] as? Bool) == true && ($0["type"] as? String) != "URLTask" })
                ?? tasks.first(where: { ($0["type"] as? String) != "URLTask" }),
              let primaryRelativeExecutable = primaryTask["path"] as? String,
              !primaryRelativeExecutable.isEmpty else {
            throw GOGServiceError.invalidLaunchPlan("no executable play task")
        }
        // The Witcher 3's official GOG task launches REDprelauncher, which
        // opens REDlauncher. REDlauncher crashes under the Wine runtime used
        // by Boreal before the game starts, even though GOG also provides a
        // direct, hidden game task in the same manifest.
        let task = Self.witcher3DirectLaunchTask(primaryTask: primaryTask, tasks: tasks) ?? primaryTask
        guard let relativeExecutable = task["path"] as? String,
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
        var plan = WindowsLaunchPlan(
            executable: executable,
            arguments: configuration.arguments,
            environment: configuration.environment,
            workingDirectory: workingDirectory
        )

        // GOG metadata can expose a launcher as the primary task while the
        // actual game is a hidden secondary task. When the launcher is kept,
        // identify the game process that owns the user-visible session after
        // the launcher exits.
        if let gameExecutable = Self.gameExecutable(
            in: tasks,
            primaryRelativePath: primaryRelativeExecutable,
            gameDirectory: gameDirectory
        ) {
            plan.processExecutableName = gameExecutable.lastPathComponent
            plan.processExecutablePath = gameExecutable.path
        }
        return plan
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
            environment["WINE_D3D_CONFIG"] = "renderer=vulkan"
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
            environment["WINE_D3D_CONFIG"] = "renderer=vulkan"
        }
        return (arguments, environment)
    }

    func disconnect() async throws {
        let helperAvailable = fileManager.isExecutableFile(atPath: helperURL.path)
        if fileManager.fileExists(atPath: authURL.path) { try fileManager.removeItem(at: authURL) }
        try? GOGCredentialKeychain.remove()
        cloudAuthorizationCache.removeAll()
        guard helperAvailable else { throw GOGServiceError.helperUnavailable }
    }

    func cloudAuthorization(for appID: String) async throws -> GOGCloudAuthorization {
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.invalidResponse }
        if let cached = cloudAuthorizationCache[appID], cached.expiresAt.map({ $0.timeIntervalSinceNow > 60 }) ?? true {
            return cached
        }
        let base = try await credentials()

        var buildsComponents = URLComponents(string: "https://content-system.gog.com/products/\(appID)/os/windows/builds")!
        buildsComponents.queryItems = [URLQueryItem(name: "generation", value: "2")]
        var buildsRequest = URLRequest(url: buildsComponents.url!)
        buildsRequest.setValue("Bearer \(base.accessToken)", forHTTPHeaderField: "Authorization")
        buildsRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (buildsData, buildsResponse) = try await session.data(for: buildsRequest)
        guard let buildsHTTPResponse = buildsResponse as? HTTPURLResponse else {
            throw GOGServiceError.cloudBuildsResponseInvalid
        }
        guard buildsHTTPResponse.statusCode == 200 else {
            if buildsHTTPResponse.statusCode == 401 || buildsHTTPResponse.statusCode == 403 {
                throw GOGServiceError.cloudAuthorizationRejected
            }
            throw GOGServiceError.cloudBuildsRequestFailed(buildsHTTPResponse.statusCode)
        }
        guard let buildsRoot = GOGCloudMetadataDecoder.object(from: buildsData) as? [String: Any],
              let items = buildsRoot["items"] as? [[String: Any]],
              let metadataLink = items.compactMap({ $0["link"] as? String }).first,
              let metadataURL = URL(string: metadataLink),
              metadataURL.scheme?.lowercased() == "https" else {
            throw GOGServiceError.cloudBuildsResponseInvalid
        }

        var metadataRequest = URLRequest(url: metadataURL)
        metadataRequest.setValue("Bearer \(base.accessToken)", forHTTPHeaderField: "Authorization")
        let (metadataData, metadataResponse) = try await session.data(for: metadataRequest)
        guard let metadataHTTPResponse = metadataResponse as? HTTPURLResponse else {
            throw GOGServiceError.cloudMetadataResponseInvalid
        }
        guard metadataHTTPResponse.statusCode == 200 else {
            if metadataHTTPResponse.statusCode == 401 || metadataHTTPResponse.statusCode == 403 {
                throw GOGServiceError.cloudAuthorizationRejected
            }
            throw GOGServiceError.cloudMetadataRequestFailed(metadataHTTPResponse.statusCode)
        }
        guard let metadata = GOGCloudMetadataDecoder.object(from: metadataData) as? [String: Any] else {
            throw GOGServiceError.cloudMetadataResponseInvalid
        }
        guard let clientID = Self.stringValue(metadata["clientId"]),
              let clientSecret = Self.stringValue(metadata["clientSecret"]),
              !clientID.isEmpty,
              !clientSecret.isEmpty else {
            throw GOGServiceError.cloudMetadataCredentialsMissing
        }
        guard let refreshToken = base.refreshToken, !refreshToken.isEmpty else {
            throw GOGServiceError.cloudRefreshTokenUnavailable
        }

        var tokenComponents = URLComponents(string: "https://auth.gog.com/token")!
        tokenComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "without_new_session", value: "1"),
        ]
        var tokenRequest = URLRequest(url: tokenComponents.url!)
        tokenRequest.httpMethod = "GET"
        let (tokenData, tokenResponse) = try await session.data(for: tokenRequest)
        guard let httpResponse = tokenResponse as? HTTPURLResponse else {
            throw GOGServiceError.cloudTokenResponseInvalid
        }
        guard httpResponse.statusCode == 200 else {
            let oauthError = (try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any])?["error"] as? String
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 || oauthError == "invalid_grant" {
                throw GOGServiceError.cloudAuthorizationRejected
            }
            throw GOGServiceError.cloudAuthorizationFailed(httpResponse.statusCode)
        }
        guard let tokenRoot = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let accessToken = tokenRoot["access_token"] as? String,
              !accessToken.isEmpty else {
            throw GOGServiceError.cloudTokenResponseInvalid
        }
        if let refreshedToken = Self.stringValue(tokenRoot["refresh_token"]),
           !refreshedToken.isEmpty,
           refreshedToken != refreshToken {
            try persistRefreshToken(refreshedToken)
        }
        let userID = Self.stringValue(tokenRoot["user_id"]) ?? base.userID
        let expiresAt = (tokenRoot["expires_in"] as? NSNumber).map { Date().addingTimeInterval($0.doubleValue) }
        let authorization = GOGCloudAuthorization(
            userID: userID,
            accessToken: accessToken,
            clientID: clientID,
            expiresAt: expiresAt
        )
        if expiresAt != nil {
            cloudAuthorizationCache[appID] = authorization
        }
        return authorization
    }

    private func credentials() async throws -> Credentials {
        guard fileManager.fileExists(atPath: authURL.path) else { throw GOGServiceError.notAuthenticated }
        let data = try await run(["auth"])
        guard var credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              !credentials.accessToken.isEmpty, !credentials.userID.isEmpty else {
            throw GOGServiceError.notAuthenticated
        }
        if credentials.refreshToken?.isEmpty != false {
            credentials.refreshToken = persistedRefreshToken() ?? (try? GOGCredentialKeychain.read())
        } else if let refreshToken = credentials.refreshToken {
            try? GOGCredentialKeychain.store(refreshToken: refreshToken)
        }
        return credentials
    }

    private func persistedRefreshToken() -> String? {
        guard let data = try? Data(contentsOf: authURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let refreshToken = Self.stringValue(root["refresh_token"]),
              !refreshToken.isEmpty else { return nil }
        return refreshToken
    }

    private func persistRefreshToken(_ refreshToken: String) throws {
        guard let data = try? Data(contentsOf: authURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GOGServiceError.credentialPersistenceFailed
        }
        root["refresh_token"] = refreshToken
        do {
            let updatedData = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            try updatedData.write(to: authURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
            try? GOGCredentialKeychain.store(refreshToken: refreshToken)
        } catch {
            throw GOGServiceError.credentialPersistenceFailed
        }
    }

    private static func sizeValues(_ value: Any?) -> (downloadBytes: Int64?, installedBytes: Int64?)? {
        guard let value = value as? [String: Any] else { return nil }
        return (int64Value(value["download_size"]), int64Value(value["disk_size"]))
    }

    private func contentSystemBuilds(
        appID: String,
        platform: StoreGameInstallationPlatform,
        accessToken: String
    ) async throws -> [ContentSystemBuildRecord] {
        let os = platform == .nativeMacOS ? "osx" : "windows"
        var components = URLComponents(string: "https://content-system.gog.com/products/\(appID)/os/\(os)/builds")!
        components.queryItems = [URLQueryItem(name: "generation", value: "2")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GOGServiceError.contentSystemResponseInvalid
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw GOGServiceError.notAuthenticated }
            throw GOGServiceError.contentSystemRequestFailed(httpResponse.statusCode)
        }
        guard let root = GOGCloudMetadataDecoder.object(from: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            throw GOGServiceError.contentSystemResponseInvalid
        }
        return items.compactMap { item in
            guard let buildID = Self.stringValue(item["build_id"]),
                  let linkValue = Self.stringValue(item["link"]),
                  let link = URL(string: linkValue),
                  link.scheme?.lowercased() == "https",
                  link.host?.lowercased() == "cdn.gog.com" else { return nil }
            return ContentSystemBuildRecord(
                buildID: buildID,
                versionName: Self.stringValue(item["version_name"]).flatMap { $0.isEmpty ? nil : $0 },
                publishedAt: Self.stringValue(item["date_published"]),
                branch: Self.stringValue(item["branch"]),
                isPublic: (item["public"] as? Bool) ?? false,
                generation: Self.intValue(item["generation"]) ?? 1,
                link: link,
                legacyBuildID: Self.stringValue(item["legacy_build_id"])
            )
        }
    }

    private func contentSystemData(at url: URL, accessToken: String) async throws -> Data {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "cdn.gog.com" else {
            throw GOGServiceError.contentSystemManifestInvalid
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GOGServiceError.contentSystemManifestInvalid
        }
        guard httpResponse.statusCode == 200 else {
            throw GOGServiceError.contentSystemRequestFailed(httpResponse.statusCode)
        }
        return data
    }

    private static func isNewerContentSystemBuild(_ lhs: ContentSystemBuildRecord, _ rhs: ContentSystemBuildRecord) -> Bool {
        if lhs.publishedAt != rhs.publishedAt { return (lhs.publishedAt ?? "") > (rhs.publishedAt ?? "") }
        if lhs.generation != rhs.generation { return lhs.generation > rhs.generation }
        return lhs.localBuildID > rhs.localBuildID
    }

    private static func isMasterContentSystemBuild(_ build: ContentSystemBuildRecord) -> Bool {
        guard let branch = build.branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty else {
            return true
        }
        return branch.caseInsensitiveCompare("master") == .orderedSame
    }

    private static func contentSystemV2MetadataURL(hash: String) -> URL? {
        guard hash.range(of: #"^[A-Fa-f0-9]{32}$"#, options: .regularExpression) != nil else { return nil }
        let normalized = hash.lowercased()
        let first = normalized.prefix(2)
        let second = normalized.dropFirst(2).prefix(2)
        return URL(string: "https://cdn.gog.com/content-system/v2/meta/\(first)/\(second)/\(normalized)")
    }

    private static func installedLanguages(appID: String, installationURL: URL?) -> [String] {
        guard let installationURL else { return [] }
        let infoURL = installationURL.appending(path: "goggame-\(appID).info")
        guard let data = try? Data(contentsOf: infoURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return (root["languages"] as? [String] ?? []) + [stringValue(root["language"])].compactMap { $0 }
    }

    private static func contentDepotMatchesInstalledLanguage(_ depot: [String: Any], installedLanguages: [String]) -> Bool {
        let depotLanguages = depot["languages"] as? [String] ?? []
        guard !depotLanguages.isEmpty else { return true }
        if depotLanguages.contains(where: { ["*", "neutral"].contains($0.lowercased()) }) || installedLanguages.isEmpty {
            return true
        }
        let installed = Set(installedLanguages.flatMap(contentLanguageAliases))
        return depotLanguages.flatMap(contentLanguageAliases).contains(where: installed.contains)
    }

    private static func contentLanguageAliases(_ value: String) -> [String] {
        let normalized = value.lowercased().replacingOccurrences(of: "_", with: "-")
        let aliases: [String: String] = [
            "english": "en", "french": "fr", "german": "de", "spanish": "es",
            "italian": "it", "polish": "pl", "russian": "ru", "portuguese": "pt",
            "brazilian": "pt-br", "japanese": "ja", "korean": "ko", "chinese": "zh",
            "dutch": "nl", "czech": "cs", "hungarian": "hu", "turkish": "tr",
            "ukrainian": "uk", "swedish": "sv", "norwegian": "no", "danish": "da",
            "finnish": "fi", "thai": "th", "greek": "el", "arabic": "ar",
        ]
        let base = aliases[normalized] ?? normalized.split(separator: "-").first.map(String.init) ?? normalized
        return [normalized, base]
    }

    private static func additionalContentItem(
        _ value: [String: Any],
        fallbackPrefix: String,
        index: Int
    ) -> GOGAdditionalContentItem? {
        let files = value["files"] as? [[String: Any]] ?? []
        let identifier = stringValue(value["id"])
            ?? stringValue(value["product_id"])
            ?? "\(fallbackPrefix)-\(index)"
        let parsedFiles = files.enumerated().compactMap { fileIndex, file in
            additionalContentFile(
                file,
                fallbackPrefix: identifier,
                index: fileIndex,
                category: fallbackPrefix == "dlc" ? nil : fallbackPrefix
            )
        }
        let sizes = parsedFiles.compactMap(\.sizeBytes).filter { $0 > 0 }
        let reportedSize = int64Value(value["total_size"]).flatMap { $0 > 0 ? $0 : nil }
        let fallbackName = stringValue(value["id"]).map { identifier in
            fallbackPrefix == "dlc" ? "DLC \(identifier)" : identifier
        }
        let name = localized(value["name"])
            ?? localized(value["title"])
            ?? fallbackName
            ?? "\(fallbackPrefix) \(index + 1)"
        return GOGAdditionalContentItem(
            id: identifier,
            name: name,
            kind: stringValue(value["type"]),
            sizeBytes: reportedSize ?? (sizes.isEmpty ? nil : sizes.reduce(0, +)),
            fileCount: parsedFiles.count,
            files: parsedFiles
        )
    }

    private static func additionalContentFile(
        _ value: [String: Any],
        fallbackPrefix: String,
        index: Int,
        packageID: String? = nil,
        category: String? = nil
    ) -> GOGAdditionalContentFile? {
        let identifier = stringValue(value["id"]) ?? "\(fallbackPrefix)-\(index + 1)"
        let fileName = localized(value["name"])
            ?? stringValue(value["file_name"])
            ?? stringValue(value["filename"])
            ?? identifier
        let downlink = stringValue(value["downlink"]).flatMap(URL.init(string:))
        return GOGAdditionalContentFile(
            id: identifier,
            fileName: fileName,
            sizeBytes: int64Value(value["size"]).flatMap { $0 > 0 ? $0 : nil },
            downlink: downlink,
            packageID: packageID,
            category: category
        )
    }

    private func productMetadata(
        appID: String,
        expand: String,
        credentials: Credentials
    ) async throws -> [String: Any] {
        guard Self.isSafeAppID(appID) else { throw GOGServiceError.additionalContentResponseInvalid }
        var components = URLComponents(string: "https://api.gog.com/products/\(appID)")!
        components.queryItems = [URLQueryItem(name: "expand", value: expand)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GOGServiceError.additionalContentResponseInvalid
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw GOGServiceError.notAuthenticated
        }
        guard httpResponse.statusCode == 200 else {
            throw GOGServiceError.additionalContentRequestFailed(httpResponse.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GOGServiceError.additionalContentResponseInvalid
        }
        return root
    }

    private static func additionalContentDownlinkEndpoint(
        _ suppliedURL: URL?,
        productID: String,
        category: String,
        fileID: String
    ) throws -> URL {
        guard isSafeAppID(productID) else { throw GOGServiceError.additionalContentDownloadLinkInvalid }
        let endpoint: URL
        if let suppliedURL {
            endpoint = suppliedURL
        } else {
            let safeCategory = safePathComponent(category)
            let safeFileID = safePathComponent(fileID)
            guard safeCategory == category, safeFileID == fileID,
                  let generated = URL(string: "https://api.gog.com/products/\(productID)/downlink/\(category)/\(fileID)") else {
                throw GOGServiceError.additionalContentDownloadLinkInvalid
            }
            endpoint = generated
        }
        let parts = endpoint.pathComponents
        guard endpoint.scheme?.lowercased() == "https",
              endpoint.host?.lowercased() == "api.gog.com",
              parts.count >= 5,
              parts[1] == "products",
              parts[2] == productID,
              parts[3] == "downlink",
              parts.dropFirst(4).allSatisfy({ safePathComponent($0) == $0 }) else {
            throw GOGServiceError.additionalContentDownloadLinkInvalid
        }
        return endpoint
    }

    private nonisolated static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return result.isEmpty || result == "." || result == ".." ? "content" : result
    }

    private nonisolated static func safeAdditionalContentFilename(_ value: String) -> String {
        let basename = URL(fileURLWithPath: value.replacingOccurrences(of: "\\", with: "/")).lastPathComponent
        let cleaned = basename.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "." || result == ".." ? "gog-content-file" : result
    }

    private nonisolated static func isCompleteAdditionalContentFile(
        _ url: URL,
        expectedSize: Int64?
    ) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0 else { return false }
        return expectedSize.map { $0 == Int64(fileSize) } ?? true
    }

    private nonisolated static func additionalContentFileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else { return 0 }
        return Int64(fileSize)
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
        var helperArguments = arguments
        if let command = arguments.first,
           ["download", "update", "repair"].contains(command),
           arguments.count > 1, Self.isSafeAppID(arguments[1]),
           !arguments.contains("--support") {
            // gogdl 1.3.0 leaves support_path empty by default. During repair,
            // its case-insensitive path lookup loops forever for missing relative
            // support files. All lifecycle commands must use the same absolute root.
            let supportURL = configURL.appending(path: "heroic_gogdl/gog-support/\(arguments[1])", directoryHint: .isDirectory)
                .standardizedFileURL
            try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
            helperArguments += ["--support", supportURL.path]
        }
        return try await Self.runProcess(
            executable: helperURL,
            arguments: ["--auth-config-path", authURL.path] + helperArguments,
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

    private static func gameExecutable(
        in tasks: [[String: Any]],
        primaryRelativePath: String,
        gameDirectory: URL
    ) -> URL? {
        let primaryPath = primaryRelativePath.replacingOccurrences(of: "\\", with: "/")
        let candidates = tasks.compactMap { task -> (URL, String, Bool)? in
            guard let path = task["path"] as? String,
                  !path.isEmpty,
                  path.replacingOccurrences(of: "\\", with: "/").caseInsensitiveCompare(primaryPath) != .orderedSame,
                  let executable = safeChild(path, of: gameDirectory),
                  FileManager.default.isExecutableFile(atPath: executable.path)
                    || FileManager.default.fileExists(atPath: executable.path) else {
                return nil
            }
            let category = (task["category"] as? String)?.lowercased() ?? ""
            let hidden = task["isHidden"] as? Bool ?? false
            return (executable, category, hidden)
        }

        return candidates.first(where: { $0.1 == "game" })?.0
            ?? candidates.first(where: { $0.2 })?.0
    }

    private static func witcher3DirectLaunchTask(
        primaryTask: [String: Any],
        tasks: [[String: Any]]
    ) -> [String: Any]? {
        guard (primaryTask["category"] as? String)?.caseInsensitiveCompare("launcher") == .orderedSame,
              let launcherPath = primaryTask["path"] as? String,
              URL(fileURLWithPath: launcherPath.replacingOccurrences(of: "\\", with: "/"))
                .lastPathComponent.caseInsensitiveCompare("REDprelauncher.exe") == .orderedSame else {
            return nil
        }

        return tasks.first { task in
            guard (task["category"] as? String)?.caseInsensitiveCompare("game") == .orderedSame,
                  let path = task["path"] as? String else { return false }
            return URL(fileURLWithPath: path.replacingOccurrences(of: "\\", with: "/"))
                .lastPathComponent.caseInsensitiveCompare("witcher3.exe") == .orderedSame
        }
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

    private static func playtimePage(from data: Data) throws -> (minutes: Int, nextPageToken: String?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GOGServiceError.playtimeResponseInvalid
        }
        let nextPageToken = stringValue(root["next_page_token"]).flatMap { $0.isEmpty ? nil : $0 }
        let sessions = root["items"] as? [[String: Any]] ?? root["sessions"] as? [[String: Any]]
        if let sessions {
            let sessionTimes = sessions.compactMap { session -> Int? in
                intValue(session["time"]) ?? stringValue(session["time"]).flatMap(Int.init)
            }
            guard sessions.isEmpty || !sessionTimes.isEmpty else { throw GOGServiceError.playtimeResponseInvalid }
            return (sessionTimes.reduce(0) { $0 + max(0, $1) }, nextPageToken)
        }
        if let totalMinutes = intValue(root["total_time_minutes"]) {
            return (max(0, totalMinutes), nextPageToken)
        }
        if let totalSeconds = intValue(root["total_time_seconds"]) {
            return (max(0, totalSeconds / 60), nextPageToken)
        }
        throw GOGServiceError.playtimeResponseInvalid
    }

    private static func isSafeAppID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }

    private func preferredLanguage(appID: String) -> String? {
        let url = configURL.appending(path: "language-preferences/\(appID).txt")
        guard let value = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func savePreferredLanguage(_ languageCode: String, appID: String) throws {
        let directory = configURL.appending(path: "language-preferences", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(languageCode.utf8).write(
            to: directory.appending(path: "\(appID).txt"),
            options: .atomic
        )
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
                } else if String(data: diagnosticOutput, encoding: .utf8)?.localizedCaseInsensitiveContains("No manifest stored locally") == true {
                    continuation.resume(throwing: GOGServiceError.localManifestUnavailable)
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
    static func deduplicate(_ games: [StoreLibraryGame]) -> [StoreLibraryGame] {
        // Only identical GOG product IDs are duplicates. Promotional releases
        // (Prime, Luna, giveaways) are separate entitlements and must remain
        // visible even when their titles look similar. Cross-store grouping is
        // represented separately by `entitlementGroupID` and never inferred by
        // this normalizer.
        let grouped = Dictionary(grouping: games, by: \.externalID)
        return grouped.values.compactMap { candidates in
            let identity = candidates.first(where: { $0.isInstalled })
                ?? candidates.max { metadataScore($0) < metadataScore($1) }
                ?? candidates.first
            guard var result = identity else { return nil }
            for candidate in candidates where metadataScore(candidate) > metadataScore(result) {
                result.preservePresentationMetadata(from: candidate)
            }
            return result
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
