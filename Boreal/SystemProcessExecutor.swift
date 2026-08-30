import Darwin
import Foundation

actor SystemProcessExecutor: ProcessExecuting {
    private final class Record {
        let process: Process
        let startedAt: Date
        let stdoutLog: URL
        let stderrLog: URL
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        var result: ProcessExecutionResult?
        var waiters: [CheckedContinuation<ProcessExecutionResult, Never>] = []

        init(process: Process, startedAt: Date, stdoutLog: URL, stderrLog: URL, stdoutHandle: FileHandle, stderrHandle: FileHandle) {
            self.process = process
            self.startedAt = startedAt
            self.stdoutLog = stdoutLog
            self.stderrLog = stderrLog
            self.stdoutHandle = stdoutHandle
            self.stderrHandle = stderrHandle
        }
    }

    private var records: [UUID: Record] = [:]

    func launch(_ request: ProcessLaunchRequest) async throws -> ProcessLaunchReceipt {
        guard FileManager.default.isExecutableFile(atPath: request.executable.path) else {
            throw ProcessRunnerError.executableMissing(request.executable)
        }
        try prepareLog(request.stdoutLog)
        try prepareLog(request.stderrLog)
        let stdout = try FileHandle(forWritingTo: request.stdoutLog)
        let stderr = try FileHandle(forWritingTo: request.stderrLog)
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = request.currentDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        if let standardInput = request.standardInput {
            let input = Pipe()
            process.standardInput = input
            input.fileHandleForWriting.write(standardInput)
            try? input.fileHandleForWriting.close()
        }
        let id = UUID()
        let startedAt = Date()
        let record = Record(process: process, startedAt: startedAt, stdoutLog: request.stdoutLog, stderrLog: request.stderrLog, stdoutHandle: stdout, stderrHandle: stderr)
        records[id] = record
        process.terminationHandler = { [weak self] _ in
            Task { await self?.finish(id) }
        }
        do {
            try process.run()
            return ProcessLaunchReceipt(id: id, pid: process.processIdentifier, startedAt: startedAt, stdoutLog: request.stdoutLog, stderrLog: request.stderrLog)
        } catch {
            records[id] = nil
            try? stdout.close()
            try? stderr.close()
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }
    }

    func waitForExit(_ id: UUID) async throws -> ProcessExecutionResult {
        guard let record = records[id] else { throw ProcessRunnerError.sessionNotFound(id) }
        if let result = record.result { return result }
        return await withCheckedContinuation { continuation in record.waiters.append(continuation) }
    }

    func state(of id: UUID) async throws -> ProcessExecutionState {
        guard let record = records[id] else { throw ProcessRunnerError.sessionNotFound(id) }
        if let result = record.result { return .terminated(result) }
        return .running(pid: record.process.processIdentifier)
    }

    func terminate(_ id: UUID) async throws {
        guard let record = records[id] else { throw ProcessRunnerError.sessionNotFound(id) }
        if record.process.isRunning { record.process.terminate() }
    }

    func forceTerminate(_ id: UUID) async throws {
        guard let record = records[id] else { throw ProcessRunnerError.sessionNotFound(id) }
        if record.process.isRunning { Darwin.kill(record.process.processIdentifier, SIGKILL) }
    }

    private func finish(_ id: UUID) {
        guard let record = records[id], record.result == nil else { return }
        try? record.stdoutHandle.close()
        try? record.stderrHandle.close()
        let result = ProcessExecutionResult(
            pid: record.process.processIdentifier,
            startedAt: record.startedAt,
            terminatedAt: Date(),
            exitCode: record.process.terminationStatus,
            terminationReason: Int(record.process.terminationReason.rawValue),
            stdoutLog: record.stdoutLog,
            stderrLog: record.stderrLog
        )
        record.result = result
        let waiters = record.waiters
        record.waiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
    }

    private func prepareLog(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
}
