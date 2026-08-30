import Foundation

nonisolated struct SteamCMDCredentials: Sendable {
    let username: String
    let password: String
    let guardCode: String
}

nonisolated struct SteamWindowsDownload: Sendable {
    let destination: URL
    let log: URL
}

nonisolated protocol SteamWindowsProviding: Sendable {
    func downloadWindowsGame(appID: String, destination: URL, credentials: SteamCMDCredentials, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsDownload
}

enum SteamWindowsError: LocalizedError, Sendable {
    case steamCMDNotFound
    case downloadFailed(Int32, URL)
    case authenticationFailed(URL)
    case credentialsRequired
    case gameExecutableMissing

    var errorDescription: String? {
        switch self {
        case .steamCMDNotFound: "SteamCMD was not found. Install it with Homebrew using: brew install steamcmd"
        case .downloadFailed(let code, let log): "SteamCMD could not download the Windows game (exit code \(code)). See \(log.path)."
        case .authenticationFailed(let log): "SteamCMD could not sign in. Open Steam Guard Mobile, approve the sign-in if prompted, then enter the current code and try again. See \(log.path)."
        case .credentialsRequired: "Enter your Steam username and password to download this game."
        case .gameExecutableMissing: "SteamCMD finished, but no Windows game executable was found in the destination folder."
        }
    }
}

actor SteamWindowsService: SteamWindowsProviding {
    private let fileManager: FileManager
    private let processExecutor: any ProcessExecuting
    private let applicationSupportURL: URL

    init(applicationSupportURL: URL, processExecutor: any ProcessExecuting, fileManager: FileManager = .default) {
        self.applicationSupportURL = applicationSupportURL
        self.processExecutor = processExecutor
        self.fileManager = fileManager
    }

    func downloadWindowsGame(appID: String, destination: URL, credentials: SteamCMDCredentials, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsDownload {
        guard !credentials.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !credentials.password.isEmpty else { throw SteamWindowsError.credentialsRequired }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        await progress(.preparingRuntime)
        guard let executable = steamCMDExecutable() else { throw SteamWindowsError.steamCMDNotFound }
        await progress(.startingInstaller)
        let log = applicationSupportURL.appending(path: "Logs/SteamCMD/\(appID)-\(UUID().uuidString).log")
        // SteamCMD's documented login syntax is `+login <username> <password> [<guard-code>]`.
        // Feeding these values to stdin is unreliable when SteamCMD is launched without a TTY:
        // it can consume the input before the login command asks for it. The values are held only
        // for this process invocation and are never persisted by Boreal.
        var loginArguments = ["+login", credentials.username, credentials.password]
        if !credentials.guardCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loginArguments.append(credentials.guardCode.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let request = ProcessLaunchRequest(
            executable: executable,
            arguments: [
                "+@sSteamCmdForcePlatformType", "windows",
            ] + loginArguments + [
                "+force_install_dir", destination.path, "+app_update", appID, "validate", "+quit"
            ], environment: [:], currentDirectory: destination, stdoutLog: log, stderrLog: log
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await withTaskCancellationHandler {
            try await processExecutor.waitForExit(receipt.id)
        } onCancel: {
            Task { try? await self.processExecutor.terminate(receipt.id) }
        }
        let logText = (try? String(contentsOf: log, encoding: .utf8))?.lowercased() ?? ""
        if logText.contains("need two-factor code")
            || logText.contains("account logon denied")
            || logText.contains("invalid password")
            || logText.contains("login failure") {
            throw SteamWindowsError.authenticationFailed(log)
        }
        guard result.exitCode == 0 else { throw SteamWindowsError.downloadFailed(result.exitCode, log) }
        await progress(.detectingApplication)
        guard !ExecutableDiscovery.snapshot(at: destination, fileManager: fileManager).entries.isEmpty else { throw SteamWindowsError.gameExecutableMissing }
        await progress(.committing)
        return SteamWindowsDownload(destination: destination, log: log)
    }

    private func steamCMDExecutable() -> URL? {
        ["/opt/homebrew/bin/steamcmd", "/usr/local/bin/steamcmd", "/opt/homebrew/bin/steamcmd.sh", "/usr/local/bin/steamcmd.sh"].map(URL.init(fileURLWithPath:)).first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
