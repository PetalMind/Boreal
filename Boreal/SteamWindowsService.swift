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
