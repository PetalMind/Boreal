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

    /// Removes common archive wrappers such as
    /// `Mods/Archive Name/mods/modActual/content/file` and
    /// `Mods/Archive Name/dlc/dlcActual/content/file`, which the game does
    /// not discover because their payload folders are nested below the game roots.
    static func deploymentPath(for relativePath: String) -> String {
        let components = relativePath.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
        guard components.count > 3,
              ["Mods", "DLC"].contains(where: { components[0].caseInsensitiveCompare($0) == .orderedSame }),
              let nestedRootIndex = components.indices.dropFirst(2).first(where: { index in
                  let nestedRoot = components[index].lowercased()
                  let expectedFolderPrefix = nestedRoot == "mods" ? "mod" : "dlc"
                  return index < 6
                      && ["mods", "dlc"].contains(nestedRoot)
                      && components.indices.contains(index + 1)
                      && components[index + 1].lowercased().hasPrefix(expectedFolderPrefix)
                      && !components[2..<index].contains(where: {
                          ["content", "bin", "dlc", "userdata", "userconfig"].contains($0.lowercased())
                      })
              }) else {
            return relativePath
        }
        let targetRoot = components[nestedRootIndex].caseInsensitiveCompare("mods") == .orderedSame
            ? "Mods"
            : "DLC"
        return ([targetRoot] + Array(components.dropFirst(nestedRootIndex + 1))).joined(separator: "/")
    }

    static func isScriptMergerOutput(_ mod: InstalledMod) -> Bool {
        mod.files.contains { file in
            let components = deploymentPath(for: file.relativePath).split(separator: "/")
            return components.count >= 3
                && components[0].caseInsensitiveCompare("Mods") == .orderedSame
                && components[1].caseInsensitiveCompare("mod0000_MergedFiles") == .orderedSame
        }
    }
}

nonisolated enum Witcher3ConflictResolver {
    static func conflicts(in mods: [InstalledMod]) -> [ModConflict] {
        var owners: [String: [(mod: InstalledMod, file: ModFile)]] = [:]
        var locations: [String: ConflictLocation] = [:]
        for mod in mods where mod.enabled {
            for file in mod.files {
                let location = conflictLocation(for: file.relativePath)
                locations[location.key] = location
                owners[location.key, default: []].append((mod, file))
            }
        }

        return owners.compactMap { key, values in
            let uniqueValues = values.reduce(into: [(mod: InstalledMod, file: ModFile)]()) { result, value in
                guard !result.contains(where: { $0.mod.id == value.mod.id }) else { return }
                result.append(value)
            }
            guard uniqueValues.count > 1,
                  let location = locations[key],
                  !hasIdenticalPayloads(uniqueValues) else { return nil }

            let ordered = uniqueValues.sorted {
                if $0.mod.priority != $1.mod.priority { return $0.mod.priority < $1.mod.priority }
                return $0.mod.name.localizedStandardCompare($1.mod.name) == .orderedAscending
            }
            guard let first = ordered.first, let last = ordered.last else { return nil }
            let winner = location.strategy == .priorityLast ? last : first
            return ModConflict(
                relativePath: location.displayPath,
                modIDs: ordered.map { $0.mod.id },
                winnerModID: winner.mod.id,
                kind: location.strategy == .scriptMerger ? .mergeable : .directReplacement,
                resolutionStrategy: location.strategy
            )
        }.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private struct ConflictLocation {
        let key: String
        let displayPath: String
        let strategy: ModConflictResolutionStrategy
    }

    private static func conflictLocation(for path: String) -> ConflictLocation {
        let normalized = Witcher3Adapter.deploymentPath(for: path)
            .replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        if components.count > 2,
           components[0].caseInsensitiveCompare("Mods") == .orderedSame,
           components[1].lowercased().hasPrefix("mod") {
            let modResource = components.dropFirst(2).joined(separator: "/")
            let extensionName = URL(fileURLWithPath: modResource).pathExtension.lowercased()
            let strategy: ModConflictResolutionStrategy = ["ws", "bundle"].contains(extensionName)
                ? .scriptMerger
                : .priorityFirst
            return ConflictLocation(
                key: "mods/\(modResource.lowercased())",
                displayPath: "Mods/\(modResource)",
                strategy: strategy
            )
        }

        // DLC, user-data, and game-root files occupy different destinations
        // and use file-copy precedence rather than mods.settings priority.
        return ConflictLocation(
            key: normalized.lowercased(),
            displayPath: normalized,
            strategy: .priorityLast
        )
    }

    private static func hasIdenticalPayloads(_ values: [(mod: InstalledMod, file: ModFile)]) -> Bool {
        let hashes = values.map { $0.file.sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return hashes.allSatisfy { !$0.isEmpty } && Set(hashes).count == 1
    }
}
