import Foundation

// MARK: - The Witcher 3 adapter

/// The Witcher 3's Classic, Next-Gen, Complete and GOTY editions share the
/// same mod deployment contract: `Mods` and `DLC` live beside `bin`, and
/// optional enablement/load order is stored in Documents/The Witcher 3.
nonisolated enum Witcher3Adapter {
    static let adapter: ModGameAdapter = .witcher3
    static let steamAppID = "292030"
    static let gogProductID = "1640424747"
    static let nexusURL = URL(string: "https://www.nexusmods.com/witcher3")!
    static let knownExecutables = [
        "bin/x64/witcher3.exe",
        "bin/x64_dx12/witcher3.exe",
        "bin/witcher3.exe"
    ]

    static func supports(game: StoreLibraryGame) -> Bool {
        let normalized = game.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let knownIDs = [steamAppID, gogProductID, "the-witcher-3", "witcher-3", "witcher3"]
        return normalized.contains("witcher 3")
            || normalized.contains("witcher iii")
            || knownIDs.contains(game.externalID.lowercased())
    }

    static func gameRoot(
        installationRoot: URL?,
        executable: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let installationRoot {
            var current = installationRoot.standardizedFileURL
            if current.pathExtension.caseInsensitiveCompare("exe") == .orderedSame {
                current.deleteLastPathComponent()
            }
            for _ in 0..<7 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }
        if let executable {
            var current = executable.standardizedFileURL.deletingLastPathComponent()
            for _ in 0..<8 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            let root = candidate.standardizedFileURL
            let hasExpectedExecutable = knownExecutables.contains {
                fileManager.isReadableFile(atPath: append($0, to: root).path)
            }
            let hasGameLayout = ["bin", "content", "dlc"].allSatisfy {
                fileManager.fileExists(atPath: root.appending(path: $0, directoryHint: .isDirectory).path)
            }
            if hasExpectedExecutable || hasGameLayout { return root }
        }
        return nil
    }

    /// Returns the Windows Documents/The Witcher 3 directory for a Wine
    /// prefix. If the game has not created it yet, the standard user path is
    /// returned so Boreal can create it when the user deploys a profile.
    static func documentsRoot(
        inPrefix prefixURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let normalized = prefixURL.standardizedFileURL
        let driveC = normalized.lastPathComponent.caseInsensitiveCompare("drive_c") == .orderedSame
            ? normalized
            : normalized.appending(path: "drive_c", directoryHint: .isDirectory)
        let usersRoot = driveC.appending(path: "users", directoryHint: .isDirectory)
        let users = (try? fileManager.contentsOfDirectory(
            at: usersRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        } ?? []
        let ordered = users.sorted {
            let left = $0.lastPathComponent.caseInsensitiveCompare("steamuser") == .orderedSame ? 0 : 1
            let right = $1.lastPathComponent.caseInsensitiveCompare("steamuser") == .orderedSame ? 0 : 1
            if left != right { return left < right }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        for user in ordered {
            for documents in ["Documents", "My Documents"] {
                let candidate = user.appending(path: "\(documents)/The Witcher 3", directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        guard let user = ordered.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare("steamuser") == .orderedSame
        }) ?? ordered.first else { return nil }
        return user.appending(path: "Documents/The Witcher 3", directoryHint: .isDirectory)
    }

    static func documentsRoot(
        forGameRoot gameRoot: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var current = gameRoot.standardizedFileURL
        for _ in 0..<14 {
            if current.lastPathComponent.caseInsensitiveCompare("drive_c") == .orderedSame {
                return documentsRoot(inPrefix: current, fileManager: fileManager)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    static func contentDirectory(named name: String, in gameRoot: URL, fileManager: FileManager = .default) -> URL {
        let candidates = (try? fileManager.contentsOfDirectory(
            at: gameRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return candidates.first {
            $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
                && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        } ?? gameRoot.appending(path: name, directoryHint: .isDirectory)
    }

    static func append(_ relativePath: String, to root: URL) -> URL {
        relativePath.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }
    }
}

nonisolated enum Witcher3ConflictResolver {
    static func conflicts(in mods: [InstalledMod]) -> [ModConflict] {
        var owners: [String: [(mod: InstalledMod, file: ModFile)]] = [:]
        for mod in mods where mod.enabled {
            for file in mod.files {
                let key = resourcePath(for: file.relativePath)
                owners[key, default: []].append((mod, file))
            }
        }
        return owners.compactMap { path, values in
            let uniqueValues = values.reduce(into: [(mod: InstalledMod, file: ModFile)]()) { result, value in
                guard !result.contains(where: { $0.mod.id == value.mod.id }) else { return }
                result.append(value)
            }
            guard uniqueValues.count > 1,
                  let winner = uniqueValues.max(by: { $0.mod.priority < $1.mod.priority }) else { return nil }
            let extensionName = URL(fileURLWithPath: path).pathExtension.lowercased()
            return ModConflict(
                relativePath: path,
                modIDs: uniqueValues.sorted { $0.mod.priority < $1.mod.priority }.map { $0.mod.id },
                winnerModID: winner.mod.id,
                kind: extensionName == "ws" ? .mergeable : .directReplacement
            )
        }.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func resourcePath(for path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        guard components.count > 2 else { return normalized.lowercased() }
        if components[0].caseInsensitiveCompare("Mods") == .orderedSame,
           components[1].lowercased().hasPrefix("mod") {
            return components.dropFirst(2).joined(separator: "/").lowercased()
        }
        if components[0].caseInsensitiveCompare("DLC") == .orderedSame,
           components[1].lowercased().hasPrefix("dlc") {
            return components.dropFirst(2).joined(separator: "/").lowercased()
        }
        if components[0].caseInsensitiveCompare("UserData") == .orderedSame {
            return components.dropFirst().joined(separator: "/").lowercased()
        }
        return normalized.lowercased()
    }
}
