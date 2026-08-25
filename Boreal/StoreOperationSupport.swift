import Darwin
import Foundation

nonisolated final class CancellableStoreProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var wasCancelled = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = wasCancelled
        lock.unlock()
        if shouldTerminate, process.isRunning { process.terminate() }
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let process = process
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
            Task.detached { [weak self, weak process] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, let process else { return }
                self.forceTerminateIfAttachedAndRunning(process)
            }
        }
    }

    private func forceTerminateIfAttachedAndRunning(_ candidate: Process) {
        lock.lock()
        let shouldKill = process === candidate && candidate.isRunning
        let pid = candidate.processIdentifier
        lock.unlock()
        if shouldKill { Darwin.kill(pid, SIGKILL) }
    }
}

nonisolated enum StoreProgressParser {
    static func update(from data: Data, provider: String) -> StoreGameOperationProgress? {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        let line = text
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, !line.isEmpty else { return nil }
        let fraction = percentage(in: line).map { Double($0) / 100 }
        let message = fraction.map { "Downloading from \(provider)… \(Int($0 * 100))%" }
            ?? concise(line, fallback: "Downloading from \(provider)…")
        return StoreGameOperationProgress(message: message, fractionCompleted: fraction)
    }

    private static func percentage(in text: String) -> Int? {
        let pattern = #"(?:^|\s|\[)(\d{1,3})(?:\.\d+)?%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range(at: 1), in: text),
              let value = Int(text[range]), value <= 100 else { return nil }
        return value
    }

    private static func concise(_ text: String, fallback: String) -> String {
        let sanitized = text.replacingOccurrences(of: "\r", with: " ")
        guard sanitized.count <= 120 else { return fallback }
        return sanitized
    }
}
