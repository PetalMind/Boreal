import Foundation

actor WindowsProcessRunner: WindowsProcessRunning {
    private let processExecutor: any ProcessExecuting
    private let probeObservationWindow: Duration
    private var executorIDs: [UUID: UUID] = [:]

    init(processExecutor: any ProcessExecuting, probeObservationWindow: Duration = .milliseconds(250)) {
        self.processExecutor = processExecutor
        self.probeObservationWindow = probeObservationWindow
    }

    func run(executable: URL, arguments: [String], environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession {
        let plan = WindowsLaunchPlan(
            executable: executable,
            arguments: arguments,
            environment: [:],
            workingDirectory: executable.deletingLastPathComponent()
        )
        return try await run(plan: plan, environment: environment, runtime: runtime)
    }

    func run(plan: WindowsLaunchPlan, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession {
        let sessionID = UUID()
        let stem = "launch-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(sessionID.uuidString.prefix(8))"
        let wineArguments: [String]
        if plan.executable.pathExtension.lowercased() == "msi" {
            wineArguments = ["msiexec", "/i", plan.executable.path] + plan.arguments
        } else {
            wineArguments = [plan.executable.path] + plan.arguments
        }
        var processEnvironment = wineEnvironment(for: environment, runtime: runtime)
        processEnvironment.merge(plan.environment) { _, providerValue in providerValue }
        // The managed environment always owns these values. Provider metadata
        // cannot redirect a launch into another prefix or runtime search path.
        processEnvironment["WINEPREFIX"] = environment.prefixURL.path
        processEnvironment["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        let request = ProcessLaunchRequest(
            executable: runtime.wineExecutable,
            arguments: wineArguments,
            environment: processEnvironment,
            currentDirectory: plan.workingDirectory,
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

    func environmentSessionState(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> EnvironmentSessionState {
        let request = controlRequest(
            executable: runtime.wineServerExecutable,
            arguments: ["-w"],
            name: "session-probe",
            environment: environment,
            runtime: runtime
        )
        guard let receipt = try? await processExecutor.launch(request) else { return .unknown }

        do {
            try await Task.sleep(for: probeObservationWindow)
            switch try await processExecutor.state(of: receipt.id) {
            case .terminated(let result):
                return result.exitCode == 0 ? .inactive : .unknown
            case .running:
                // This terminates only the local `wineserver -w` observer. It does
                // not send a control command to the environment's wineserver.
                await stopProbeObserver(receipt.id)
                return .active
            }
        } catch is CancellationError {
            await stopProbeObserver(receipt.id)
            return .unknown
        } catch {
            await stopProbeObserver(receipt.id)
            return .unknown
        }
    }

    func waitForEnvironmentSessionEnd(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let request = controlRequest(
            executable: runtime.wineServerExecutable,
            arguments: ["-w"],
            name: "session-wait",
            environment: environment,
            runtime: runtime
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 else {
            throw ProcessRunnerError.launchFailed("wineserver -w exited with code \(result.exitCode).")
        }
    }

    func terminateEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let request = controlRequest(executable: runtime.wineBootExecutable, arguments: ["--end-session"], name: "stop", environment: environment, runtime: runtime)
        if let receipt = try? await processExecutor.launch(request) { _ = try? await processExecutor.waitForExit(receipt.id) }
    }

    func forceQuitEnvironment(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let request = controlRequest(executable: runtime.wineServerExecutable, arguments: ["-k"], name: "force-quit", environment: environment, runtime: runtime)
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 else {
            throw ProcessRunnerError.launchFailed("wineserver -k exited with code \(result.exitCode).")
        }
    }

    func forceQuit(_ session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        try await forceQuitEnvironment(environment: environment, runtime: runtime)
        if let processID = executorIDs[session.id] {
            try await processExecutor.forceTerminate(processID)
        }
    }

    private func stopProbeObserver(_ id: UUID) async {
        try? await processExecutor.terminate(id)
        for _ in 0..<20 {
            if case .terminated = try? await processExecutor.state(of: id) { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        try? await processExecutor.forceTerminate(id)
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
        let debugChannels = values["WINEDEBUG"] ?? "warn+all,err+all"
        values["WINEDEBUG"] = debugChannels.contains("+fps") ? debugChannels : debugChannels + ",+fps"
        values["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":" + (values["PATH"] ?? "/usr/bin:/bin")
        return values
    }
}
