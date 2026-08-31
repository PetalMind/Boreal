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
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let updates = lines.compactMap { parse(line: $0, provider: provider) }
        return updates.last(where: {
            $0.fractionCompleted != nil
                || $0.transferredBytes != nil
                || $0.transferRate != nil
                || $0.estimatedTimeRemaining != nil
                || $0.phase != .preparing
        }) ?? updates.last
    }

    private static func parse(line rawLine: String, provider: String) -> StoreGameOperationProgress? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let fraction = percentage(in: line, provider: provider).map { $0 / 100 }
        let phase = phase(in: line)
        let amount = byteProgress(in: line)
        let rates = byteRates(in: line, phase: phase)
        return StoreGameOperationProgress(
            message: phase.detail,
            fractionCompleted: fraction,
            phase: phase,
            transferRate: transferRate(in: line, phase: phase),
            transferred: amount?.completed,
            total: amount?.total,
            transferredBytes: amount?.completedBytes,
            totalBytes: amount?.totalBytes,
            estimatedTimeRemaining: estimatedTime(in: line),
            rawDetail: concise(line),
            networkBytesPerSecond: rates.network,
            diskBytesPerSecond: rates.disk
        )
    }

    private static func percentage(in text: String, provider: String) -> Double? {
        let pattern = #"(?:^|\s|\[)(\d{1,3}(?:\.\d+)?)%"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
           let range = Range(match.range(at: 1), in: text),
           let value = Double(text[range]), value <= 100 {
            return value
        }
        guard provider.localizedCaseInsensitiveContains("steam") else { return nil }
        let steamPattern = #"progress:\s*(\d{1,3}(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: steamPattern, options: [.caseInsensitive]),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]), value <= 100 else { return nil }
        return value
    }

    private static func phase(in text: String) -> StoreGameOperationPhase {
        let value = text.lowercased()
        if value.contains("verif") || value.contains("checksum") { return .verifying }
        if value.contains("disk") || value.contains("write") || value.contains("install") || value.contains("unpack") {
            return .installing
        }
        if value.contains("download") || value.contains("receive") || value.contains("network") || value.contains("mib/s") {
            return .downloading
        }
        return .preparing
    }

    private static func transferRate(in text: String, phase: StoreGameOperationPhase) -> String? {
        let pattern = #"(\d+(?:\.\d+)?)\s*((?:K|M|G)i?B/s)(?:\s*\((write|read|receive|download)\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        let preferred = matches.first { match in
            guard match.numberOfRanges > 3,
                  let labelRange = Range(match.range(at: 3), in: text) else { return false }
            let label = text[labelRange].lowercased()
            return phase == .installing ? label == "write" : label == "receive" || label == "download"
        } ?? matches.first
        guard let preferred,
              let valueRange = Range(preferred.range(at: 1), in: text),
              let unitRange = Range(preferred.range(at: 2), in: text),
              let value = Double(text[valueRange]), value > 0 else { return nil }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(text[unitRange])"
    }

    private static func byteRates(in text: String, phase: StoreGameOperationPhase) -> (network: Double?, disk: Double?) {
        let pattern = #"(\d+(?:\.\d+)?)\s*((?:K|M|G)i?B/s)(?:\s*\((write|read|receive|download)\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (nil, nil)
        }
        var network: Double?
        var disk: Double?
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]) else { continue }
            let bytes = bytesPerSecond(value: value, unit: String(text[unitRange]))
            let label = match.numberOfRanges > 3
                ? Range(match.range(at: 3), in: text).map { text[$0].lowercased() }
                : nil
            if label == "write" || label == "read" {
                disk = bytes
            } else if label == "receive" || label == "download" {
                network = bytes
            } else if phase == .installing {
                disk = bytes
            } else {
                network = bytes
            }
        }
        return (network, disk)
    }

    private static func bytesPerSecond(value: Double, unit: String) -> Double {
        switch unit.lowercased() {
        case "kb/s": return value * 1_000
        case "kib/s": return value * 1_024
        case "mb/s": return value * 1_000_000
        case "mib/s": return value * 1_048_576
        case "gb/s": return value * 1_000_000_000
        case "gib/s": return value * 1_073_741_824
        default: return value
        }
    }

    private static func byteProgress(in text: String) -> (completed: String, total: String, completedBytes: Int64, totalBytes: Int64)? {
        let pattern = #"(\d+(?:\.\d+)?)\s*((?:K|M|G|T)i?B)\s*(?:/|of)\s*(\d+(?:\.\d+)?)\s*((?:K|M|G|T)i?B)?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let completedValue = Range(match.range(at: 1), in: text),
           let completedUnit = Range(match.range(at: 2), in: text),
           let totalValue = Range(match.range(at: 3), in: text) {
            let totalUnit = Range(match.range(at: 4), in: text) ?? completedUnit
            return makeByteProgress(
                completedValue: completedValue,
                completedUnit: completedUnit,
                totalValue: totalValue,
                totalUnit: totalUnit,
                text: text
            )
        }

        // Steam-compatible providers sometimes print the unit only after the total value:
        // "1234 / 5678 KB".
        let steamPattern = #"(\d+(?:\.\d+)?)\s*(?:/|of)\s*(\d+(?:\.\d+)?)\s*((?:K|M|G|T)i?B)"#
        guard let regex = try? NSRegularExpression(pattern: steamPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let completedValue = Range(match.range(at: 1), in: text),
              let totalValue = Range(match.range(at: 2), in: text),
              let unit = Range(match.range(at: 3), in: text) else { return nil }
        return makeByteProgress(
            completedValue: completedValue,
            completedUnit: unit,
            totalValue: totalValue,
            totalUnit: unit,
            text: text
        )
    }

    private static func makeByteProgress(
        completedValue: Range<String.Index>,
        completedUnit: Range<String.Index>,
        totalValue: Range<String.Index>,
        totalUnit: Range<String.Index>,
        text: String
    ) -> (completed: String, total: String, completedBytes: Int64, totalBytes: Int64) {
        let completedNumber = Double(text[completedValue]) ?? 0
        let totalNumber = Double(text[totalValue]) ?? 0
        let completedUnitText = String(text[completedUnit])
        let totalUnitText = String(text[totalUnit])
        let completedBytes = byteCount(value: completedNumber, unit: completedUnitText)
        let totalBytes = byteCount(value: totalNumber, unit: totalUnitText)
        return (
            "\(text[completedValue]) \(completedUnitText)",
            "\(text[totalValue]) \(totalUnitText)",
            completedBytes,
            totalBytes
        )
    }

    private static func byteCount(value: Double, unit: String) -> Int64 {
        let multiplier: Double
        switch unit.lowercased() {
        case "kb": multiplier = 1_000
        case "kib": multiplier = 1_024
        case "mb": multiplier = 1_000_000
        case "mib": multiplier = 1_048_576
        case "gb": multiplier = 1_000_000_000
        case "gib": multiplier = 1_073_741_824
        case "tb": multiplier = 1_000_000_000_000
        case "tib": multiplier = 1_099_511_627_776
        default: multiplier = 1
        }
        return Int64(max(0, (value * multiplier).rounded()))
    }

    private static func estimatedTime(in text: String) -> String? {
        let patterns = [
            #"(?:eta|remaining|left)[:\s]+(?:about\s+)?([^,|\]]+)"#,
            #"~\s*([^,|\]]+)\s+(?:remaining|left)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let valueRange = Range(match.range(at: 1), in: text) else { continue }
            let value = text[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func concise(_ text: String) -> String? {
        let sanitized = text.replacingOccurrences(of: "\r", with: " ")
        guard !sanitized.isEmpty else { return nil }
        return String(sanitized.prefix(500))
    }
}

/// Buffers helper output because readability callbacks are allowed to split a
/// progress line at any byte boundary. Without this, a percentage or byte pair
/// can disappear simply because `%` arrived in the next callback.
nonisolated final class StoreProgressAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private let provider: String

    init(provider: String) {
        self.provider = provider
    }

    func update(from data: Data) -> StoreGameOperationProgress? {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        lock.lock()
        let combined = pending + text
        let hasTrailingNewline = combined.last?.isNewline == true
        let lines = combined.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).map(String.init)
        let completeLines = hasTrailingNewline ? lines : Array(lines.dropLast())
        pending = hasTrailingNewline ? "" : (lines.last ?? combined)
        lock.unlock()

        return completeLines.reversed()
            .compactMap { StoreProgressParser.update(from: Data($0.utf8), provider: provider) }
            .first
    }
}
