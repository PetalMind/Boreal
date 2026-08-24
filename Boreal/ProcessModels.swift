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

nonisolated struct ProcessLaunchRequest: Sendable {
    let executable: URL
    var arguments: [String] = []
    var environment: [String: String] = [:]
    var currentDirectory: URL?
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
    func waitForExit(_ session: WindowsProcessSession) async throws -> ProcessExecutionResult
    func state(of session: WindowsProcessSession) async throws -> ProcessExecutionState
    func stopApplication(_ session: WindowsProcessSession) async throws
    func terminateEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func forceQuit(_ session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
}
