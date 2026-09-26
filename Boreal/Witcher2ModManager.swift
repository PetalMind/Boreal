import Foundation

// MARK: - The Witcher 2 adapter

/// The Witcher 2 has two different mod contracts which must not be mixed:
///
/// * ordinary replacement files and `.dzip` packages are loaded from the
///   installation's `CookedPC` directory;
/// * REDkit adventures and other user-content packages live in
///   `Documents/Witcher 2/UserContent` and are enabled through
///   `Config/UserContent.ini`.
///
/// Boreal stages both layouts separately, deploys them transactionally and
/// never unpacks or rewrites a native DZIP. Script/XML merging is deliberately
/// left as an explicit conflict for the user to resolve.
nonisolated enum Witcher2Adapter {
    static let adapter: ModGameAdapter = .witcher2
    static let steamAppID = "20920"
    static let gogProductID = "1207658930"
    static let knownExecutables = [
        "bin/witcher2.exe",
        "bin/witcher2enhanced.exe",
        "witcher2.exe"
    ]

    static func supports(game: StoreLibraryGame) -> Bool {
        let normalized = game.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let knownIDs = [steamAppID, gogProductID, "the-witcher-2", "witcher-2"]
        return (normalized.contains("witcher 2") || normalized.contains("witcher ii"))
            && !normalized.contains("witcher 3")
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
            if current.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                candidates.append(
                    current.appending(
                        path: "Contents/Resources/Data",
                        directoryHint: .isDirectory
                    )
                )
            }
            if current.pathExtension.caseInsensitiveCompare("exe") == .orderedSame {
                current.deleteLastPathComponent()
            }
            for _ in 0..<6 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }
        if let executable {
            var current = executable.standardizedFileURL.deletingLastPathComponent()
            for _ in 0..<7 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            let root = candidate.standardizedFileURL
            let cookedPC = root.appending(path: "CookedPC", directoryHint: .isDirectory)
            let hasGameContent = fileManager.fileExists(atPath: cookedPC.path)
                && fileManager.fileExists(atPath: root.appending(path: "bin", directoryHint: .isDirectory).path)
            let hasExecutable = knownExecutables.contains {
                fileManager.isReadableFile(atPath: append($0, to: root).path)
            }
            if hasGameContent || hasExecutable { return root }
        }
        return nil
    }

    static func cookedPCRoot(in gameRoot: URL) -> URL {
        gameRoot.appending(path: "CookedPC", directoryHint: .isDirectory)
    }

    /// Resolves the Windows Documents equivalent from a managed Wine prefix.
    /// The game may be stored outside the prefix, so this must not be inferred
    /// from the installation path alone.
    static func userDataRoot(
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
                let candidate = user.appending(path: "\(documents)/Witcher 2", directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        guard let user = ordered.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare("steamuser") == .orderedSame
        }) ?? ordered.first else { return nil }
        return user.appending(path: "My Documents/Witcher 2", directoryHint: .isDirectory)
    }

    static func userDataRoot(
        forGameRoot gameRoot: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var current = gameRoot.standardizedFileURL
        var isNativeMacOSBundle = false
        for _ in 0..<12 {
            if current.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                isNativeMacOSBundle = true
                break
            }
            if current.lastPathComponent.caseInsensitiveCompare("drive_c") == .orderedSame {
                return userDataRoot(inPrefix: current, fileManager: fileManager)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        if isNativeMacOSBundle,
           let applicationSupport = fileManager.urls(
               for: .applicationSupportDirectory,
               in: .userDomainMask
           ).first {
            return applicationSupport.appending(
                path: "com.cdprojektred.TheWitcher2/GameDocuments/Witcher 2",
                directoryHint: .isDirectory
            )
        }
        return nil
    }

    static func append(_ relativePath: String, to root: URL) -> URL {
        relativePath.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }
    }
}

nonisolated enum WitcherModContract: Sendable, Equatable {
    case witcher2
    case witcher3

    var adapter: ModGameAdapter {
        switch self {
        case .witcher2: .witcher2
        case .witcher3: .witcher3
        }
    }

    var storageDirectory: String {
        switch self {
        case .witcher2: "witcher-2"
        case .witcher3: "witcher-3"
        }
    }
}

nonisolated struct WitcherModManager: GameModManaging, Sendable {
    let rootURL: URL
    private let archiveSupport: GTASAModManager
    let contract: WitcherModContract

    var adapter: ModGameAdapter { contract.adapter }

    init(applicationSupportURL: URL, contract: WitcherModContract = .witcher2) {
        self.contract = contract
        rootURL = applicationSupportURL.appending(path: "Mods/\(contract.storageDirectory)", directoryHint: .isDirectory)
        archiveSupport = GTASAModManager(applicationSupportURL: applicationSupportURL)
    }

    func inspect(archive: URL, gameID: UUID) throws -> ModInstallPreview {
        let format = try archiveFormat(for: archive)
        let pendingRoot = gameURL(for: gameID).appending(path: "Archives/.pending", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        let pendingURL = pendingRoot.appending(path: "\(UUID().uuidString)-\(archive.lastPathComponent)")
        try FileManager.default.copyItem(at: archive, to: pendingURL)

        do {
            let analysis: PackageAnalysis
            if format == .dzip {
                analysis = try analyzeStandaloneDZIP(at: pendingURL)
            } else {
                let extracted = try archiveSupport.extract(pendingURL, format: format)
                defer { try? FileManager.default.removeItem(at: extracted) }
                analysis = try analyze(extracted: extracted)
            }
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
                canInstallAutomatically: true,
                totalSize: analysis.sourceFiles.reduce(Int64(0)) {
                    $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                },
                existingModID: ModIdentity.existingModID(
                    for: archive.lastPathComponent,
                    relativePaths: analysis.sourceFiles.map(\.lastPathComponent),
                    in: current
                )
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
        profileID: String? = nil,
        auxiliaryRoot: URL? = nil
    ) throws -> ModGameState {
        let gameDirectory = gameURL(for: gameID)
        let resolvedProfileID = normalizedProfileID(profileID ?? activeProfileID(for: gameID))
        let profile = try read(ModProfile.self, at: profileURL(for: gameID, profileID: resolvedProfileID))
        let deployment = (try? read(ModDeploymentManifest.self, at: gameDirectory.appending(path: "deployment.json")))
            ?? .empty(gameID: gameID)
        let storedMods = profile?.mods ?? scanManifests(in: gameDirectory)
        let discoveredMods = scanExternalMods(in: gameRoot, auxiliaryRoot: auxiliaryRoot, deployment: deployment)
        var mods = ExternalModDiscovery.merge(managed: storedMods, discovered: discoveredMods)
        if contract == .witcher3,
           profile?.mods.contains(where: \.isExternallyDetected) != true,
           let auxiliaryRoot {
            applyExistingWitcher3LoadOrder(from: auxiliaryRoot, to: &mods)
        }
        mods.sort {
            $0.priority == $1.priority
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.priority < $1.priority
        }
        for index in mods.indices { mods[index].priority = index }
        var resolvedDeployment = deployment
        let fingerprint = ModProfileFingerprint.make(
            mods: mods,
            plugins: [],
            includeExternallyDetected: contract == .witcher3
        )
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
            runtime: nil,
            auxiliaryRoot: auxiliaryRoot
        )
    }

    func install(
        preview: ModInstallPreview,
        gameRoot: URL?,
        pluginsFile: URL?,
        profileID: String = "default",
        auxiliaryRoot: URL? = nil
    ) throws -> ModGameState {
        guard preview.adapter == adapter else { throw ModManagerError.unsupportedGame(preview.adapter.displayName) }
        let fileManager = FileManager.default
        let format = try archiveFormat(for: preview.archiveURL)
        let extracted: URL?
        let analysis: PackageAnalysis
        if format == .dzip {
            extracted = nil
            analysis = try analyzeStandaloneDZIP(at: preview.archiveURL)
        } else {
            let directory = try archiveSupport.extract(preview.archiveURL, format: format)
            extracted = directory
            analysis = try analyze(extracted: directory)
        }
        defer {
            if let extracted { try? fileManager.removeItem(at: extracted) }
        }
        guard !analysis.sourceFiles.isEmpty else { throw ModManagerError.extractedArchiveEmpty }

        let current = try load(
            gameID: preview.gameID,
            gameRoot: gameRoot,
            pluginsFile: pluginsFile,
            profileID: profileID,
            auxiliaryRoot: auxiliaryRoot
        )
        let replacement = preview.existingModID.flatMap { id in current.mods.first { $0.id == id } }
        let gameDirectory = gameURL(for: preview.gameID)
        let stagingID = UUID()
        let stagingDirectory = gameDirectory.appending(path: "Staging/\(stagingID.uuidString)/files", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            var files: [ModFile] = []
            var seen = Set<String>()
            for source in analysis.sourceFiles {
                let relative: String
                if format == .dzip {
                    relative = source.lastPathComponent
                } else {
                    relative = try analysis.relativePath(for: source)
                }
                guard isSafeRelativePath(relative), seen.insert(relative.lowercased()).inserted else {
                    throw ModManagerError.duplicatePath(relative)
                }
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
            if let replacement,
               let index = mods.firstIndex(where: { $0.id == replacement.id }) {
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
            return try load(
                gameID: preview.gameID,
                gameRoot: gameRoot,
                pluginsFile: pluginsFile,
                profileID: current.profileID,
                auxiliaryRoot: auxiliaryRoot
            )
        } catch {
            try? fileManager.removeItem(at: stagingDirectory.deletingLastPathComponent())
            throw error
        }
    }

    func saveProfile(
        gameID: UUID,
        profileID: String,
        profileName: String,
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
            at: profileURL(for: gameID, profileID: normalizedProfileID(profileID))
        )
        for mod in normalizedMods where !mod.isExternallyDetected {
            try saveJSON(mod, at: append("\(mod.stagingRelativePath)/manifest.json", to: gameDirectory))
        }
    }

    func deploy(state: ModGameState, gameRoot: URL?, pluginsFile: URL?) throws -> ModGameState {
        guard let gameRoot else { throw ModManagerError.gameRootUnavailable }
        let fileManager = FileManager.default
        let gameDirectory = gameURL(for: state.gameID)
        if contract == .witcher2 {
            try fileManager.createDirectory(at: Witcher2Adapter.cookedPCRoot(in: gameRoot), withIntermediateDirectories: true)
        }
        let old = (try? read(ModDeploymentManifest.self, at: gameDirectory.appending(path: "deployment.json")))
            ?? .empty(gameID: state.gameID)
        let userRoot = state.auxiliaryRoot
        let hasUserContent = contract == .witcher2 && (
            state.mods.contains {
                $0.enabled && !$0.isExternallyDetected && $0.deployStrategy == .witcher2UserContent
            } || old.files.keys.contains {
                $0.lowercased().hasPrefix("usercontent/") || $0.lowercased().hasPrefix("userconfig/")
            }
        )
        if hasUserContent && userRoot == nil {
            throw ModManagerError.witcher2DocumentsUnavailable
        }
        if let userRoot, contract == .witcher2 {
            try fileManager.createDirectory(at: userRoot.appending(path: "UserContent", directoryHint: .isDirectory), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: userRoot.appending(path: "Config", directoryHint: .isDirectory), withIntermediateDirectories: true)
        }

        var resolved = try resolvedFiles(for: state.mods)
        let packageNames = userContentPackageNames(for: state.mods)
        var witcher3Folders: [String] = []
        if contract == .witcher2, !packageNames.isEmpty {
            guard let userRoot else { throw ModManagerError.witcher2DocumentsUnavailable }
            let config = try makeUserContentINI(
                at: userRoot.appending(path: "Config/UserContent.ini"),
                removing: Set(old.managedUserContentPackages),
                adding: packageNames
            )
            let hash = RuntimeSecurity.sha256(data: Data(config.utf8))
            resolved[Self.userConfigPath.lowercased()] = ResolvedFile(
                targetPath: Self.userConfigPath,
                owner: Self.generatedOwner,
                source: nil,
                content: Data(config.utf8),
                sha256: hash
            )
        }
        if contract == .witcher3 {
            witcher3Folders = witcher3ModFolderNames(in: state.mods)
            let oldHasSettings = old.files.values.contains {
                $0.path.caseInsensitiveCompare(Self.witcher3SettingsPath) == .orderedSame
            }
            let hasUserDataFiles = resolved.values.contains {
                $0.targetPath.lowercased().hasPrefix("userdata/")
            } || old.files.values.contains {
                $0.path.lowercased().hasPrefix("userdata/")
            }
            if (witcher3Folders.isEmpty == false || oldHasSettings || hasUserDataFiles), userRoot == nil {
                throw ModManagerError.witcher3DocumentsUnavailable
            }
            if !witcher3Folders.isEmpty, let userRoot {
                let settings = try makeWitcher3ModsSettings(
                    at: userRoot.appending(path: "mods.settings"),
                    removing: Set(old.managedWitcher3ModFolders),
                    mods: state.mods
                )
                let bytes = Data(settings.utf8)
                resolved[Self.witcher3SettingsPath.lowercased()] = ResolvedFile(
                    targetPath: Self.witcher3SettingsPath,
                    owner: Self.generatedOwner,
                    source: nil,
                    content: bytes,
                    sha256: RuntimeSecurity.sha256(data: bytes)
                )
            }
        }

        try validateManagedFiles(old.files, gameRoot: gameRoot, userRoot: userRoot)
        try preflightExternalChanges(old.files, gameRoot: gameRoot, userRoot: userRoot)
        let transactionURL = gameDirectory.appending(path: ".transactions/\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: transactionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transactionURL) }
        let changedPaths = Set(old.files.values.map(\.path)).union(resolved.values.map(\.targetPath))
        var transactionOriginals: [String: URL] = [:]
        var transactionMissing = Set<String>()

        do {
            for path in changedPaths {
                guard let destination = destinationURL(
                    for: path,
                    gameRoot: gameRoot,
                    userRoot: userRoot
                ) else { throw ModManagerError.invalidRelativePath(path) }
                guard fileManager.fileExists(atPath: destination.path) else {
                    transactionMissing.insert(path)
                    continue
                }
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The \(adapter.displayName) destination is not a regular file: \(path)")
                }
                let backup = transactionURL.appending(path: "originals/\(UUID().uuidString)")
                try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: destination, to: backup)
                transactionOriginals[path] = backup
            }

            var nextFiles: [String: ModDeploymentFile] = [:]
            for resolvedFile in resolved.values {
                guard let destination = destinationURL(for: resolvedFile.targetPath, gameRoot: gameRoot, userRoot: userRoot) else {
                    throw ModManagerError.invalidRelativePath(resolvedFile.targetPath)
                }
                let source: URL
                if let stagedSource = resolvedFile.source {
                    source = append(stagedSource, to: gameDirectory)
                    guard try RuntimeSecurity.sha256(of: source) == resolvedFile.sha256 else {
                        throw ModManagerError.stagedFileChanged(resolvedFile.targetPath)
                    }
                } else {
                    let generatedName = contract == .witcher3 ? "mods.settings" : "UserContent.ini"
                    source = transactionURL.appending(path: "generated/\(generatedName)")
                    try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try resolvedFile.content?.write(to: source, options: .atomic)
                }
                let oldFile = old.files.values.first {
                    $0.path.caseInsensitiveCompare(resolvedFile.targetPath) == .orderedSame
                }
                let backup = try prepareBackup(
                    destination: destination,
                    gameDirectory: gameDirectory,
                    path: resolvedFile.targetPath,
                    oldFile: oldFile
                )
                try replace(source: source, destination: destination)
                nextFiles[resolvedFile.targetPath.lowercased()] = ModDeploymentFile(
                    path: resolvedFile.targetPath,
                    owner: resolvedFile.owner,
                    sha256: resolvedFile.sha256,
                    source: resolvedFile.source ?? "generated/\(contract == .witcher3 ? "mods.settings" : "UserContent.ini")",
                    backup: backup.path,
                    originalHash: backup.originalHash
                )
            }

            for oldFile in old.files.values where resolved[oldFile.path.lowercased()] == nil {
                guard let destination = destinationURL(for: oldFile.path, gameRoot: gameRoot, userRoot: userRoot),
                      fileManager.fileExists(atPath: destination.path) else { continue }
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

            let next = ModDeploymentManifest(
                gameID: state.gameID,
                deployedAt: .now,
                profileFingerprint: ModProfileFingerprint.make(
                    mods: state.mods,
                    plugins: [],
                    includeExternallyDetected: contract == .witcher3
                ),
                files: nextFiles,
                pluginFilePath: nil,
                pluginFileHash: nil,
                pluginFileBackup: nil,
                pluginFileOriginalHash: nil,
                managedUserContentPackages: packageNames,
                managedWitcher3ModFolders: witcher3Folders
            )
            try saveJSON(next, at: gameDirectory.appending(path: "deployment.json"))
            try saveProfile(gameID: state.gameID, profileID: state.profileID, profileName: state.profileName, mods: state.mods, plugins: [])
            var returned = try load(
                gameID: state.gameID,
                gameRoot: gameRoot,
                pluginsFile: nil,
                profileID: state.profileID,
                auxiliaryRoot: state.auxiliaryRoot
            )
            returned.auxiliaryRoot = state.auxiliaryRoot
            return returned
        } catch {
            for (path, original) in transactionOriginals {
                guard let destination = destinationURL(for: path, gameRoot: gameRoot, userRoot: userRoot) else { continue }
                try? fileManager.removeItem(at: destination)
                try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: original, to: destination)
            }
            for path in transactionMissing {
                if let destination = destinationURL(for: path, gameRoot: gameRoot, userRoot: userRoot) {
                    try? fileManager.removeItem(at: destination)
                }
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
        guard let mod = state.mods.first(where: { $0.id == modID }), !mod.isExternallyDetected else { return state }
        let gameDirectory = gameURL(for: state.gameID)
        let fileManager = FileManager.default
        if let archive = mod.archiveRelativePath {
            try? fileManager.removeItem(at: append(archive, to: gameDirectory))
        }
        try? fileManager.removeItem(at: append(mod.stagingRelativePath, to: gameDirectory))
        var next = state
        next.mods.removeAll { $0.id == modID }
        try saveProfile(gameID: state.gameID, profileID: state.profileID, profileName: state.profileName, mods: next.mods, plugins: [])
        return next
    }

    func stagedModURL(gameID: UUID, modID: UUID) -> URL? {
        let url = gameURL(for: gameID).appending(path: "Staging/\(modID.uuidString)", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func activateProfile(_ profileID: String, for gameID: UUID) throws {
        let url = activeProfileURL(for: gameID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(normalizedProfileID(profileID).utf8).write(to: url, options: .atomic)
    }

    func deploymentHealth(for state: ModGameState, gameRoot: URL?, pluginsFile: URL?, auxiliaryRoot: URL? = nil) -> ModDeploymentHealth {
        let fileManager = FileManager.default
        var externalChanges: [String] = []
        for entry in state.deployment.files.values {
            guard let destination = destinationURL(for: entry.path, gameRoot: gameRoot, userRoot: auxiliaryRoot ?? state.auxiliaryRoot),
                  fileManager.fileExists(atPath: destination.path),
                  (try? RuntimeSecurity.sha256(of: destination)) == entry.sha256 else {
                externalChanges.append(entry.path)
                continue
            }
        }
        let protected = state.deployment.files.values.allSatisfy { entry in
            guard entry.originalHash != nil else { return true }
            guard let backup = entry.backup else { return false }
            return fileManager.fileExists(atPath: append(backup, to: gameURL(for: state.gameID)).path)
        }
        let owners = Set(state.deployment.files.values.map(\.owner)).intersection(Set(state.mods.map(\.id)))
        return ModDeploymentHealth(
            deployedModCount: owners.count,
            managedFileCount: state.deployment.files.count,
            pluginsSynchronized: true,
            vanillaFilesProtected: protected,
            externalChanges: Array(Set(externalChanges)).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            validation: state.validation,
            pendingChanges: state.pendingChanges,
            lastDeployment: state.deployment.deployedAt
        )
    }

    func repairRuntime(gameRoot: URL?) throws -> ModRuntimeState? { nil }

    func launchArguments(for gameRoot: URL?) -> [String] { [] }
}

typealias Witcher2ModManager = WitcherModManager

private extension WitcherModManager {
    static let generatedOwner = UUID(uuidString: "4C7A6A7E-8F0F-4F40-8D8B-4C59C27C6D2B")!
    static let userConfigPath = "UserConfig/UserContent.ini"
    static let witcher3SettingsPath = "UserConfig/mods.settings"

    struct PackageAnalysis {
        let root: URL
        let sourceFiles: [URL]
        let detectedRoot: String
        let contentType: ModContentType
        let deployStrategy: ModDeployStrategy
        let requirements: [String]
        let warnings: [String]
        var routesWitcher3Payload = false

        func relativePath(for source: URL) throws -> String {
            let rootPath = root.standardizedFileURL.path
            let path = source.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { throw ModManagerError.invalidRelativePath(path) }
            let relative = String(path.dropFirst(rootPath.count + 1)).replacingOccurrences(of: "\\", with: "/")
            let components = relative.split(separator: "/").map(String.init)
            guard !relative.isEmpty,
                  !relative.hasPrefix("/"),
                  !components.contains(".."),
                  !components.contains(where: { $0.contains(":" ) }) else {
                throw ModManagerError.invalidRelativePath(relative)
            }
            guard routesWitcher3Payload else { return relative }
            let normalized = relative.replacingOccurrences(of: "\\", with: "/")
            var routed = normalized.split(separator: "/").map(String.init)
            guard let first = routed.first else { throw ModManagerError.invalidRelativePath(relative) }
            let lower = first.lowercased()
            if lower == "mods" || lower == "dlc" {
                routed[0] = lower == "mods" ? "Mods" : "DLC"
            } else if lower == "documents" {
                guard routed.count >= 3,
                      routed[1].caseInsensitiveCompare("The Witcher 3") == .orderedSame else {
                    throw ModManagerError.witcher3ArchiveInvalid("Documents payloads must be inside a The Witcher 3 folder.")
                }
                routed = ["UserData"] + Array(routed.dropFirst(2))
            } else if first.caseInsensitiveCompare("The Witcher 3") == .orderedSame {
                let second = routed.dropFirst().first?.lowercased()
                if ["mods", "dlc", "bin", "content", "redkit"].contains(second ?? "") {
                    routed = Array(routed.dropFirst())
                } else {
                    routed = ["UserData"] + Array(routed.dropFirst())
                }
            } else if lower == "userdata" {
                routed[0] = "UserData"
            } else if lower.hasPrefix("mod") {
                routed.insert("Mods", at: 0)
            } else if lower.hasPrefix("dlc") {
                routed.insert("DLC", at: 0)
            } else if routed.count == 1,
                      ["input.settings", "user.settings"].contains(lower) {
                routed.insert("UserData", at: 0)
            }
            let target = routed.joined(separator: "/")
            if target.caseInsensitiveCompare("UserData/mods.settings") == .orderedSame {
                throw ModManagerError.witcher3ArchiveInvalid("Boreal owns mods.settings while a Witcher 3 profile is deployed. Import other Documents/The Witcher 3 files separately.")
            }
            guard !target.isEmpty, isValidRelativePath(target) else {
                throw ModManagerError.invalidRelativePath(target)
            }
            return target
        }

        private func isValidRelativePath(_ path: String) -> Bool {
            let components = path.split(separator: "/").map(String.init)
            return !path.hasPrefix("/") && !components.contains("..") && !components.contains(where: { $0.contains(":") })
        }
    }

    struct ResolvedFile {
        let targetPath: String
        let owner: UUID
        let source: String?
        let content: Data?
        let sha256: String
    }

    struct BackupInfo {
        let path: String?
        let originalHash: String?
    }

    func archiveFormat(for archive: URL) throws -> ModArchiveFormat {
        guard FileManager.default.isReadableFile(atPath: archive.path) else {
            throw ModManagerError.unsupportedArchive(archive)
        }
        if archive.pathExtension.caseInsensitiveCompare("dzip") == .orderedSame {
            guard contract == .witcher2 else { throw ModManagerError.unsupportedArchive(archive) }
            return .dzip
        }
        return try archiveSupport.archiveFormat(for: archive)
    }

    func analyzeStandaloneDZIP(at url: URL) throws -> PackageAnalysis {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ModManagerError.symbolicLinkNotAllowed(url)
        }
        return PackageAnalysis(
            root: url.deletingLastPathComponent(),
            sourceFiles: [url],
            detectedRoot: "CookedPC",
            contentType: .witcher2CookedPC,
            deployStrategy: .witcher2CookedPC,
            requirements: [],
            warnings: ["The DZIP will be copied unchanged into CookedPC; Boreal does not unpack or merge native Witcher 2 archives."]
        )
    }

    func analyze(extracted: URL) throws -> PackageAnalysis {
        if contract == .witcher3 { return try analyzeWitcher3(extracted: extracted) }
        return try analyzeWitcher2(extracted: extracted)
    }

    func analyzeWitcher2(extracted: URL) throws -> PackageAnalysis {
        let files = try archiveSupport.contentFiles(in: extracted)
        guard !files.isEmpty else { throw ModManagerError.extractedArchiveEmpty }
        let cooked = findDirectory(named: "CookedPC", under: extracted)
        let userContent = findDirectory(named: "UserContent", under: extracted)
        if cooked != nil, userContent != nil {
            throw ModManagerError.witcher2ArchiveInvalid("The archive contains both CookedPC and UserContent payloads. Import them as separate archives so Boreal can deploy each root safely.")
        }
        if let cooked {
            let selected = files.filter { isDescendant($0, of: cooked) }
            guard !selected.isEmpty else { throw ModManagerError.extractedArchiveEmpty }
            return PackageAnalysis(
                root: cooked,
                sourceFiles: selected,
                detectedRoot: "CookedPC",
                contentType: .witcher2CookedPC,
                deployStrategy: .witcher2CookedPC,
                requirements: [],
                warnings: ["Files will be deployed into CookedPC and original files will be backed up before replacement."]
            )
        }
        if let userContent {
            let selected = files.filter { isDescendant($0, of: userContent) }
            guard !selected.isEmpty else { throw ModManagerError.extractedArchiveEmpty }
            return userContentAnalysis(root: userContent, files: selected, detectedRoot: "Documents/Witcher 2/UserContent")
        }

        let topLevelDirectories = (try? FileManager.default.contentsOfDirectory(
            at: extracted,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
        if topLevelDirectories.count == 1,
           let candidate = topLevelDirectories.first,
           looksLikeUserContent(candidate, files: files) {
            return userContentAnalysis(root: extracted, files: files, detectedRoot: "Documents/Witcher 2/UserContent")
        }
        if topLevelDirectories.count == 1,
           let candidate = topLevelDirectories.first {
            let selected = files.filter { isDescendant($0, of: candidate) }
            if selected.count == files.count, !selected.isEmpty {
                return PackageAnalysis(
                    root: candidate,
                    sourceFiles: selected,
                    detectedRoot: "CookedPC",
                    contentType: .witcher2CookedPC,
                    deployStrategy: .witcher2CookedPC,
                    requirements: [],
                    warnings: ["The archive has a single wrapper folder; its contents will be overlaid relative to CookedPC."]
                )
            }
        }
        return PackageAnalysis(
            root: extracted,
            sourceFiles: files,
            detectedRoot: "CookedPC",
            contentType: .witcher2CookedPC,
            deployStrategy: .witcher2CookedPC,
            requirements: [],
            warnings: ["The archive has no CookedPC wrapper; its files will be overlaid relative to CookedPC."]
        )
    }

    func analyzeWitcher3(extracted: URL) throws -> PackageAnalysis {
        let files = try archiveSupport.contentFiles(in: extracted)
        guard !files.isEmpty else { throw ModManagerError.extractedArchiveEmpty }

        var root = extracted
        let installationFolders: Set<String> = ["mods", "dlc", "bin", "content", "redkit", "documents", "userdata", "the witcher 3"]
        for _ in 0..<4 {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let directories = children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            let rootFiles = children.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            guard directories.count == 1, rootFiles.isEmpty, let candidate = directories.first else { break }
            let lower = candidate.lastPathComponent.lowercased()
            if installationFolders.contains(lower) || lower.hasPrefix("mod") || lower.hasPrefix("dlc") {
                break
            }
            root = candidate
        }

        let selected = try archiveSupport.contentFiles(in: root)
        guard !selected.isEmpty else { throw ModManagerError.extractedArchiveEmpty }
        let targetPaths = try selected.map { try witcher3TargetPath(for: $0, relativeTo: root) }
        let allModFolders = !targetPaths.isEmpty && targetPaths.allSatisfy(isWitcher3ModPath)
        let allDLCFolders = !targetPaths.isEmpty && targetPaths.allSatisfy(isWitcher3DLCPath)
        let contentType: ModContentType = allModFolders
            ? .witcher3Mod
            : allDLCFolders ? .witcher3DLC : .witcher3GameFiles
        let detectedRoot: String = allModFolders
            ? "Game/Mods"
            : allDLCFolders ? "Game/DLC" : "Game folder and Documents/The Witcher 3"
        var warnings = [
            "Boreal will stage this archive first and keep a backup of every game file it replaces.",
            "Conflicting Witcher 3 scripts need a Script Merger review; Boreal reports conflicts but does not merge script code."
        ]
        if !allModFolders && !allDLCFolders {
            warnings.append("This archive includes game-root or user-data files. Review the mod author’s installation instructions before deploying it.")
        }
        if targetPaths.contains(where: { $0.lowercased().hasPrefix("userdata/") }) {
            warnings.append("User-data files will be deployed inside the linked Wine prefix’s Documents/The Witcher 3 folder.")
        }
        return PackageAnalysis(
            root: root,
            sourceFiles: selected,
            detectedRoot: detectedRoot,
            contentType: contentType,
            deployStrategy: .witcher3GameRoot,
            requirements: [],
            warnings: warnings,
            routesWitcher3Payload: true
        )
    }

    func witcher3TargetPath(for source: URL, relativeTo root: URL) throws -> String {
        let relative = try PackageAnalysis(
            root: root,
            sourceFiles: [],
            detectedRoot: "",
            contentType: .witcher3GameFiles,
            deployStrategy: .witcher3GameRoot,
            requirements: [],
            warnings: [],
            routesWitcher3Payload: true
        ).relativePath(for: source)
        return relative
    }

    func isWitcher3ModPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        return components.count >= 3
            && components[0].caseInsensitiveCompare("Mods") == .orderedSame
            && components[1].lowercased().hasPrefix("mod")
    }

    func isWitcher3DLCPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        return components.count >= 3
            && components[0].caseInsensitiveCompare("DLC") == .orderedSame
            && components[1].lowercased().hasPrefix("dlc")
    }

    func userContentAnalysis(root: URL, files: [URL], detectedRoot: String) -> PackageAnalysis {
        PackageAnalysis(
            root: root,
            sourceFiles: files,
            detectedRoot: detectedRoot,
            contentType: .witcher2UserContent,
            deployStrategy: .witcher2UserContent,
            requirements: ["The Witcher 2 Enhanced Edition with User Content support"],
            warnings: [
                "Files will be kept as a separate UserContent package and mounted in Config/UserContent.ini.",
                "REDkit adventures are selected in the game's New Game → User Content menu after deployment."
            ]
        )
    }

    func looksLikeUserContent(_ candidate: URL, files: [URL]) -> Bool {
        let markers = Set(["mod.info", "mod.xml", "metadata.xml", "worlds", "quests", "quest", "scenes"])
        if markers.contains(where: {
            FileManager.default.fileExists(atPath: candidate.appending(path: $0).path)
        }) {
            return true
        }
        for file in files where isDescendant(file, of: candidate) {
            let lower = file.lastPathComponent.lowercased()
            if markers.contains(lower) || ["w2scene", "w2ent", "w2comm"].contains(file.pathExtension.lowercased()) {
                return true
            }
        }
        return false
    }

    func findDirectory(named name: String, under root: URL) -> URL? {
        if root.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame { return root }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return url }
        }
        return nil
    }

    func isDescendant(_ url: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(rootPath + "/")
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

    func scanExternalMods(in gameRoot: URL?, auxiliaryRoot: URL?, deployment: ModDeploymentManifest) -> [InstalledMod] {
        guard let gameRoot else { return [] }
        if contract == .witcher3 {
            return scanExternalWitcher3Mods(in: gameRoot, deployment: deployment)
        }
        let fileManager = FileManager.default
        let cookedRoot = Witcher2Adapter.cookedPCRoot(in: gameRoot)
        let managedPaths = Set(deployment.files.values.map { $0.path.lowercased() })
        var result: [InstalledMod] = []

        let vanillaDZIPs = Set([
            "pack0", "base_scripts", "arena", "darkdiff", "dlc_finishers", "elf_flotsam",
            "hairdresser", "harpy_feathers", "krbr", "magical_suit", "merchant", "roche_jacket",
            "succubuss", "summer", "swordsman_suit", "troll", "tutorial", "winter", "alchemy_suit"
        ])
        let cookedFiles = (try? fileManager.contentsOfDirectory(
            at: cookedRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && $0.pathExtension.caseInsensitiveCompare("dzip") == .orderedSame
                && !vanillaDZIPs.contains($0.deletingPathExtension().lastPathComponent.lowercased())
                && !managedPaths.contains("cookedpc/\($0.lastPathComponent.lowercased())")
        } ?? []
        if let mod = ExternalModDiscovery.makeMod(
            adapter: adapter,
            name: "External Witcher 2 CookedPC files",
            detectionKey: "cookedpc-external",
            files: cookedFiles,
            relativeTo: cookedRoot,
            contentType: .witcher2CookedPC,
            requirements: []
        ) {
            result.append(mod)
        }

        if let userRoot = auxiliaryRoot ?? Witcher2Adapter.userDataRoot(forGameRoot: gameRoot),
           let children = try? fileManager.contentsOfDirectory(
               at: userRoot.appending(path: "UserContent", directoryHint: .isDirectory),
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles]
           ) {
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                guard let files = try? archiveSupport.contentFiles(in: child), !files.isEmpty else { continue }
                let packagePath = "UserContent/\(child.lastPathComponent)".lowercased()
                guard !managedPaths.contains(where: { $0.hasPrefix(packagePath + "/") }) else { continue }
                if let mod = ExternalModDiscovery.makeMod(
                    adapter: adapter,
                    name: child.lastPathComponent,
                    detectionKey: "user-content/\(child.lastPathComponent)",
                    files: files,
                    relativeTo: child,
                    contentType: .witcher2UserContent,
                    requirements: ["The Witcher 2 User Content"]
                ) {
                    result.append(mod)
                }
            }
        }
        return result
    }

    func scanExternalWitcher3Mods(in gameRoot: URL, deployment: ModDeploymentManifest) -> [InstalledMod] {
        let fileManager = FileManager.default
        let modsRoot = Witcher3Adapter.contentDirectory(named: "Mods", in: gameRoot, fileManager: fileManager)
        let managedPaths = Set(deployment.files.values.map { ExternalModDiscovery.normalizedPath($0.path) })
        guard let rootValues = try? modsRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: modsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.compactMap { child in
            guard child.lastPathComponent.lowercased().hasPrefix("mod"),
                  let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let allFiles = try? archiveSupport.contentFiles(in: child) else { return nil }
            let folderPrefix = ExternalModDiscovery.normalizedPath("Mods/\(child.lastPathComponent)/")
            let externalFiles = allFiles.filter { file in
                guard let relative = ExternalModDiscovery.relativePath(of: file, from: gameRoot) else { return false }
                return !managedPaths.contains(ExternalModDiscovery.normalizedPath(relative))
            }
            guard !externalFiles.isEmpty else { return nil }
            let contents = externalFiles.compactMap { ExternalModDiscovery.relativePath(of: $0, from: gameRoot) }
            guard contents.allSatisfy({ ExternalModDiscovery.normalizedPath($0).hasPrefix(folderPrefix) }) else { return nil }
            return ExternalModDiscovery.makeMod(
                adapter: adapter,
                name: child.lastPathComponent,
                detectionKey: "mods/\(child.lastPathComponent)",
                files: externalFiles,
                relativeTo: gameRoot,
                contentType: .witcher3Mod,
                requirements: ["The Witcher 3 script or bundle conflicts may need Script Merger."]
            )
        }
    }

    func applyExistingWitcher3LoadOrder(from documentsRoot: URL, to mods: inout [InstalledMod]) {
        let settings = witcher3LoadSettings(at: documentsRoot.appending(path: "mods.settings"))
        guard !settings.isEmpty else { return }
        for index in mods.indices where mods[index].isExternallyDetected {
            let folders = witcher3ModFolderNames(in: [mods[index]])
            let values = folders.compactMap { settings[$0.lowercased()] }
            guard !values.isEmpty else { continue }
            mods[index].enabled = values.allSatisfy(\.enabled)
            mods[index].priority = (values.map(\.priority).min() ?? 1) - 1
        }
    }

    func witcher3LoadSettings(at url: URL) -> [String: (enabled: Bool, priority: Int)] {
        guard let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: (enabled: Bool, priority: Int)] = [:]
        var currentSection: String?
        var enabled = true
        var priority: Int?

        func saveCurrent() {
            guard let currentSection else { return }
            result[currentSection] = (enabled, priority ?? 10_000)
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("["), line.hasSuffix("]"), line.count > 2 {
                saveCurrent()
                currentSection = String(line.dropFirst().dropLast()).lowercased()
                enabled = true
                priority = nil
                continue
            }
            guard let currentSection,
                  let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if key == "enabled", let parsed = Int(value) { enabled = parsed != 0 }
            if key == "priority", let parsed = Int(value), (1...9999).contains(parsed) { priority = parsed }
            _ = currentSection
        }
        saveCurrent()
        return result
    }

    func witcher3ModFolderNames(in mods: [InstalledMod]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for mod in mods.sorted(by: { $0.priority < $1.priority }) {
            for file in mod.files {
                let components = file.relativePath.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
                guard components.count >= 3,
                      components[0].caseInsensitiveCompare("Mods") == .orderedSame,
                      components[1].lowercased().hasPrefix("mod") else { continue }
                let key = components[1].lowercased()
                if seen.insert(key).inserted { result.append(components[1]) }
            }
        }
        return result
    }

    func makeWitcher3ModsSettings(
        at url: URL,
        removing oldFolders: Set<String>,
        mods: [InstalledMod]
    ) throws -> String {
        let original = String(data: (try? Data(contentsOf: url)) ?? Data(), encoding: .utf8) ?? ""
        let removeSet = Set(oldFolders.map { $0.lowercased() }).union(witcher3ModFolderNames(in: mods).map { $0.lowercased() })
        let lines = original.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var preserved: [String] = []
        var removingSection = false
        for line in lines {
            let header = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if header.hasPrefix("["), header.hasSuffix("]"), header.count > 2 {
                let section = String(header.dropFirst().dropLast()).lowercased()
                removingSection = removeSet.contains(section)
            }
            if !removingSection { preserved.append(line) }
        }
        while preserved.last?.isEmpty == true { preserved.removeLast() }

        var values: [String: (name: String, enabled: Bool, priority: Int)] = [:]
        for mod in mods.sorted(by: { $0.priority < $1.priority }) {
            for name in witcher3ModFolderNames(in: [mod]) {
                let key = name.lowercased()
                let requestedPriority = min(max(mod.priority + 1, 1), 9999)
                if let existing = values[key] {
                    values[key] = (existing.name, existing.enabled || mod.enabled, min(existing.priority, requestedPriority))
                } else {
                    values[key] = (name, mod.enabled, requestedPriority)
                }
            }
        }
        let generated = values.values.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.flatMap { value in
            ["[\(value.name)]", "Enabled=\(value.enabled ? 1 : 0)", "Priority=\(value.priority)"]
        }
        guard !generated.isEmpty else { return preserved.joined(separator: "\n") + (preserved.isEmpty ? "" : "\n") }
        if !preserved.isEmpty { preserved.append("") }
        preserved.append(contentsOf: generated)
        return preserved.joined(separator: "\n") + "\n"
    }

    func resolvedFiles(for mods: [InstalledMod]) throws -> [String: ResolvedFile] {
        var result: [String: ResolvedFile] = [:]
        for mod in mods.sorted(by: { $0.priority < $1.priority }) where mod.enabled && !mod.isExternallyDetected {
            if contract == .witcher3, mod.deployStrategy == .witcher3GameRoot {
                for file in mod.files {
                    guard isSafeRelativePath(file.relativePath) else { throw ModManagerError.invalidRelativePath(file.relativePath) }
                    result[file.relativePath.lowercased()] = ResolvedFile(
                        targetPath: file.relativePath,
                        owner: mod.id,
                        source: "\(mod.stagingRelativePath)/files/\(file.relativePath)",
                        content: nil,
                        sha256: file.sha256
                    )
                }
                continue
            }
            guard mod.deployStrategy == .witcher2CookedPC || mod.deployStrategy == .witcher2UserContent else {
                continue
            }
            for file in mod.files {
                guard isSafeRelativePath(file.relativePath) else { throw ModManagerError.invalidRelativePath(file.relativePath) }
                let target: String
                switch mod.deployStrategy {
                case .witcher2CookedPC:
                    target = "CookedPC/\(file.relativePath)"
                case .witcher2UserContent:
                    let package = userContentPackageName(for: mod)
                    let first = file.relativePath.split(separator: "/").first.map(String.init)
                    let packageRelative = first?.caseInsensitiveCompare(package) == .orderedSame
                        ? file.relativePath
                        : "\(package)/\(file.relativePath)"
                    target = "UserContent/\(packageRelative)"
                default:
                    continue
                }
                result[target.lowercased()] = ResolvedFile(
                    targetPath: target,
                    owner: mod.id,
                    source: "\(mod.stagingRelativePath)/files/\(file.relativePath)",
                    content: nil,
                    sha256: file.sha256
                )
            }
        }
        return result
    }

    func userContentPackageNames(for mods: [InstalledMod]) -> [String] {
        mods.filter { $0.enabled && !$0.isExternallyDetected && $0.deployStrategy == .witcher2UserContent }
            .map(userContentPackageName(for:))
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { result.append(value) }
            }
    }

    func userContentPackageName(for mod: InstalledMod) -> String {
        let components = mod.files.compactMap { $0.relativePath.split(separator: "/").first.map(String.init) }
        guard let first = components.first,
              components.allSatisfy({ $0.caseInsensitiveCompare(first) == .orderedSame }),
              URL(fileURLWithPath: first).pathExtension.isEmpty,
              !["CookedPC", "UserContent"].contains(where: { $0.caseInsensitiveCompare(first) == .orderedSame }) else {
            return sanitizedPackageName(mod.name)
        }
        return first
    }

    func sanitizedPackageName(_ value: String) -> String {
        let sanitized = value.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" { return String(scalar) }
            return "-"
        }.joined().split(separator: "-").joined(separator: "-")
        return sanitized.isEmpty ? "boreal-mod" : sanitized
    }

    func destinationURL(for path: String, gameRoot: URL?, userRoot: URL?) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let lower = normalized.lowercased()
        if contract == .witcher3 {
            if lower == Self.witcher3SettingsPath.lowercased() {
                return userRoot?.appending(path: "mods.settings")
            }
            if lower.hasPrefix("userdata/") {
                guard let userRoot else { return nil }
                return safelyAppend(String(normalized.dropFirst("UserData/".count)), to: userRoot)
            }
            guard let gameRoot else { return nil }
            return safelyAppend(normalized, to: gameRoot)
        }
        if lower.hasPrefix("cookedpc/") {
            guard let gameRoot else { return nil }
            return Witcher2Adapter.append(String(normalized.dropFirst("CookedPC/".count)), to: Witcher2Adapter.cookedPCRoot(in: gameRoot))
        }
        if lower.hasPrefix("usercontent/") {
            guard let userRoot else { return nil }
            return Witcher2Adapter.append(String(normalized.dropFirst("UserContent/".count)), to: userRoot.appending(path: "UserContent", directoryHint: .isDirectory))
        }
        if lower == Self.userConfigPath.lowercased() {
            return userRoot?.appending(path: "Config/UserContent.ini")
        }
        return nil
    }

    func safelyAppend(_ relativePath: String, to root: URL) -> URL? {
        guard isSafeRelativePath(relativePath) else { return nil }
        let components = relativePath.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }
        let normalizedRoot = root.standardizedFileURL
        let destination = append(relativePath, to: normalizedRoot).standardizedFileURL
        guard destination.path.hasPrefix(normalizedRoot.path.hasSuffix("/") ? normalizedRoot.path : normalizedRoot.path + "/") else {
            return nil
        }

        var parent = normalizedRoot
        for component in components.dropLast() {
            parent.append(path: component, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: parent.path) else { continue }
            guard let values = try? parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { return nil }
        }
        return destination
    }

    func validateManagedFiles(_ files: [String: ModDeploymentFile], gameRoot: URL?, userRoot: URL?) throws {
        for path in files.values.map(\.path) {
            guard isSafeRelativePath(path), let destination = destinationURL(for: path, gameRoot: gameRoot, userRoot: userRoot) else {
                throw ModManagerError.invalidRelativePath(path)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The managed \(adapter.displayName) destination is unsafe: \(path)")
                }
            }
        }
    }

    func preflightExternalChanges(_ files: [String: ModDeploymentFile], gameRoot: URL?, userRoot: URL?) throws {
        for entry in files.values {
            guard let destination = destinationURL(for: entry.path, gameRoot: gameRoot, userRoot: userRoot),
                  FileManager.default.fileExists(atPath: destination.path) else { continue }
            guard try RuntimeSecurity.sha256(of: destination) == entry.sha256 else {
                throw ModManagerError.externalFileChanged(entry.path)
            }
        }
    }

    func prepareBackup(destination: URL, gameDirectory: URL, path: String, oldFile: ModDeploymentFile?) throws -> BackupInfo {
        if let oldFile { return BackupInfo(path: oldFile.backup, originalHash: oldFile.originalHash) }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path) else { return BackupInfo(path: nil, originalHash: nil) }
        let hash = try RuntimeSecurity.sha256(of: destination)
        let backupRelative = "Backups/\(UUID().uuidString)-\(path.replacingOccurrences(of: "/", with: "_"))"
        let backup = append(backupRelative, to: gameDirectory)
        try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: destination, to: backup)
        return BackupInfo(path: backupRelative, originalHash: hash)
    }

    func replace(source: URL, destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }

    func makeUserContentINI(at url: URL, removing oldPackages: Set<String>, adding packages: [String]) throws -> String {
        let original = String(data: (try? Data(contentsOf: url)) ?? Data(), encoding: .utf8) ?? ""
        var lines = original.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let sectionHeader = "[Packages]"
        let start = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(sectionHeader) == .orderedSame }
        let end = start.map { index in
            lines[(index + 1)...].firstIndex {
                let value = $0.trimmingCharacters(in: .whitespaces)
                return value.hasPrefix("[") && value.hasSuffix("]")
            } ?? lines.endIndex
        }
        let removeSet = oldPackages.union(packages).map { $0.lowercased() }
        let mountLine: (String) -> String? = { line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Mount") == .orderedSame else { return nil }
            return parts[1].trimmingCharacters(in: .whitespaces).lowercased()
        }
        if let start, let end {
            let sectionLines = lines[(start + 1)..<end]
            lines.removeSubrange((start + 1)..<end)
            let kept = sectionLines.filter { line in
                guard let mount = mountLine(line) else { return true }
                return !removeSet.contains(mount)
            }
            lines.insert(contentsOf: kept + packages.map { "Mount=\($0)" }, at: start + 1)
        } else {
            if !lines.isEmpty { lines.append("") }
            lines.append(sectionHeader)
            lines.append(contentsOf: packages.map { "Mount=\($0)" })
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func isModStorageReferenced(_ mod: InstalledMod, gameID: UUID, excludingProfileID: String) -> Bool {
        for profile in profiles(for: gameID) where profile.id.caseInsensitiveCompare(excludingProfileID) != .orderedSame {
            guard let stored = try? read(ModProfile.self, at: profileURL(for: gameID, profileID: profile.id)) else { return true }
            if stored.mods.contains(where: {
                $0.id == mod.id || $0.stagingRelativePath == mod.stagingRelativePath || $0.archiveRelativePath == mod.archiveRelativePath
            }) { return true }
        }
        return false
    }

    func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        return !components.isEmpty
            && !components.contains("..")
            && !components.contains(".")
            && !components.contains(where: { $0.contains(":" ) })
    }

    func append(_ relativePath: String, to root: URL) -> URL {
        Witcher2Adapter.append(relativePath, to: root)
    }

    func gameURL(for gameID: UUID) -> URL { rootURL.appending(path: gameID.uuidString, directoryHint: .isDirectory) }

    func profileURL(for gameID: UUID, profileID: String) -> URL {
        gameURL(for: gameID).appending(path: "profiles/\(normalizedProfileID(profileID)).json")
    }

    func activeProfileURL(for gameID: UUID) -> URL { gameURL(for: gameID).appending(path: "active-profile.txt") }

    func activeProfileID(for gameID: UUID) -> String {
        guard let data = try? Data(contentsOf: activeProfileURL(for: gameID)),
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return "default" }
        return normalizedProfileID(value)
    }

    func normalizedProfileID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("default") == .orderedSame { return "default" }
        let normalized = trimmed.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? String(scalar) : "-"
        }.joined().split(separator: "-").joined(separator: "-").lowercased()
        return normalized.isEmpty ? "profile-\(UUID().uuidString.prefix(8).lowercased())" : normalized
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
