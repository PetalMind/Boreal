import Foundation

actor WindowsProcessRunner: WindowsProcessRunning {
    private let processExecutor: any ProcessExecuting
    private var executorIDs: [UUID: UUID] = [:]

    init(processExecutor: any ProcessExecuting) { self.processExecutor = processExecutor }

    func run(executable: URL, arguments: [String], environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession {
        let sessionID = UUID()
        let stem = "launch-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(sessionID.uuidString.prefix(8))"
        let wineArguments: [String]
        if executable.pathExtension.lowercased() == "msi" {
            wineArguments = ["msiexec", "/i", executable.path] + arguments
        } else {
            wineArguments = [executable.path] + arguments
        }
        let request = ProcessLaunchRequest(
            executable: runtime.wineExecutable,
            arguments: wineArguments,
            environment: wineEnvironment(for: environment, runtime: runtime),
            currentDirectory: executable.deletingLastPathComponent(),
            stdoutLog: environment.logsURL.appending(path: "\(stem).stdout.log"),
            stderrLog: environment.logsURL.appending(path: "\(stem).stderr.log")
        )
        let receipt = try await processExecutor.launch(request)
        executorIDs[sessionID] = receipt.id
        return WindowsProcessSession(id: sessionID, environmentID: environment.id, launcherPID: receipt.pid, startedAt: receipt.startedAt, stdoutLog: receipt.stdoutLog, stderrLog: receipt.stderrLog)
    }

    func waitForExit(_ session: WindowsProcessSession) async throws -> ProcessExecutionResult {
        guard let id = executorIDs[session.id] else { throw ProcessRunnerError.sessionNotFound(session.id) }
        let result = try await processExecutor.waitForExit(id)
        executorIDs[session.id] = nil
        return result
    }

    func state(of session: WindowsProcessSession) async throws -> ProcessExecutionState {
        guard let id = executorIDs[session.id] else { throw ProcessRunnerError.sessionNotFound(session.id) }
        return try await processExecutor.state(of: id)
    }

    func stopApplication(_ session: WindowsProcessSession) async throws {
        guard let processID = executorIDs[session.id] else { throw ProcessRunnerError.sessionNotFound(session.id) }
        try await processExecutor.terminate(processID)
    }

    func terminateEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let request = controlRequest(executable: runtime.wineBootExecutable, arguments: ["--end-session"], name: "stop", environment: environment, runtime: runtime)
        if let receipt = try? await processExecutor.launch(request) { _ = try? await processExecutor.waitForExit(receipt.id) }
    }

    func forceQuit(_ session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        guard let processID = executorIDs[session.id] else { throw ProcessRunnerError.sessionNotFound(session.id) }
        let request = controlRequest(executable: runtime.wineServerExecutable, arguments: ["-k"], name: "force-quit", environment: environment, runtime: runtime)
        if let receipt = try? await processExecutor.launch(request) { _ = try? await processExecutor.waitForExit(receipt.id) }
        try await processExecutor.forceTerminate(processID)
    }

    private func controlRequest(executable: URL, arguments: [String], name: String, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) -> ProcessLaunchRequest {
        ProcessLaunchRequest(
            executable: executable,
            arguments: arguments,
            environment: wineEnvironment(for: environment, runtime: runtime),
            currentDirectory: environment.rootURL,
            stdoutLog: environment.logsURL.appending(path: "\(name).stdout.log"),
            stderrLog: environment.logsURL.appending(path: "\(name).stderr.log")
        )
    }

    private func wineEnvironment(for environment: ManagedBorealEnvironment, runtime: InstalledRuntime) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["WINEPREFIX"] = environment.prefixURL.path
        values["WINEARCH"] = environment.configuration.architecture
        values["WINEDEBUG"] = values["WINEDEBUG"] ?? "warn+all,err+all"
        values["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":" + (values["PATH"] ?? "/usr/bin:/bin")
        return values
    }
}
