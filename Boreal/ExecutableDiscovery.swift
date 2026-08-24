import Foundation

/// A value-only description of an executable observed in a filesystem snapshot.
/// It deliberately contains no runtime or Wine-specific state.
nonisolated struct ExecutableSnapshotEntry: Hashable, Sendable {
    let relativePath: String
    let creationDate: Date?
    let modificationDate: Date?
    let fileSize: Int64?
    let isGUIExecutable: Bool?

    init(
        relativePath: String,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        fileSize: Int64? = nil,
        isGUIExecutable: Bool? = nil
    ) {
        self.relativePath = relativePath.replacingOccurrences(of: "\\", with: "/")
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.isGUIExecutable = isGUIExecutable
    }
}

nonisolated struct ExecutableFilesystemSnapshot: Hashable, Sendable {
    let rootURL: URL
    let capturedAt: Date
    let entries: [ExecutableSnapshotEntry]

    init(rootURL: URL, capturedAt: Date = Date(), entries: [ExecutableSnapshotEntry]) {
        self.rootURL = rootURL.standardizedFileURL
        self.capturedAt = capturedAt
        self.entries = entries
    }
}

nonisolated struct ExecutableCandidate: Hashable, Sendable {
    let url: URL
    let relativePath: String
    let score: Int
    let isGUIExecutable: Bool?
    let creationDate: Date?
}

/// Ranks executables added or replaced between two snapshots.
///
/// The discovery algorithm is pure: callers provide snapshots and get ranked
/// values back. `snapshot(at:)` is only a convenience adapter for filesystem
/// metadata and PE headers; it neither writes files nor launches processes.
nonisolated enum ExecutableDiscovery {
    static func rankedCandidates(
        before: ExecutableFilesystemSnapshot,
        after: ExecutableFilesystemSnapshot,
        applicationName: String
    ) -> [ExecutableCandidate] {
        var previous: [String: ExecutableSnapshotEntry] = [:]
        for entry in before.entries {
            previous[pathKey(entry.relativePath)] = entry
        }
        let eligible = after.entries.filter { entry in
            guard isEligibleExecutablePath(entry.relativePath) else { return false }
            guard let oldEntry = previous[pathKey(entry.relativePath)] else { return true }
            return fingerprint(of: oldEntry) != fingerprint(of: entry)
        }

        let creationDates = eligible.compactMap(\.creationDate)
        let oldestCreationDate = creationDates.min()
        let newestCreationDate = creationDates.max()

        return eligible.map { entry in
            let score = score(
                entry,
                applicationName: applicationName,
                before: before,
                oldestCreationDate: oldestCreationDate,
                newestCreationDate: newestCreationDate
            )
            return ExecutableCandidate(
                url: after.rootURL.appending(path: entry.relativePath),
                relativePath: entry.relativePath,
                score: score,
                isGUIExecutable: entry.isGUIExecutable,
                creationDate: entry.creationDate
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.creationDate != $1.creationDate {
                return ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    static func snapshot(at rootURL: URL, fileManager: FileManager = .default) -> ExecutableFilesystemSnapshot {
        let root = rootURL.standardizedFileURL
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return ExecutableFilesystemSnapshot(rootURL: root, entries: [])
        }

        var entries: [ExecutableSnapshotEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.caseInsensitiveCompare("exe") == .orderedSame,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            entries.append(ExecutableSnapshotEntry(
                relativePath: relativePath(of: url.standardizedFileURL, under: root),
                creationDate: values.creationDate,
                modificationDate: values.contentModificationDate,
                fileSize: values.fileSize.map(Int64.init),
                isGUIExecutable: peSubsystem(at: url).map { $0 == 2 }
            ))
        }
        return ExecutableFilesystemSnapshot(rootURL: root, entries: entries)
    }

    private static func score(
        _ entry: ExecutableSnapshotEntry,
        applicationName: String,
        before: ExecutableFilesystemSnapshot,
        oldestCreationDate: Date?,
        newestCreationDate: Date?
    ) -> Int {
        let lowerPath = "/" + entry.relativePath.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var result = 0

        if entry.isGUIExecutable == true { result += 45 }
        if entry.isGUIExecutable == false { result -= 15 }
        if lowerPath.hasPrefix("/program files/") || lowerPath.hasPrefix("/program files (x86)/") { result += 35 }

        let executableName = entry.relativePath.lastPathComponent.deletingPathExtension
        result += Int((nameSimilarity(executableName, applicationName) * 50).rounded())

        if let creationDate = entry.creationDate {
            if creationDate >= before.capturedAt { result += 6 }
            if let oldestCreationDate, let newestCreationDate, newestCreationDate > oldestCreationDate {
                let position = creationDate.timeIntervalSince(oldestCreationDate) / newestCreationDate.timeIntervalSince(oldestCreationDate)
                result += Int((position * 9).rounded())
            } else {
                result += 4
            }
        }
        return result
    }

    static func isEligibleExecutablePath(_ path: String) -> Bool {
        guard path.pathExtension.caseInsensitiveCompare("exe") == .orderedSame else { return false }
        let lowerPath = "/" + path.replacingOccurrences(of: "\\", with: "/").lowercased()
        if lowerPath.hasPrefix("/windows/") { return false }
        let components = normalizedWords(path)
        let joined = components.joined()
        let forbiddenWords: Set<String> = [
            "uninstall", "uninstaller", "unins", "updater", "update", "helper",
            "setup", "installer", "install", "crashreporter", "crashhandler"
        ]
        if !Set(components).isDisjoint(with: forbiddenWords) { return false }
        return !["uninstall", "unins", "updater", "update", "helper", "setup", "installer", "crashreporter", "crashhandler"]
            .contains { joined.contains($0) }
    }

    private static func nameSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = normalizedWords(lhs).joined()
        let right = normalizedWords(rhs).joined()
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }
        if left.contains(right) || right.contains(left) {
            return Double(min(left.count, right.count)) / Double(max(left.count, right.count))
        }
        let distance = levenshtein(Array(left), Array(right))
        return max(0, 1 - Double(distance) / Double(max(left.count, right.count)))
    }

    private static func normalizedWords(_ value: String) -> [String] {
        let words = value.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.map(String.init).filter { !["exe", "x64", "x86", "win32", "win64"].contains($0) }
    }

    private static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var previous = Array(0...rhs.count)
        for (leftIndex, left) in lhs.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, right) in rhs.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (left == right ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private static func fingerprint(of entry: ExecutableSnapshotEntry) -> String {
        "\(entry.fileSize.map(String.init) ?? "-")|\(entry.modificationDate?.timeIntervalSinceReferenceDate ?? -1)|\(entry.isGUIExecutable.map(String.init) ?? "-")"
    }

    private static func pathKey(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(url.path.dropFirst(rootPath.count))
    }

    /// Returns the PE subsystem value (2 = Windows GUI, 3 = console).
    private static func peSubsystem(at url: URL) -> UInt16? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let dosHeader = try? handle.read(upToCount: 64),
              dosHeader.count >= 64,
              dosHeader[0] == 0x4d, dosHeader[1] == 0x5a else { return nil }
        let peOffset = Int(readUInt32LE(dosHeader, at: 0x3c))
        guard peOffset >= 0, peOffset < 16 * 1_024 * 1_024 else { return nil }
        do {
            try handle.seek(toOffset: UInt64(peOffset))
            guard let header = try handle.read(upToCount: 96),
                  header.count >= 94,
                  header[0] == 0x50, header[1] == 0x45, header[2] == 0, header[3] == 0 else { return nil }
            // Signature (4) + COFF (20) + optional header subsystem offset (68).
            return readUInt16LE(header, at: 92)
        } catch {
            return nil
        }
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

private nonisolated extension String {
    var pathExtension: String { (self as NSString).pathExtension }
    var deletingPathExtension: String { (self as NSString).deletingPathExtension }
    var lastPathComponent: String { (self as NSString).lastPathComponent }
}
