import Foundation

nonisolated struct ProcessExecutionResult: Sendable, Equatable {
    let pid: Int32
    let startedAt: Date
    let terminatedAt: Date
    let exitCode: Int32
    let terminationReason: Int
    let stdoutLog: URL
    let stderrLog: URL
}

nonisolated struct WindowsProcessSession: Identifiable, Sendable, Hashable {
    let id: UUID
    let environmentID: UUID
    let launcherPID: Int32
    let startedAt: Date
    let stdoutLog: URL
    let stderrLog: URL
}

nonisolated struct WindowsLaunchPlan: Sendable, Hashable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL
    var overlayCompatibleFullscreen = false
    var overlayDisplayID: UInt32? = nil
}

nonisolated enum GameLaunchCompatibilityError: LocalizedError, Sendable {
    case steamAppIDFileUnavailable(URL, underlying: String)

    var errorDescription: String? {
        switch self {
        case .steamAppIDFileUnavailable(let url, let underlying):
            "Boreal couldn’t prepare Torchlight II for direct launch. The file \(url.path) could not be written: \(underlying)"
        }
    }
}

/// Applies compatibility files that are required by a game's own startup
/// code when the game is launched outside its original store client.
nonisolated enum GameLaunchCompatibility {
    private static let torchlightAppID = "200710"

    static func prepare(application: WindowsApplication) throws {
        guard application.usesStoreMetadataOnly,
              application.storeProvider == .steam,
              application.storeExternalID == torchlightAppID else { return }

        let executable = URL(fileURLWithPath: application.executablePath)
        guard executable.lastPathComponent.caseInsensitiveCompare("Torchlight2.exe") == .orderedSame else { return }

        let appIDFile = executable.deletingLastPathComponent().appending(path: "steam_appid.txt")
        let expected = Data("\(torchlightAppID)\n".utf8)
        if let existing = try? Data(contentsOf: appIDFile), existing == expected {
            return
        }

        do {
            try expected.write(to: appIDFile, options: .atomic)
        } catch {
            throw GameLaunchCompatibilityError.steamAppIDFileUnavailable(
                appIDFile,
                underlying: error.localizedDescription
            )
        }
    }
}

nonisolated struct ProcessLaunchRequest: Sendable {
    let executable: URL
    var arguments: [String] = []
    var environment: [String: String] = [:]
    var currentDirectory: URL?
    var standardInput: Data? = nil
    let stdoutLog: URL
    let stderrLog: URL
}

nonisolated struct ProcessLaunchReceipt: Sendable, Hashable {
    let id: UUID
    let pid: Int32
    let startedAt: Date
    let stdoutLog: URL
    let stderrLog: URL
}

nonisolated enum ProcessExecutionState: Sendable, Equatable {
    case running(pid: Int32)
    case terminated(ProcessExecutionResult)
}

nonisolated enum EnvironmentSessionState: Sendable, Equatable {
    case unknown
    case inactive
    case active
}

nonisolated enum ProcessRunnerError: LocalizedError, Sendable {
    case executableMissing(URL)
    case launchFailed(String)
    case sessionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let url): "Executable not found at \(url.path)."
        case .launchFailed(let reason): "The process couldn’t start: \(reason)"
        case .sessionNotFound: "The process session no longer exists."
        }
    }
}

nonisolated protocol ProcessExecuting: Sendable {
    func launch(_ request: ProcessLaunchRequest) async throws -> ProcessLaunchReceipt
    func waitForExit(_ id: UUID) async throws -> ProcessExecutionResult
    func state(of id: UUID) async throws -> ProcessExecutionState
    func terminate(_ id: UUID) async throws
    func forceTerminate(_ id: UUID) async throws
}

nonisolated protocol WindowsProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession
    func run(plan: WindowsLaunchPlan, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession
    func waitForExit(_ session: WindowsProcessSession) async throws -> ProcessExecutionResult
    func state(of session: WindowsProcessSession) async throws -> ProcessExecutionState
    func stopApplication(_ session: WindowsProcessSession) async throws
    func environmentSessionState(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> EnvironmentSessionState
    func waitForEnvironmentSessionEnd(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func terminateEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func forceQuitEnvironment(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func forceQuit(_ session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
}
