import Foundation

nonisolated struct SteamWindowsClientCommit: Sendable {
    let installation: InstallationCommit
    let steamExecutable: URL
}

nonisolated protocol SteamWindowsProviding: Sendable {
    func prepareClient(progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsClientCommit
}

enum SteamWindowsError: LocalizedError, Sendable {
    case downloadFailed
    case invalidInstaller
    case clientExecutableMissing

    var errorDescription: String? {
        switch self {
        case .downloadFailed: "Boreal couldn’t download Valve’s official Steam for Windows installer."
        case .invalidInstaller: "Valve’s download did not contain a valid Windows installer."
        case .clientExecutableMissing: "Steam setup finished, but steam.exe was not found in the isolated environment."
        }
    }
}

actor SteamWindowsService: SteamWindowsProviding {
    private let fileManager: FileManager
    private let session: URLSession
    private let installer: any Installing
    private let installerURL: URL
    private let setupURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!

    init(
        applicationSupportURL: URL,
        installer: any Installing,
        fileManager: FileManager = .default,
        session: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.session = session
        self.installer = installer
        self.installerURL = applicationSupportURL.appending(path: "Installers/Steam/SteamSetup.exe")
    }

    func prepareClient(progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsClientCommit {
        try await downloadCurrentInstaller()
        let commit = try await installer.install(installerURL, name: "Steam") { stage in
            await progress(stage)
        }
        guard let steamExecutable = steamExecutable(in: commit.environment, discovered: commit.executable) else {
            throw SteamWindowsError.clientExecutableMissing
        }
        return SteamWindowsClientCommit(installation: commit, steamExecutable: steamExecutable)
    }

    private func downloadCurrentInstaller() async throws {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(from: setupURL) }
        catch { throw SteamWindowsError.downloadFailed }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url?.scheme == "https",
              http.url?.host == setupURL.host,
              data.count > 1_000_000,
              data.prefix(2) == Data([0x4D, 0x5A]) else {
            throw SteamWindowsError.invalidInstaller
        }
        try fileManager.createDirectory(at: installerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: installerURL, options: .atomic)
    }

    private func steamExecutable(in environment: ManagedBorealEnvironment, discovered: URL) -> URL? {
        let driveC = environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory).standardizedFileURL
        let candidates = [
            driveC.appending(path: "Program Files (x86)/Steam/steam.exe"),
            driveC.appending(path: "Program Files/Steam/steam.exe"),
            discovered
        ]
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(driveC.path + "/") else { continue }
            if fileManager.fileExists(atPath: resolved.path), resolved.lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame {
                return resolved
            }
        }
        let snapshot = ExecutableDiscovery.snapshot(at: driveC, fileManager: fileManager)
        return snapshot.entries.first(where: {
            ($0.relativePath as NSString).lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame
        })
            .map { driveC.appending(path: $0.relativePath).resolvingSymlinksInPath().standardizedFileURL }
    }
}
