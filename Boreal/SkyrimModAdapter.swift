import Foundation

nonisolated enum SkyrimModAdapter {
    static let supportedDataDirectories: Set<String> = [
        "meshes", "textures", "scripts", "interface", "sound", "music", "strings", "skse",
    ]

    static func supports(game: StoreLibraryGame) -> Bool {
        supports(gameName: game.name) || game.externalID == "489830"
    }

    static func supports(gameName: String) -> Bool {
        let name = gameName.lowercased()
        return name.contains("skyrim") && (name.contains("special edition") || name.contains("anniversary edition"))
    }

    static func gameRoot(
        installationRoot: URL?,
        executable: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let installationRoot {
            let root = installationRoot.standardizedFileURL
            candidates.append(root.lastPathComponent.lowercased() == "data" ? root.deletingLastPathComponent() : root)
        }
        if let executable {
            var current = executable.standardizedFileURL.deletingLastPathComponent()
            for _ in 0..<5 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }
        for candidate in candidates {
            let root = candidate.standardizedFileURL
            let data = root.appending(path: "Data", directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: data.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return root
            }
        }
        return nil
    }

    static func dataRoot(for gameRoot: URL, fileManager: FileManager = .default) -> URL? {
        let root = gameRoot.standardizedFileURL
        if root.lastPathComponent.lowercased() == "data" { return root }
        let data = root.appending(path: "Data", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: data.path, isDirectory: &isDirectory) && isDirectory.boolValue ? data : nil
    }

    /// Skyrim keeps this file in `%LOCALAPPDATA%/Skyrim Special Edition`.
    /// An existing plugin list is preferred; a fresh or ambiguous prefix uses
    /// Wine's conventional `steamuser` account.
    static func pluginsFile(
        in prefix: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let users = prefix.appending(path: "drive_c/users", directoryHint: .isDirectory)
        var userNames: [String] = []
        if let children = try? fileManager.contentsOfDirectory(at: users, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            userNames = children.compactMap { url in
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                return url.lastPathComponent
            }.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
        }
        if !userNames.contains(where: { $0.caseInsensitiveCompare("steamuser") == .orderedSame }) {
            userNames.append("steamuser")
        }
        let candidates = userNames.map { user in
            (
                user: user,
                url:
                    users
                    .appending(path: user, directoryHint: .isDirectory)
                    .appending(path: "AppData/Local/Skyrim Special Edition", directoryHint: .isDirectory)
                    .appending(path: "plugins.txt")
            )
        }
        if let existing = candidates.first(where: {
            $0.user.caseInsensitiveCompare("steamuser") == .orderedSame
                && fileManager.fileExists(atPath: $0.url.path)
        }) ?? candidates.first(where: { fileManager.fileExists(atPath: $0.url.path) }) {
            return existing.url
        }

        // Prefer an already-created game settings folder when no plugin list
        // exists yet. A stale or empty folder for another Wine account must
        // not shadow an existing plugins.txt in a later account.
        let existingSettingsFolders = candidates.filter {
            fileManager.fileExists(atPath: $0.url.deletingLastPathComponent().path)
        }
        if existingSettingsFolders.count == 1, let folder = existingSettingsFolders.first {
            return folder.url
        }
        if let steamUser = candidates.first(where: { $0.user.caseInsensitiveCompare("steamuser") == .orderedSame }) {
            return steamUser.url
        }
        return candidates.first?.url
    }

    static func pluginType(for filename: String) -> BethesdaPluginType? {
        BethesdaPluginType(fileExtension: URL(fileURLWithPath: filename).pathExtension)
    }

    static func isBasePlugin(_ filename: String) -> Bool {
        let baseNames: Set<String> = [
            "skyrim.esm", "update.esm", "dawnguard.esm", "hearthfires.esm", "dragonborn.esm",
        ]
        let lowercased = filename.lowercased()
        return baseNames.contains(lowercased) || lowercased.hasPrefix("cc")
    }

    static func gameProvidedPluginNames(in gameRoot: URL?) -> Set<String> {
        var names: Set<String> = [
            "skyrim.esm", "update.esm", "dawnguard.esm", "hearthfires.esm", "dragonborn.esm",
        ]
        guard let gameRoot else { return names }
        let ccc = gameRoot.appending(path: "Skyrim.ccc")
        guard let contents = try? String(contentsOf: ccc, encoding: .utf8) else { return names }
        for line in contents.split(whereSeparator: \.isNewline) {
            let filename = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !filename.isEmpty { names.insert(filename) }
        }
        return names
    }

    static func pluginsFileData(
        plugins: [BethesdaPlugin],
        mods: [InstalledMod],
        gameRoot: URL?
    ) -> Data {
        let gameProvidedNames = gameProvidedPluginNames(in: gameRoot)
        let enabledModIDs = Set(mods.filter(\.enabled).map(\.id))
        var seenFilenames: Set<String> = []
        let effective = plugins.sorted { $0.loadOrder < $1.loadOrder }.compactMap { plugin -> String? in
            let key = plugin.filename.lowercased()
            guard !gameProvidedNames.contains(key), !isBasePlugin(plugin.filename) else { return nil }
            if let modID = plugin.modID, !enabledModIDs.contains(modID) { return nil }
            guard seenFilenames.insert(key).inserted else { return nil }
            return "\(plugin.enabled ? "*" : "")\(plugin.filename)"
        }
        let text = effective.joined(separator: "\n")
        let header = "# This file is used by Skyrim to keep track of your downloaded content.\n# Please do not modify this file.\n"
        return Data((header + text + (text.isEmpty ? "" : "\n")).utf8)
    }

    static func isBaseArchive(_ filename: String) -> Bool {
        let lowercased = filename.lowercased()
        return lowercased.hasPrefix("skyrim")
            || lowercased.hasPrefix("update")
            || lowercased.hasPrefix("dawnguard")
            || lowercased.hasPrefix("hearthfires")
            || lowercased.hasPrefix("dragonborn")
            || lowercased.hasPrefix("cc")
    }

    /// Reads the TES4 record header used by Skyrim plugins. The extension is
    /// only a fallback: the master and light flags in the header are the
    /// authoritative classification, and MAST subrecords are the dependency
    /// list used by the deployment preflight.
    static func inspectPlugin(at url: URL) -> BethesdaPluginHeader? {
        guard let data = try? Data(contentsOf: url), data.count >= 24,
            String(data: data.prefix(4), encoding: .ascii) == "TES4",
            let recordSize = readUInt32(data, offset: 4),
            Int(recordSize) <= data.count - 24,
            let flags = readUInt32(data, offset: 8)
        else { return nil }

        let recordEnd = 24 + Int(recordSize)
        var cursor = 24
        var masters: [String] = []
        while cursor + 6 <= recordEnd {
            let signature = String(decoding: data[cursor..<(cursor + 4)], as: UTF8.self)
            guard let size = readUInt16(data, offset: cursor + 4) else { break }
            cursor += 6
            let end = cursor + Int(size)
            guard end <= recordEnd else { break }
            if signature == "MAST",
                let master = String(data: data[cursor..<end], encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n")),
                !master.isEmpty,
                !masters.contains(where: { $0.caseInsensitiveCompare(master) == .orderedSame })
            {
                masters.append(master)
            }
            cursor = end
        }

        let classification: BethesdaPluginClassification
        if flags & 0x0000_0200 != 0 {
            classification = .light
        } else if flags & 0x0000_0001 != 0 {
            classification = .master
        } else {
            classification = .plugin
        }
        return BethesdaPluginHeader(flags: flags, classification: classification, masters: masters)
    }

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

// MARK: - Mod manager helpers
