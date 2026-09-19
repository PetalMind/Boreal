import Foundation

// MARK: - Dragon Age: Origins adapter

/// Dragon Age: Origins has two native mod layouts:
///
/// * loose override files under `Documents/BioWare/Dragon Age/packages/core/override`;
/// * DAZIP packages whose `Contents` directory is installed into the same
///   Dragon Age user directory and whose `Manifest.xml` entries are registered
///   in `Settings/AddIns.xml`.
///
/// Boreal keeps both layouts isolated in its staged profile and only writes to
/// the Wine user directory during deployment.
nonisolated enum DragonAgeOriginsAdapter {
    static let adapter: ModGameAdapter = .dragonAgeOrigins
    static let knownExecutables = [
        "DAOrigins.exe",
        "DAOriginsLauncher.exe",
        "DAOriginsConfig.exe"
    ]

    static func supports(game: StoreLibraryGame) -> Bool {
        let name = game.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let knownExternalIDs = ["47810", "dragon-age-origins", "dragon-age-origins-ultimate-edition"]
        return (name.contains("dragon age") && name.contains("origins"))
            || knownExternalIDs.contains(game.externalID.lowercased())
    }

    static func gameRoot(
        installationRoot: URL?,
        executable: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let executable {
            var current = executable.standardizedFileURL.deletingLastPathComponent()
            for _ in 0..<7 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }
        if let installationRoot {
            var current = installationRoot.standardizedFileURL
            if current.pathExtension.caseInsensitiveCompare("exe") == .orderedSame {
                current.deleteLastPathComponent()
            }
            candidates.append(current)
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            let root = candidate.standardizedFileURL
            let executableFound = knownExecutables.contains {
                fileManager.isReadableFile(atPath: root.appending(path: $0).path)
            }
            let binShipFound = fileManager.isReadableFile(
                atPath: root.appending(path: "bin_ship/DAOrigins.exe").path
            )
            let updaterFound = fileManager.isReadableFile(
                atPath: root.appending(path: "bin_ship/DAUpdater.exe").path
            )
            if executableFound || binShipFound || updaterFound {
                return root
            }
        }
        return nil
    }

    /// Resolves the Windows Documents equivalent from the managed Wine prefix.
    /// We do not use the host macOS Documents directory: DAO writes its user
    /// data beside the game inside `drive_c/users/<account>`.
    static func userDataRoot(
        for gameRoot: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var current = gameRoot.standardizedFileURL
        var driveC: URL?
        while current.path != "/" {
            if current.lastPathComponent.caseInsensitiveCompare("drive_c") == .orderedSame {
                driveC = current
                break
            }
            current.deleteLastPathComponent()
        }
        guard let driveC else { return nil }

        return userDataRoot(forPrefix: driveC, fileManager: fileManager)
    }

    /// Resolves DAO's Windows Documents directory from Boreal's managed Wine
    /// prefix. The game installation can live outside the prefix (for example
    /// on a separate GOG volume), so the game root is not a reliable source
    /// for this path.
    static func userDataRoot(
        forPrefix prefixURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let normalizedPrefix = prefixURL.standardizedFileURL
        let driveC = normalizedPrefix.lastPathComponent.caseInsensitiveCompare("drive_c") == .orderedSame
            ? normalizedPrefix
            : normalizedPrefix.appending(path: "drive_c", directoryHint: .isDirectory)

        let usersRoot = driveC.appending(path: "users", directoryHint: .isDirectory)
        let users = (try? fileManager.contentsOfDirectory(
            at: usersRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        } ?? []

        let orderedUsers = users.sorted {
            let left = $0.lastPathComponent.caseInsensitiveCompare("steamuser") == .orderedSame ? 0 : 1
            let right = $1.lastPathComponent.caseInsensitiveCompare("steamuser") == .orderedSame ? 0 : 1
            if left != right { return left < right }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        for user in orderedUsers {
            for documentsName in ["Documents", "My Documents"] {
                let candidate = user.appending(path: "\(documentsName)/BioWare/Dragon Age", directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        let fallbackUser = orderedUsers.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare("steamuser") == .orderedSame
        }) ?? orderedUsers.first
        guard let fallbackUser else { return nil }
        return fallbackUser.appending(path: "Documents/BioWare/Dragon Age", directoryHint: .isDirectory)
    }

    static func addInsFile(in gameRoot: URL, fileManager: FileManager = .default) -> URL? {
        userDataRoot(for: gameRoot, fileManager: fileManager)?.appending(path: "Settings/AddIns.xml")
    }

    static func addInsFile(inPrefix prefixURL: URL, fileManager: FileManager = .default) -> URL? {
        userDataRoot(forPrefix: prefixURL, fileManager: fileManager)?.appending(path: "Settings/AddIns.xml")
    }

    static func append(_ relativePath: String, to root: URL) -> URL {
        relativePath.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }
    }
}

nonisolated struct DragonAgeOriginsModManager: GameModManaging, Sendable {
    let rootURL: URL
    let adapter: ModGameAdapter = .dragonAgeOrigins

    init(applicationSupportURL: URL) {
        rootURL = applicationSupportURL.appending(path: "Mods/dragon-age-origins", directoryHint: .isDirectory)
    }

    func inspect(archive: URL, gameID: UUID) throws -> ModInstallPreview {
        let format = try archiveFormat(for: archive)
        let pendingRoot = gameURL(for: gameID).appending(path: "Archives/.pending", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        let pendingURL = pendingRoot.appending(path: "\(UUID().uuidString)-\(archive.lastPathComponent)")
        try FileManager.default.copyItem(at: archive, to: pendingURL)

        do {
            let extracted = try extract(pendingURL, format: format)
            defer { try? FileManager.default.removeItem(at: extracted) }
            let analysis = try analyze(extracted: extracted, archiveName: archive.lastPathComponent)
            let current = try load(gameID: gameID, gameRoot: nil, pluginsFile: nil, profileID: nil)
            return ModInstallPreview(
                gameID: gameID,
                archiveURL: pendingURL,
                archiveName: archive.lastPathComponent,
                format: format,
                detectedRoot: analysis.detectedRoot,
                fileCount: analysis.sourceFiles.count,
                pluginCount: 0,
                adapter: adapter,
                contentType: analysis.contentType,
                deployStrategy: analysis.deployStrategy,
                requirements: analysis.requirements,
                warnings: analysis.warnings,
                canInstallAutomatically: analysis.canInstallAutomatically,
                totalSize: analysis.sourceFiles.reduce(Int64(0)) {
                    $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                },
                existingModID: ModIdentity.existingModID(for: archive.lastPathComponent, in: current)
            )
        } catch {
            try? FileManager.default.removeItem(at: pendingURL)
            throw error
        }
    }

    func discardPreview(_ preview: ModInstallPreview) {
        let pendingRoot = gameURL(for: preview.gameID).appending(path: "Archives/.pending", directoryHint: .isDirectory)
        let url = preview.archiveURL.standardizedFileURL
        guard url.path.hasPrefix(pendingRoot.standardizedFileURL.path + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func load(
        gameID: UUID,
        gameRoot: URL?,
        pluginsFile: URL?,
        profileID: String? = nil
    ) throws -> ModGameState {
        let gameDirectory = gameURL(for: gameID)
        let resolvedProfileID = normalizedProfileID(profileID ?? activeProfileID(for: gameID))
        let profile = try read(ModProfile.self, at: profileURL(for: gameID, profileID: resolvedProfileID))
        let deployment = (try? read(ModDeploymentManifest.self, at: gameDirectory.appending(path: "deployment.json")))
            ?? .empty(gameID: gameID)
        var mods = profile?.mods ?? scanManifests(in: gameDirectory)
        mods.sort {
            $0.priority == $1.priority
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.priority < $1.priority
        }
        for index in mods.indices { mods[index].priority = index }
        let fingerprint = ModProfileFingerprint.make(mods: mods, plugins: [])
        var resolvedDeployment = deployment
        if deployment.profileFingerprint == nil && mods.isEmpty {
            resolvedDeployment.profileFingerprint = fingerprint
        }
        return ModGameState(
            gameID: gameID,
            profileID: resolvedProfileID,
            profileName: profile?.name ?? (resolvedProfileID == "default" ? "Default" : resolvedProfileID),
            mods: mods,
            plugins: [],
            deployment: resolvedDeployment,
            adapter: adapter,
            runtime: nil
        )
    }

    func install(
        preview: ModInstallPreview,
        gameRoot: URL?,
        pluginsFile: URL?,
        profileID: String = "default"
    ) throws -> ModGameState {
        guard preview.adapter == adapter else { throw ModManagerError.unsupportedGame(preview.adapter.displayName) }
        guard preview.canInstallAutomatically else {
            throw ModManagerError.deploymentFailed("This archive does not expose a native DAZIP or override layout and must be installed manually.")
        }

        let fileManager = FileManager.default
        let extracted = try extract(preview.archiveURL, format: try archiveFormat(for: preview.archiveURL))
        defer { try? fileManager.removeItem(at: extracted) }
        let analysis = try analyze(extracted: extracted, archiveName: preview.archiveName)
        guard analysis.canInstallAutomatically else {
            throw ModManagerError.deploymentFailed("This archive does not expose a native DAZIP or override layout and must be installed manually.")
        }

        let current = try load(gameID: preview.gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: profileID)
        let replacement = preview.existingModID.flatMap { modID in current.mods.first { $0.id == modID } }
        let gameDirectory = gameURL(for: preview.gameID)
        let stagingID = UUID()
        let stagingDirectory = gameDirectory.appending(path: "Staging/\(stagingID.uuidString)/files", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            var files: [ModFile] = []
            var seen = Set<String>()
            for source in analysis.sourceFiles {
                let relative = try analysis.logicalPath(for: source, extracted: extracted)
                let key = relative.lowercased()
                guard seen.insert(key).inserted else { throw ModManagerError.duplicatePath(relative) }
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw ModManagerError.symbolicLinkNotAllowed(source) }
                let destination = append(relative, to: stagingDirectory)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: destination)
                files.append(ModFile(
                    relativePath: relative,
                    sha256: try RuntimeSecurity.sha256(of: source),
                    size: Int64(values.fileSize ?? 0)
                ))
            }

            if case .dazip(let manifestURL, _) = analysis.kind {
                let manifestDestination = gameDirectory.appending(path: "Staging/\(stagingID.uuidString)/.boreal/Manifest.xml")
                try fileManager.createDirectory(at: manifestDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: manifestURL, to: manifestDestination)
            }

            let archiveDirectory = gameDirectory.appending(path: "Archives", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let archiveName = "\(stagingID.uuidString)-\(preview.archiveName)"
            try fileManager.copyItem(at: preview.archiveURL, to: archiveDirectory.appending(path: archiveName))

            let mod = InstalledMod(
                id: replacement?.id ?? stagingID,
                name: URL(fileURLWithPath: preview.archiveName).deletingPathExtension().lastPathComponent,
                version: replacement?.version,
                enabled: replacement?.enabled ?? true,
                priority: replacement?.priority ?? current.mods.count,
                archiveRelativePath: "Archives/\(archiveName)",
                stagingRelativePath: "Staging/\(stagingID.uuidString)",
                installedAt: .now,
                files: files,
                plugins: [],
                contentType: analysis.contentType,
                deployStrategy: analysis.deployStrategy,
                requirements: analysis.requirements,
                warnings: analysis.warnings
            )
            var mods = current.mods
            if let index = replacement.flatMap({ replacement in mods.firstIndex { $0.id == replacement.id } }) {
                mods[index] = mod
            } else {
                mods.append(mod)
            }
            try saveProfile(
                gameID: preview.gameID,
                profileID: current.profileID,
                profileName: current.profileName,
                mods: mods,
                plugins: []
            )
            if let replacement,
               !isModStorageReferenced(replacement, gameID: preview.gameID, excludingProfileID: current.profileID) {
                if let archive = replacement.archiveRelativePath {
                    try? fileManager.removeItem(at: append(archive, to: gameDirectory))
                }
                try? fileManager.removeItem(at: append(replacement.stagingRelativePath, to: gameDirectory))
            }
            try? fileManager.removeItem(at: preview.archiveURL)
            return try load(gameID: preview.gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: current.profileID)
        } catch {
            try? fileManager.removeItem(at: stagingDirectory.deletingLastPathComponent())
            throw error
        }
    }

    func saveProfile(
        gameID: UUID,
        profileID: String = "default",
        profileName: String = "Default",
        mods: [InstalledMod],
        plugins: [BethesdaPlugin]
    ) throws {
        let gameDirectory = gameURL(for: gameID)
        let normalizedMods = mods.enumerated().map { index, mod -> InstalledMod in
            var value = mod
            value.priority = index
            return value
        }
        try saveJSON(
            ModProfile(gameID: gameID, name: profileName, mods: normalizedMods, plugins: [], updatedAt: .now),
            at: profileURL(for: gameID, profileID: profileID)
        )
        for mod in normalizedMods {
            try saveJSON(mod, at: append("\(mod.stagingRelativePath)/manifest.json", to: gameDirectory))
        }
    }

    func deploy(
        state: ModGameState,
        gameRoot: URL?,
        pluginsFile: URL?
    ) throws -> ModGameState {
        guard let userDataRoot = userDataRoot(gameRoot: gameRoot, pluginsFile: pluginsFile) else {
            throw ModManagerError.dragonAgeDocumentsUnavailable
        }
        let fileManager = FileManager.default
        let gameDirectory = gameURL(for: state.gameID)
        let deploymentURL = gameDirectory.appending(path: "deployment.json")
        let old = (try? read(ModDeploymentManifest.self, at: deploymentURL)) ?? .empty(gameID: state.gameID)
        let resolved = try resolvedFiles(for: state.mods, gameDirectory: gameDirectory)
        try validateManagedFiles(old.files, userDataRoot: userDataRoot)
        try preflightExternalChanges(old.files, userDataRoot: userDataRoot)

        let addInsURL = pluginsFile ?? gameRoot.flatMap { DragonAgeOriginsAdapter.addInsFile(in: $0) }
        let activeAddIns = try activeAddInItems(for: state.mods, gameDirectory: gameDirectory)
        if !activeAddIns.isEmpty && addInsURL == nil {
            throw ModManagerError.dragonAgeDocumentsUnavailable
        }
        if let addInsURL,
           let oldPath = old.pluginFilePath,
           oldPath == addInsURL.standardizedFileURL.path,
           let oldHash = old.pluginFileHash,
           fileManager.fileExists(atPath: addInsURL.path),
           try RuntimeSecurity.sha256(of: addInsURL) != oldHash {
            throw ModManagerError.externalFileChanged(addInsURL.path)
        }

        let transactionURL = gameDirectory.appending(path: ".transactions/\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: transactionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transactionURL) }

        let changedPaths = Set(old.files.values.map(\.path)).union(resolved.values.map(\.path))
        var transactionOriginals: [String: URL] = [:]
        var transactionMissingPaths = Set<String>()
        var transactionAddInsOriginal: URL?
        var transactionAddInsWasMissing = false
        var managedAddInUIDsToSave: [String]?
        do {
            for path in changedPaths {
                let destination = append(path, to: userDataRoot)
                guard fileManager.fileExists(atPath: destination.path) else {
                    transactionMissingPaths.insert(path)
                    continue
                }
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The Dragon Age destination is not a regular file: \(path)")
                }
                let backup = append(path, to: transactionURL)
                try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: destination, to: backup)
                transactionOriginals[path] = backup
            }

            var nextFiles: [String: ModDeploymentFile] = [:]
            for resolvedFile in resolved.values {
                let destination = append(resolvedFile.path, to: userDataRoot)
                let source = append(resolvedFile.source, to: gameDirectory)
                guard try RuntimeSecurity.sha256(of: source) == resolvedFile.sha256 else {
                    throw ModManagerError.stagedFileChanged(resolvedFile.path)
                }
                let oldFile = old.files.values.first {
                    $0.path.caseInsensitiveCompare(resolvedFile.path) == .orderedSame
                }
                let backupInfo = try prepareBackup(
                    destination: destination,
                    gameDirectory: gameDirectory,
                    path: resolvedFile.path,
                    oldFile: oldFile
                )
                try replace(source: source, destination: destination)
                nextFiles[resolvedFile.path.lowercased()] = ModDeploymentFile(
                    path: resolvedFile.path,
                    owner: resolvedFile.owner,
                    sha256: resolvedFile.sha256,
                    source: resolvedFile.source,
                    backup: backupInfo.path,
                    originalHash: backupInfo.originalHash
                )
            }

            for oldFile in old.files.values where resolved[oldFile.path.lowercased()] == nil {
                let destination = append(oldFile.path, to: userDataRoot)
                guard fileManager.fileExists(atPath: destination.path) else { continue }
                if let backup = oldFile.backup {
                    let backupURL = append(backup, to: gameDirectory)
                    if fileManager.fileExists(atPath: backupURL.path) {
                        try replace(source: backupURL, destination: destination)
                    } else {
                        try fileManager.removeItem(at: destination)
                    }
                } else {
                    try fileManager.removeItem(at: destination)
                }
            }

            var next = ModDeploymentManifest(
                gameID: state.gameID,
                deployedAt: .now,
                profileFingerprint: ModProfileFingerprint.make(mods: state.mods, plugins: []),
                files: nextFiles,
                pluginFilePath: old.pluginFilePath,
                pluginFileHash: old.pluginFileHash,
                pluginFileBackup: old.pluginFileBackup,
                pluginFileOriginalHash: old.pluginFileOriginalHash
            )
            if let addInsURL,
               old.pluginFilePath != nil || !activeAddIns.isEmpty {
                if fileManager.fileExists(atPath: addInsURL.path) {
                    let original = transactionURL.appending(path: "AddIns-original.xml")
                    try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: addInsURL, to: original)
                    transactionAddInsOriginal = original
                } else {
                    transactionAddInsWasMissing = true
                }

                if !activeAddIns.isEmpty {
                    let previousManaged = try readManagedAddInUIDs(for: state.gameID)
                    if next.pluginFileBackup == nil,
                       transactionAddInsOriginal != nil {
                        let backupInfo = try prepareAddInsBackup(
                            source: addInsURL,
                            gameDirectory: gameDirectory,
                            old: old
                        )
                        next.pluginFileBackup = backupInfo.path
                        next.pluginFileOriginalHash = backupInfo.originalHash
                    }
                    let baseData: Data?
                    if let backup = old.pluginFileBackup {
                        baseData = try? Data(contentsOf: append(backup, to: gameDirectory))
                    } else {
                        baseData = try? Data(contentsOf: addInsURL)
                    }
                    let generated = makeAddInsXML(
                        base: baseData,
                        removingUIDs: Set(previousManaged),
                        adding: activeAddIns
                    )
                    let temporary = transactionURL.appending(path: "AddIns-generated.xml")
                    try generated.write(to: temporary, options: .atomic)
                    try replace(source: temporary, destination: addInsURL)
                    next.pluginFilePath = addInsURL.standardizedFileURL.path
                    next.pluginFileHash = try RuntimeSecurity.sha256(of: addInsURL)
                    managedAddInUIDsToSave = activeAddIns.map { $0.uid }
                } else {
                    if let backup = old.pluginFileBackup {
                        let backupURL = append(backup, to: gameDirectory)
                        if fileManager.fileExists(atPath: backupURL.path) {
                            try replace(source: backupURL, destination: addInsURL)
                        } else {
                            try fileManager.removeItem(at: addInsURL)
                        }
                    } else if old.pluginFileOriginalHash == nil {
                        try? fileManager.removeItem(at: addInsURL)
                    }
                    next.pluginFilePath = nil
                    next.pluginFileHash = nil
                    managedAddInUIDsToSave = []
                }
            }

            try saveJSON(next, at: deploymentURL)
            try saveProfile(
                gameID: state.gameID,
                profileID: state.profileID,
                profileName: state.profileName,
                mods: state.mods,
                plugins: []
            )
            if let managedAddInUIDsToSave {
                try saveManagedAddInUIDs(managedAddInUIDsToSave, for: state.gameID)
            }
            return try load(gameID: state.gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: state.profileID)
        } catch {
            for (path, original) in transactionOriginals {
                let destination = append(path, to: userDataRoot)
                try? fileManager.removeItem(at: destination)
                try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: original, to: destination)
            }
            for path in transactionMissingPaths {
                try? fileManager.removeItem(at: append(path, to: userDataRoot))
            }
            if let addInsURL, let original = transactionAddInsOriginal {
                try? fileManager.removeItem(at: addInsURL)
                try? fileManager.createDirectory(at: addInsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: original, to: addInsURL)
            } else if let addInsURL, transactionAddInsWasMissing {
                try? fileManager.removeItem(at: addInsURL)
            }
            throw error
        }
    }

    func profiles(for gameID: UUID) -> [ModProfileDescriptor] {
        let directory = gameURL(for: gameID).appending(path: "profiles", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var result = files.compactMap { url -> ModProfileDescriptor? in
            guard url.pathExtension.caseInsensitiveCompare("json") == .orderedSame,
                  let profile = try? read(ModProfile.self, at: url) else { return nil }
            return ModProfileDescriptor(id: url.deletingPathExtension().lastPathComponent, name: profile.name)
        }
        if !result.contains(where: { $0.id.caseInsensitiveCompare("default") == .orderedSame }) {
            result.append(ModProfileDescriptor(id: "default", name: "Default"))
        }
        return result.sorted {
            if $0.id.caseInsensitiveCompare("default") == .orderedSame { return true }
            if $1.id.caseInsensitiveCompare("default") == .orderedSame { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func createProfile(name: String, from state: ModGameState) throws -> ModGameState {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            throw ModManagerError.invalidProfileName
        }
        let profileID = normalizedProfileID(trimmed)
        guard !profiles(for: state.gameID).contains(where: { $0.id.caseInsensitiveCompare(profileID) == .orderedSame }) else {
            throw ModManagerError.profileAlreadyExists(trimmed)
        }
        try saveProfile(gameID: state.gameID, profileID: profileID, profileName: trimmed, mods: state.mods, plugins: [])
        try activateProfile(profileID, for: state.gameID)
        var created = state
        created.profileID = profileID
        created.profileName = trimmed
        return created
    }

    func removeMod(_ modID: UUID, from state: ModGameState) throws -> ModGameState {
        guard let mod = state.mods.first(where: { $0.id == modID }) else { return state }
        let gameDirectory = gameURL(for: state.gameID)
        let fileManager = FileManager.default
        var next = state
        next.mods.removeAll { $0.id == modID }
        try saveProfile(gameID: state.gameID, profileID: state.profileID, profileName: state.profileName, mods: next.mods, plugins: [])
        if !isModStorageReferenced(mod, gameID: state.gameID, excludingProfileID: state.profileID) {
            if let archive = mod.archiveRelativePath {
                let archiveURL = append(archive, to: gameDirectory)
                if fileManager.fileExists(atPath: archiveURL.path) { try fileManager.removeItem(at: archiveURL) }
            }
            let stagingURL = append(mod.stagingRelativePath, to: gameDirectory)
            if fileManager.fileExists(atPath: stagingURL.path) { try fileManager.removeItem(at: stagingURL) }
        }
        return next
    }

    func stagedModURL(gameID: UUID, modID: UUID) -> URL? {
        let directory = gameURL(for: gameID).appending(path: "Staging/\(modID.uuidString)", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }

    func activateProfile(_ profileID: String, for gameID: UUID) throws {
        let url = activeProfileURL(for: gameID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(normalizedProfileID(profileID).utf8).write(to: url, options: .atomic)
    }

    func deploymentHealth(
        for state: ModGameState,
        gameRoot: URL?,
        pluginsFile: URL?
    ) -> ModDeploymentHealth {
        let fileManager = FileManager.default
        var externalChanges: [String] = []
        if let userDataRoot = userDataRoot(gameRoot: gameRoot, pluginsFile: pluginsFile) {
            for entry in state.deployment.files.values {
                let destination = append(entry.path, to: userDataRoot)
                guard fileManager.fileExists(atPath: destination.path),
                      (try? RuntimeSecurity.sha256(of: destination)) == entry.sha256 else {
                    externalChanges.append(entry.path)
                    continue
                }
            }
        } else if !state.deployment.files.isEmpty {
            externalChanges.append("Dragon Age Documents")
        }

        var addInsSynchronized = true
        if let path = state.deployment.pluginFilePath,
           let hash = state.deployment.pluginFileHash,
           let addIns = pluginsFile ?? gameRoot.flatMap({ DragonAgeOriginsAdapter.addInsFile(in: $0) }),
           path == addIns.standardizedFileURL.path {
            addInsSynchronized = fileManager.fileExists(atPath: addIns.path)
                && (try? RuntimeSecurity.sha256(of: addIns)) == hash
        }
        if !addInsSynchronized { externalChanges.append("Settings/AddIns.xml") }

        let managedFilesProtected = state.deployment.deployedAt == nil || state.deployment.files.values.allSatisfy { entry in
            guard entry.originalHash != nil else { return true }
            guard let backup = entry.backup else { return false }
            return fileManager.fileExists(atPath: append(backup, to: gameURL(for: state.gameID)).path)
        }
        let addInsBackupProtected: Bool = {
            guard state.deployment.pluginFileOriginalHash != nil else { return true }
            guard let backup = state.deployment.pluginFileBackup else { return false }
            return fileManager.fileExists(atPath: append(backup, to: gameURL(for: state.gameID)).path)
        }()
        let deployedOwners = Set(state.deployment.files.values.map(\.owner))
        return ModDeploymentHealth(
            deployedModCount: deployedOwners.count,
            managedFileCount: state.deployment.files.count,
            pluginsSynchronized: addInsSynchronized,
            vanillaFilesProtected: managedFilesProtected && addInsBackupProtected,
            externalChanges: Array(Set(externalChanges)).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            validation: state.validation,
            pendingChanges: state.pendingChanges,
            lastDeployment: state.deployment.deployedAt
        )
    }

    func repairRuntime(gameRoot: URL?) throws -> ModRuntimeState? { nil }

    func launchArguments(for gameRoot: URL?) -> [String] { [] }
}

private extension DragonAgeOriginsModManager {
    func userDataRoot(gameRoot: URL?, pluginsFile: URL?) -> URL? {
        if let pluginsFile {
            let normalized = pluginsFile.standardizedFileURL
            let settings = normalized.deletingLastPathComponent()
            let userData = settings.deletingLastPathComponent()
            if normalized.lastPathComponent.caseInsensitiveCompare("AddIns.xml") == .orderedSame,
               settings.lastPathComponent.caseInsensitiveCompare("Settings") == .orderedSame,
               userData.lastPathComponent.caseInsensitiveCompare("Dragon Age") == .orderedSame {
                return userData
            }
        }
        return gameRoot.flatMap { DragonAgeOriginsAdapter.userDataRoot(for: $0) }
    }

    func append(_ relativePath: String, to root: URL) -> URL {
        DragonAgeOriginsAdapter.append(relativePath, to: root)
    }

    enum PackageKind {
        case dazip(manifest: URL, contents: URL)
        case override(URL)
        case manual
    }

    struct PackageAnalysis {
        let kind: PackageKind
        let sourceFiles: [URL]
        let detectedRoot: String
        let contentType: ModContentType
        let deployStrategy: ModDeployStrategy
        let requirements: [String]
        let warnings: [String]
        let canInstallAutomatically: Bool

        func logicalPath(for source: URL, extracted: URL) throws -> String {
            switch kind {
            case .dazip(_, let contents):
                let relative = try Self.relativePath(of: source, from: contents)
                let logical = "Contents/\(relative)"
                if logical.caseInsensitiveCompare("Contents/Settings/AddIns.xml") == .orderedSame {
                    throw ModManagerError.dragonAgeArchiveInvalid("Contents/Settings/AddIns.xml is managed by Boreal and cannot be supplied by a DAZIP.")
                }
                return logical
            case .override(let root):
                let relative = try Self.relativePath(of: source, from: root)
                return "packages/core/override/\(relative)"
            case .manual:
                return try Self.relativePath(of: source, from: extracted)
            }
        }

        private static func relativePath(of url: URL, from root: URL) throws -> String {
            let rootPath = root.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { throw ModManagerError.invalidRelativePath(path) }
            let relative = String(path.dropFirst(rootPath.count + 1)).replacingOccurrences(of: "\\", with: "/")
            let components = relative.split(separator: "/").map(String.init)
            guard !relative.isEmpty,
                  !relative.hasPrefix("/"),
                  !components.contains(".."),
                  !components.contains(where: { $0.contains(":") }) else {
                throw ModManagerError.invalidRelativePath(relative)
            }
            return relative
        }
    }

    struct ResolvedFile {
        let path: String
        let source: String
        let owner: UUID
        let sha256: String
    }

    struct BackupInfo {
        let path: String?
        let originalHash: String?
    }

    struct ManagedAddInState: Codable {
        var uids: [String]
    }

    func analyze(extracted: URL, archiveName: String) throws -> PackageAnalysis {
        let manifest = findFile(named: "Manifest.xml", under: extracted, maxDepth: 3)
        if let manifest,
           let contents = findDirectory(named: "Contents", beside: manifest, under: extracted) {
            let files = try contentFiles(in: contents).filter { url in
                guard let relative = try? relativePath(of: url, from: contents) else { return false }
                return relative.caseInsensitiveCompare("Settings/AddIns.xml") != .orderedSame
            }
            guard !files.isEmpty else {
                throw ModManagerError.dragonAgeArchiveInvalid("The DAZIP Contents directory is empty.")
            }
            return PackageAnalysis(
                kind: .dazip(manifest: manifest, contents: contents),
                sourceFiles: files,
                detectedRoot: "Contents/",
                contentType: .dragonAgeDazip,
                deployStrategy: .dragonAgeDazip,
                requirements: ["Dragon Age: Origins add-in manifest"],
                warnings: [
                    "Boreal will register Manifest.xml in Settings/AddIns.xml during deployment.",
                    "DAZIP and override files use separate Dragon Age load paths."
                ],
                canInstallAutomatically: true
            )
        }
        if archiveName.lowercased().hasSuffix(".dazip") {
            throw ModManagerError.dragonAgeManifestUnavailable
        }

        let overrideRoot = findOverrideDirectory(in: extracted) ?? extracted
        let files = try contentFiles(in: overrideRoot)
        guard !files.isEmpty else { throw ModManagerError.extractedArchiveEmpty }
        let isFlatFallback = overrideRoot.standardizedFileURL.path == extracted.standardizedFileURL.path
        if isFlatFallback {
            let manualExtensions: Set<String> = ["exe", "msi", "bat", "cmd", "ps1", "sh"]
            if files.contains(where: { manualExtensions.contains($0.pathExtension.lowercased()) }) {
                return PackageAnalysis(
                    kind: .manual,
                    sourceFiles: files,
                    detectedRoot: relativeDisplayPath(overrideRoot, from: extracted),
                    contentType: .manual,
                    deployStrategy: .manual,
                    requirements: [],
                    warnings: [
                        "An executable or installer was found. This archive must be installed manually according to its author’s instructions."
                    ],
                    canInstallAutomatically: false
                )
            }
            let payloadFiles = files.filter { !isDocumentationFile($0) }
            guard !payloadFiles.isEmpty else {
                return PackageAnalysis(
                    kind: .manual,
                    sourceFiles: files,
                    detectedRoot: relativeDisplayPath(overrideRoot, from: extracted),
                    contentType: .manual,
                    deployStrategy: .manual,
                    requirements: [],
                    warnings: [
                        "The archive contains documentation but no recognizable Dragon Age resource files."
                    ],
                    canInstallAutomatically: false
                )
            }
            return PackageAnalysis(
                kind: .override(extracted),
                sourceFiles: payloadFiles,
                detectedRoot: relativeDisplayPath(overrideRoot, from: extracted),
                contentType: .dragonAgeOverride,
                deployStrategy: .dragonAgeOverride,
                requirements: [],
                warnings: [
                    "A flat override package was detected. Documentation files are ignored and the remaining files will be deployed to the DAO override directory."
                ],
                canInstallAutomatically: true
            )
        }
        return PackageAnalysis(
            kind: .override(overrideRoot),
            sourceFiles: files,
            detectedRoot: relativeDisplayPath(overrideRoot, from: extracted),
            contentType: .dragonAgeOverride,
            deployStrategy: .dragonAgeOverride,
            requirements: [],
            warnings: [
                "Files will be deployed into Documents/BioWare/Dragon Age/packages/core/override.",
                "Boreal keeps each override package isolated and restores overwritten files on profile changes."
            ],
            canInstallAutomatically: true
        )
    }

    func resolvedFiles(for mods: [InstalledMod], gameDirectory: URL) throws -> [String: ResolvedFile] {
        var result: [String: ResolvedFile] = [:]
        for mod in mods.sorted(by: { $0.priority < $1.priority }) where mod.enabled {
            guard mod.deployStrategy == .dragonAgeOverride || mod.deployStrategy == .dragonAgeDazip else {
                throw ModManagerError.deploymentFailed("The Dragon Age profile contains a mod with an unsupported deployment strategy.")
            }
            for file in mod.files {
                guard isSafeRelativePath(file.relativePath) else { throw ModManagerError.invalidRelativePath(file.relativePath) }
                let target: String
                switch mod.deployStrategy {
                case .dragonAgeOverride:
                    target = file.relativePath
                case .dragonAgeDazip:
                    let prefix = "Contents/"
                    guard file.relativePath.lowercased().hasPrefix(prefix.lowercased()) else {
                        throw ModManagerError.invalidRelativePath(file.relativePath)
                    }
                    target = String(file.relativePath.dropFirst(prefix.count))
                default:
                    throw ModManagerError.deploymentFailed("The Dragon Age profile contains a non-Dragon Age mod.")
                }
                guard isSafeRelativePath(target) else { throw ModManagerError.invalidRelativePath(target) }
                result[target.lowercased()] = ResolvedFile(
                    path: target,
                    source: "\(mod.stagingRelativePath)/files/\(file.relativePath)",
                    owner: mod.id,
                    sha256: file.sha256
                )
            }
        }
        return result
    }

    func activeAddInItems(for mods: [InstalledMod], gameDirectory: URL) throws -> [(uid: String, xml: String)] {
        var result: [(uid: String, xml: String)] = []
        var seen = Set<String>()
        for mod in mods.sorted(by: { $0.priority < $1.priority }) where mod.enabled && mod.deployStrategy == .dragonAgeDazip {
            let manifest = append("\(mod.stagingRelativePath)/.boreal/Manifest.xml", to: gameDirectory)
            let items = try addInItems(from: manifest)
            guard !items.isEmpty else { throw ModManagerError.dragonAgeManifestUnavailable }
            for item in items {
                guard seen.insert(item.uid.lowercased()).inserted else {
                    throw ModManagerError.dragonAgeArchiveInvalid("Two enabled DAZIP packages declare the same add-in UID: \(item.uid).")
                }
                result.append(item)
            }
        }
        return result
    }

    func addInItems(from url: URL) throws -> [(uid: String, xml: String)] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            throw ModManagerError.dragonAgeManifestUnavailable
        }
        let pattern = #"<AddInItem\b[\s\S]*?</AddInItem\s*>|<AddInItem\b[^>]*/>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let uidRegex = try NSRegularExpression(pattern: #"\bUID\s*=\s*[\"']([^\"']+)[\"']"#, options: [.caseInsensitive])
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result: [(uid: String, xml: String)] = []
        for match in regex.matches(in: text, options: [], range: fullRange) {
            guard let itemRange = Range(match.range, in: text) else { continue }
            let xml = String(text[itemRange])
            let itemFullRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
            guard let uidMatch = uidRegex.firstMatch(in: xml, options: [], range: itemFullRange),
                  let uidRange = Range(uidMatch.range(at: 1), in: xml) else { continue }
            result.append((String(xml[uidRange]), xml.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return result
    }

    func makeAddInsXML(
        base: Data?,
        removingUIDs: Set<String>,
        adding: [(uid: String, xml: String)]
    ) -> Data {
        var text = base.flatMap { String(data: $0, encoding: .utf8) }
            ?? "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<AddInsList/>\n"
        let itemPattern = #"<AddInItem\b[\s\S]*?</AddInItem\s*>|<AddInItem\b[^>]*/>"#
        if let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive]) {
            let uidRegex = try? NSRegularExpression(pattern: #"\bUID\s*=\s*[\"']([^\"']+)[\"']"#, options: [.caseInsensitive])
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                let item = String(text[range])
                let uid = uidRegex?.firstMatch(
                    in: item,
                    options: [],
                    range: NSRange(item.startIndex..<item.endIndex, in: item)
                ).flatMap { Range($0.range(at: 1), in: item).map { String(item[$0]) } }
                if let uid, removingUIDs.contains(uid.lowercased()) {
                    text.removeSubrange(range)
                }
            }
        }

        let xmlItems = adding.map { "\n\($0.xml)" }.joined() + "\n"
        if let listRange = text.range(of: #"<AddInsList\b[^>]*/>"#, options: .regularExpression) {
            text.replaceSubrange(listRange, with: "<AddInsList>\(xmlItems)</AddInsList>")
        } else if let closingRange = text.range(of: "</AddInsList>", options: [.caseInsensitive, .backwards]) {
            text.insert(contentsOf: xmlItems, at: closingRange.lowerBound)
        } else {
            text += "\n<AddInsList>\(xmlItems)</AddInsList>\n"
        }
        return Data(text.utf8)
    }

    func prepareAddInsBackup(source: URL, gameDirectory: URL, old: ModDeploymentManifest) throws -> BackupInfo {
        if let oldPath = old.pluginFileBackup {
            return BackupInfo(path: oldPath, originalHash: old.pluginFileOriginalHash)
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            return BackupInfo(path: nil, originalHash: nil)
        }
        let originalHash = try RuntimeSecurity.sha256(of: source)
        let backupRelative = "Backups/\(UUID().uuidString)-AddIns.xml"
        let backup = append(backupRelative, to: gameDirectory)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: backup)
        return BackupInfo(path: backupRelative, originalHash: originalHash)
    }

    func readManagedAddInUIDs(for gameID: UUID) throws -> [String] {
        let url = gameURL(for: gameID).appending(path: "managed-addins.json")
        return try read(ManagedAddInState.self, at: url)?.uids ?? []
    }

    func saveManagedAddInUIDs(_ uids: [String], for gameID: UUID) throws {
        try saveJSON(
            ManagedAddInState(uids: uids.sorted { $0.localizedStandardCompare($1) == .orderedAscending }),
            at: gameURL(for: gameID).appending(path: "managed-addins.json")
        )
    }

    func validateManagedFiles(_ files: [String: ModDeploymentFile], userDataRoot: URL) throws {
        for path in files.values.map(\.path) {
            guard isSafeRelativePath(path) else { throw ModManagerError.invalidRelativePath(path) }
            let destination = append(path, to: userDataRoot)
            if FileManager.default.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The managed Dragon Age destination is unsafe: \(path)")
                }
            }
        }
    }

    func preflightExternalChanges(_ files: [String: ModDeploymentFile], userDataRoot: URL) throws {
        for entry in files.values {
            let destination = append(entry.path, to: userDataRoot)
            guard FileManager.default.fileExists(atPath: destination.path) else { continue }
            guard try RuntimeSecurity.sha256(of: destination) == entry.sha256 else {
                throw ModManagerError.externalFileChanged(entry.path)
            }
        }
    }

    func prepareBackup(
        destination: URL,
        gameDirectory: URL,
        path: String,
        oldFile: ModDeploymentFile?
    ) throws -> BackupInfo {
        let fileManager = FileManager.default
        if let oldFile { return BackupInfo(path: oldFile.backup, originalHash: oldFile.originalHash) }
        guard fileManager.fileExists(atPath: destination.path) else { return BackupInfo(path: nil, originalHash: nil) }
        let originalHash = try RuntimeSecurity.sha256(of: destination)
        let backupRelative = "Backups/\(UUID().uuidString)-\(path.replacingOccurrences(of: "/", with: "_"))"
        let backup = append(backupRelative, to: gameDirectory)
        try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: destination, to: backup)
        return BackupInfo(path: backupRelative, originalHash: originalHash)
    }

    func replace(source: URL, destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }

    func isModStorageReferenced(_ mod: InstalledMod, gameID: UUID, excludingProfileID: String) -> Bool {
        for profile in profiles(for: gameID) where profile.id.caseInsensitiveCompare(excludingProfileID) != .orderedSame {
            let storedProfile: ModProfile?
            do {
                storedProfile = try read(ModProfile.self, at: profileURL(for: gameID, profileID: profile.id))
            } catch {
                return true
            }
            guard let storedProfile else { return true }
            if storedProfile.mods.contains(where: {
                $0.id == mod.id
                    || $0.stagingRelativePath == mod.stagingRelativePath
                    || $0.archiveRelativePath == mod.archiveRelativePath
            }) {
                return true
            }
        }
        return false
    }

    func archiveFormat(for archive: URL) throws -> ModArchiveFormat {
        guard FileManager.default.isReadableFile(atPath: archive.path) else {
            throw ModManagerError.unsupportedArchive(archive)
        }
        if archive.pathExtension.caseInsensitiveCompare("dazip") == .orderedSame {
            return .zip
        }
        guard let format = ModArchiveFormat(fileExtension: archive.pathExtension) else {
            throw ModManagerError.unsupportedArchive(archive)
        }
        return format
    }

    func extract(_ archive: URL, format: ModArchiveFormat) throws -> URL {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appending(path: "boreal-dao-mod-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            let entries = try archiveEntries(archive, format: format)
            for entry in entries where !isSafeRelativePath(entry) { throw ModManagerError.unsafeArchivePath(entry) }
            switch format {
            case .zip:
                guard fileManager.isExecutableFile(atPath: "/usr/bin/ditto") else { throw ModManagerError.archiveToolUnavailable(format) }
                _ = try run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", archive.path, temporary.path])
            case .sevenZip, .rar:
                guard let tool = sevenZipTool() else { throw ModManagerError.archiveToolUnavailable(format) }
                _ = try run(tool, arguments: ["x", "-y", archive.path, "-o\(temporary.path)"])
            }
            _ = try contentFiles(in: temporary)
            return temporary
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func archiveEntries(_ archive: URL, format: ModArchiveFormat) throws -> [String] {
        switch format {
        case .zip:
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else { throw ModManagerError.archiveToolUnavailable(format) }
            return try run(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-Z1", archive.path])
                .split(whereSeparator: \.isNewline).map(String.init)
        case .sevenZip, .rar:
            guard let tool = sevenZipTool() else { throw ModManagerError.archiveToolUnavailable(format) }
            let archivePath = archive.standardizedFileURL.path
            return try run(tool, arguments: ["l", "-slt", archive.path]).split(whereSeparator: \.isNewline).compactMap { raw in
                let line = String(raw)
                guard line.hasPrefix("Path = ") else { return nil }
                let value = String(line.dropFirst("Path = ".count))
                let listedPath = URL(fileURLWithPath: value).standardizedFileURL.path
                guard !value.isEmpty, value != archive.lastPathComponent, listedPath != archivePath else { return nil }
                return value
            }
        }
    }

    func sevenZipTool() -> URL? {
        ["/opt/homebrew/bin/7z", "/opt/homebrew/bin/7zz", "/usr/local/bin/7z", "/usr/local/bin/7zz", "/usr/bin/7z"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func run(_ executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { throw ModManagerError.archiveToolFailed(error.localizedDescription) }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ModManagerError.archiveToolFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    func contentFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { throw ModManagerError.extractedArchiveEmpty }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw ModManagerError.symbolicLinkNotAllowed(url) }
            if values.isRegularFile == true,
               url.lastPathComponent != ".DS_Store",
               !url.pathComponents.contains("__MACOSX") {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func findFile(named name: String, under root: URL, maxDepth: Int) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            let relativeDepth = url.pathComponents.count - root.pathComponents.count
            guard relativeDepth <= maxDepth,
                  url.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            return url
        }
        return nil
    }

    func findDirectory(named name: String, beside file: URL, under root: URL) -> URL? {
        let sibling = file.deletingLastPathComponent().appending(path: name, directoryHint: .isDirectory)
        if (try? sibling.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return sibling }
        return findDirectory(named: name, under: root)
    }

    func findDirectory(named name: String, under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame,
               (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return url
            }
        }
        return nil
    }

    func findOverrideDirectory(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var candidates: [(score: Int, depth: Int, url: URL)] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.caseInsensitiveCompare("override") == .orderedSame,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let components = url.pathComponents.map { $0.lowercased() }
            let score = Array(components.suffix(3)) == ["packages", "core", "override"] ? 0 : 1
            candidates.append((score, url.pathComponents.count, url))
        }
        return candidates.sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.depth < $1.depth
        }.first?.url
    }

    func relativePath(of url: URL, from root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { throw ModManagerError.invalidRelativePath(path) }
        let relative = String(path.dropFirst(rootPath.count + 1)).replacingOccurrences(of: "\\", with: "/")
        guard isSafeRelativePath(relative) else { throw ModManagerError.invalidRelativePath(relative) }
        return relative
    }

    func relativeDisplayPath(_ url: URL, from root: URL) -> String {
        (try? relativePath(of: url, from: root)) ?? "/"
    }

    func isDocumentationFile(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        return ["md", "rtf", "nfo", "txt"].contains(ext)
            || ["readme", "changelog", "license", "licence", "install", "installation"].contains(name)
    }

    func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        return !components.isEmpty && !components.contains("..") && !components.contains(where: { $0.contains(":") })
    }

    func gameURL(for gameID: UUID) -> URL {
        rootURL.appending(path: gameID.uuidString, directoryHint: .isDirectory)
    }

    func profileURL(for gameID: UUID, profileID: String) -> URL {
        gameURL(for: gameID)
            .appending(path: "profiles", directoryHint: .isDirectory)
            .appending(path: "\(normalizedProfileID(profileID)).json")
    }

    func activeProfileURL(for gameID: UUID) -> URL {
        gameURL(for: gameID).appending(path: "active-profile.txt")
    }

    func activeProfileID(for gameID: UUID) -> String {
        guard let data = try? Data(contentsOf: activeProfileURL(for: gameID)),
              let value = String(data: data, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "default" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedProfileID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("default") == .orderedSame { return "default" }
        let result = trimmed.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" { return String(scalar) }
            return "-"
        }.joined().split(separator: "-").joined(separator: "-").lowercased()
        return result.isEmpty ? "profile-\(UUID().uuidString.prefix(8).lowercased())" : result
    }

    func scanManifests(in gameDirectory: URL) -> [InstalledMod] {
        let staging = gameDirectory.appending(path: "Staging", directoryHint: .isDirectory)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap { try? read(InstalledMod.self, at: $0.appending(path: "manifest.json")) }
            .sorted { $0.priority < $1.priority }
    }

    func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    func saveJSON<T: Encodable>(_ value: T, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
