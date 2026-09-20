import Foundation

nonisolated protocol GameModManaging: Sendable {
    var adapter: ModGameAdapter { get }

    func inspect(archive: URL, gameID: UUID) throws -> ModInstallPreview
    func discardPreview(_ preview: ModInstallPreview)
    func load(gameID: UUID, gameRoot: URL?, pluginsFile: URL?, profileID: String?) throws -> ModGameState
    func install(preview: ModInstallPreview, gameRoot: URL?, pluginsFile: URL?, profileID: String) throws -> ModGameState
    func saveProfile(gameID: UUID, profileID: String, profileName: String, mods: [InstalledMod], plugins: [BethesdaPlugin]) throws
    func deploy(state: ModGameState, gameRoot: URL?, pluginsFile: URL?) throws -> ModGameState
    func profiles(for gameID: UUID) -> [ModProfileDescriptor]
    func createProfile(name: String, from state: ModGameState) throws -> ModGameState
    func removeMod(_ modID: UUID, from state: ModGameState) throws -> ModGameState
    func stagedModURL(gameID: UUID, modID: UUID) -> URL?
    func activateProfile(_ profileID: String, for gameID: UUID) throws
    func deploymentHealth(for state: ModGameState, gameRoot: URL?, pluginsFile: URL?) -> ModDeploymentHealth
    func repairRuntime(gameRoot: URL?) throws -> ModRuntimeState?
    func launchArguments(for gameRoot: URL?) -> [String]
}

extension ModManager: GameModManaging {
    var adapter: ModGameAdapter { .skyrimSpecialEdition }

    func repairRuntime(gameRoot: URL?) throws -> ModRuntimeState? { nil }

    func launchArguments(for gameRoot: URL?) -> [String] { [] }
}

// MARK: - GTA San Andreas adapter

nonisolated enum GTASAModLoaderAdapter {
    static let adapter: ModGameAdapter = .gtaSanAndreas
    static let knownRootFiles: Set<String> = [
        "gta_sa.exe", "gta-sa.exe", "gta_sa_enhanced.exe"
    ]
    static let rootOverlayFiles: Set<String> = [
        "dinput8.dll", "dsound.dll", "version.dll", "winmm.dll", "vorbisfile.dll",
        "modloader.asi", "cleo.asi", "bass.dll", "vorbis.dll"
    ]
    static let mergeableExtensions: Set<String> = ["dat", "ide", "ipl", "cfg"]
    static let manualExtensions: Set<String> = ["exe", "msi", "bat", "cmd", "ps1"]

    static func isDefinitiveEdition(game: StoreLibraryGame) -> Bool {
        let name = game.name.lowercased()
        return game.externalID == GameLaunchCompatibility.gtaSanAndreasDefinitiveEditionSteamAppID
            || (name.contains("san andreas") && name.contains("definitive edition"))
    }

    static func supports(game: StoreLibraryGame) -> Bool {
        let name = game.name.lowercased()
        if isDefinitiveEdition(game: game) {
            return false
        }
        let isSanAndreas = name.contains("san andreas")
            && (name.contains("grand theft auto") || name.contains("gta"))
        return isSanAndreas || ["12120", "gta-san-andreas"].contains(game.externalID.lowercased())
    }

    static func gameRoot(
        installationRoot: URL?,
        executable: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let executable {
            let normalized = executable.standardizedFileURL
            if normalized.pathExtension.lowercased() == "exe" {
                candidates.append(normalized.deletingLastPathComponent())
            }
            var current = normalized.deletingLastPathComponent()
            for _ in 0..<5 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }
        if let installationRoot {
            let normalized = installationRoot.standardizedFileURL
            candidates.append(normalized.pathExtension.lowercased() == "exe" ? normalized.deletingLastPathComponent() : normalized)
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            if knownRootFiles.contains(where: { fileManager.fileExists(atPath: candidate.appending(path: $0).path) }) {
                return candidate
            }
        }
        return nil
    }

    static func runtimeState(in gameRoot: URL?, fileManager: FileManager = .default) -> ModRuntimeState {
        guard let gameRoot else {
            return ModRuntimeState(
                adapter: adapter,
                executablePath: nil,
                executableVersion: nil,
                executableHash: nil,
                asiLoaderInstalled: false,
                modLoaderInstalled: false,
                cleoInstalled: false,
                compatibility: .unsupportedExecutable
            )
        }

        let executable = knownRootFiles
            .map { gameRoot.appending(path: $0) }
            .first { fileManager.isReadableFile(atPath: $0.path) }
        let modloaderDirectory = gameRoot.appending(path: "modloader", directoryHint: .isDirectory)
        let modloaderASI = gameRoot.appending(path: "modloader.asi")
        let modLoaderInstalled = fileManager.isReadableFile(atPath: modloaderASI.path)
            && isDirectory(modloaderDirectory, fileManager: fileManager)
        let asiLoaderInstalled = rootOverlayFiles
            .subtracting(["modloader.asi", "cleo.asi"])
            .contains { fileManager.isReadableFile(atPath: gameRoot.appending(path: $0).path) }
        let cleoInstalled = isDirectory(gameRoot.appending(path: "CLEO", directoryHint: .isDirectory), fileManager: fileManager)
            || fileManager.isReadableFile(atPath: gameRoot.appending(path: "cleo.asi").path)
        let compatibility: ModRuntimeCompatibility
        if executable == nil {
            compatibility = .unsupportedExecutable
        } else if !modLoaderInstalled || !asiLoaderInstalled {
            compatibility = .missingComponents
        } else {
            // Boreal does not invent a version from a filename. A release can
            // become fully ready after a verified hash/version catalog is
            // supplied; until then the warning is explicit.
            compatibility = .unknownExecutableVersion
        }
        return ModRuntimeState(
            adapter: adapter,
            executablePath: executable?.path,
            executableVersion: nil,
            executableHash: executable.flatMap { try? RuntimeSecurity.sha256(of: $0) },
            asiLoaderInstalled: asiLoaderInstalled,
            modLoaderInstalled: modLoaderInstalled,
            cleoInstalled: cleoInstalled,
            compatibility: compatibility
        )
    }

    static func prepareManagedLayout(in gameRoot: URL, fileManager: FileManager = .default) throws {
        for path in [
            "modloader",
            "modloader/.data",
            "modloader/.profiles",
            "modloader/Boreal",
            "CLEO",
            "scripts"
        ] {
            let url = append(path, to: gameRoot)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func isDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func append(_ relativePath: String, to root: URL) -> URL {
        relativePath.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }
    }

    static func classify(files: [URL]) -> (ModContentType, ModDeployStrategy, [String], [String], Bool) {
        let names = files.map { $0.lastPathComponent.lowercased() }
        let extensions = Set(files.map { $0.pathExtension.lowercased() })
        let hasManualInstaller = extensions.contains(where: manualExtensions.contains)
        if hasManualInstaller {
            return (
                .manual,
                .manual,
                [],
                ["Manual installer detected. Automatic installation is unavailable for this archive."],
                false
            )
        }

        let hasCore = names.contains(where: rootOverlayFiles.contains)
        let hasRootOverlay = hasCore || names.contains(where: { $0 == "gta_sa.exe" || $0 == "gta-sa.exe" })
        let hasASI = extensions.contains("asi")
        let hasCLEO = extensions.contains("cs") || extensions.contains("cleo")
        let requirements: [String] = {
            var result: [String] = []
            if hasASI || hasRootOverlay { result.append("ASI Loader") }
            if hasCLEO { result.append("CLEO") }
            if !hasRootOverlay { result.append("GTA SA Mod Loader") }
            return result
        }()

        if hasCore || hasRootOverlay {
            return (
                .coreComponent,
                .rootOverlay,
                requirements,
                ["Files will be deployed next to gta_sa.exe and protected with a Boreal backup."],
                true
            )
        }
        if hasASI {
            return (.asiPlugin, .modLoader, requirements, [], true)
        }
        if hasCLEO {
            return (.cleo, .cleo, requirements, [], true)
        }
        if !extensions.isEmpty && extensions.allSatisfy({ ["ini", "cfg", "txt"].contains($0) }) {
            return (.config, .modLoader, requirements, [], true)
        }
        return (.modLoader, .modLoader, requirements, [], true)
    }

    static func conflictKind(for path: String) -> ModConflictKind {
        let lowercased = path.lowercased()
        if [".asi", ".dll", ".exe"].contains(where: { lowercased.hasSuffix($0) }) {
            return .potentialRuntime
        }
        if mergeableExtensions.contains(URL(fileURLWithPath: lowercased).pathExtension) {
            return .mergeable
        }
        return .directReplacement
    }
}

// MARK: - GTA San Andreas manager

nonisolated struct GTASAModManager: GameModManaging, Sendable {
    let rootURL: URL
    let adapter: ModGameAdapter = .gtaSanAndreas

    init(applicationSupportURL: URL) {
        rootURL = applicationSupportURL.appending(path: "Mods/gta-sa", directoryHint: .isDirectory)
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
            let payloadRoot = try findPayloadRoot(in: extracted)
            let files = try contentFiles(in: payloadRoot)
            guard !files.isEmpty else { throw ModManagerError.extractedArchiveEmpty }
            let (type, strategy, requirements, warnings, canInstall) = GTASAModLoaderAdapter.classify(files: files)
            let current = try load(gameID: gameID, gameRoot: nil, pluginsFile: nil, profileID: nil)
            return ModInstallPreview(
                gameID: gameID,
                archiveURL: pendingURL,
                archiveName: archive.lastPathComponent,
                format: format,
                detectedRoot: relativeDisplayPath(payloadRoot, from: extracted),
                fileCount: files.count,
                pluginCount: files.filter { ["asi", "cleo", "cs"].contains($0.pathExtension.lowercased()) }.count,
                adapter: adapter,
                contentType: type,
                deployStrategy: strategy,
                requirements: requirements,
                warnings: warnings,
                canInstallAutomatically: canInstall,
                totalSize: files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) },
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
        let deployment = (try? read(ModDeploymentManifest.self, at: gameDirectory.appending(path: "deployment.json"))) ?? .empty(gameID: gameID)
        let storedMods = profile?.mods ?? scanManifests(in: gameDirectory)
        let discoveredMods = scanExternalMods(in: gameRoot, deployment: deployment)
        var mods = ExternalModDiscovery.merge(managed: storedMods, discovered: discoveredMods)
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
            runtime: GTASAModLoaderAdapter.runtimeState(in: gameRoot)
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
            throw ModManagerError.deploymentFailed("This archive contains a manual installer and must be installed outside Boreal.")
        }
        let fileManager = FileManager.default
        let extracted = try extract(preview.archiveURL, format: try archiveFormat(for: preview.archiveURL))
        defer { try? fileManager.removeItem(at: extracted) }
        let payloadRoot = try findPayloadRoot(in: extracted)
        let sourceFiles = try contentFiles(in: payloadRoot)
        guard !sourceFiles.isEmpty else { throw ModManagerError.extractedArchiveEmpty }

        let current = try load(gameID: preview.gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: profileID)
        let replacement = preview.existingModID.flatMap { modID in
            current.mods.first { $0.id == modID }
        }
        let gameDirectory = gameURL(for: preview.gameID)
        let stagingID = UUID()
        let stagingDirectory = gameDirectory.appending(path: "Staging/\(stagingID.uuidString)/files", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        do {
            var files: [ModFile] = []
            var seen = Set<String>()
            for source in sourceFiles {
                let relative = try relativePath(of: source, from: payloadRoot)
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

            let archiveDirectory = gameDirectory.appending(path: "Archives", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let archiveName = "\(stagingID.uuidString)-\(preview.archiveName)"
            let archiveDestination = archiveDirectory.appending(path: archiveName)
            try fileManager.copyItem(at: preview.archiveURL, to: archiveDestination)
            let mod = InstalledMod(
                id: replacement?.id ?? stagingID,
                name: URL(fileURLWithPath: preview.archiveName).deletingPathExtension().lastPathComponent,
                version: replacement?.version,
                enabled: replacement?.enabled ?? true,
                priority: replacement?.priority ?? current.mods.count,
                archiveRelativePath: "Archives/\(archiveName)",
                stagingRelativePath: "Staging/\(stagingID.uuidString)",
                files: files,
                plugins: [],
                contentType: preview.contentType,
                deployStrategy: preview.deployStrategy,
                requirements: preview.requirements,
                warnings: preview.warnings
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
        let profile = ModProfile(
            gameID: gameID,
            name: profileName,
            mods: normalizedMods,
            plugins: [],
            updatedAt: .now
        )
        try saveJSON(profile, at: profileURL(for: gameID, profileID: profileID))
        for mod in normalizedMods where !mod.isExternallyDetected {
            try saveJSON(mod, at: append("\(mod.stagingRelativePath)/manifest.json", to: gameDirectory))
        }
    }

    func deploy(state: ModGameState, gameRoot: URL?, pluginsFile: URL?) throws -> ModGameState {
        guard let gameRoot else { throw ModManagerError.gameRootUnavailable }
        try GTASAModLoaderAdapter.prepareManagedLayout(in: gameRoot)
        let fileManager = FileManager.default
        let gameDirectory = gameURL(for: state.gameID)
        let deploymentURL = gameDirectory.appending(path: "deployment.json")
        let old = (try? read(ModDeploymentManifest.self, at: deploymentURL)) ?? .empty(gameID: state.gameID)
        let generatedProfile = profileText(for: state)
        let generatedHash = try RuntimeSecurity.sha256(data: Data(generatedProfile.utf8))
        var resolved = try resolvedFiles(for: state.mods, gameDirectory: gameDirectory)
        resolved[Self.profilePath] = ResolvedFile(
            path: Self.profilePath,
            owner: Self.generatedOwner,
            source: nil,
            content: Data(generatedProfile.utf8),
            sha256: generatedHash
        )

        try validateManagedFiles(old.files, gameRoot: gameRoot)
        try preflightExternalChanges(old.files, gameRoot: gameRoot)
        let transactionURL = gameDirectory.appending(path: ".transactions/\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: transactionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transactionURL) }

        let changedPaths = Set(old.files.values.map(\.path)).union(resolved.keys)
        var transactionOriginals: [String: URL] = [:]
        var transactionMissingPaths = Set<String>()
        do {
            for path in changedPaths {
                let destination = GTASAModLoaderAdapter.append(path, to: gameRoot)
                guard fileManager.fileExists(atPath: destination.path) else {
                    transactionMissingPaths.insert(path)
                    continue
                }
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The GTA SA destination is not a regular file: \(path)")
                }
                let backup = GTASAModLoaderAdapter.append(path, to: transactionURL)
                try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: destination, to: backup)
                transactionOriginals[path] = backup
            }

            var nextFiles: [String: ModDeploymentFile] = [:]
            for (key, resolvedFile) in resolved {
                let destination = GTASAModLoaderAdapter.append(resolvedFile.path, to: gameRoot)
                let source: URL
                if let stagedSource = resolvedFile.source {
                    source = GTASAModLoaderAdapter.append(stagedSource, to: gameDirectory)
                    guard try RuntimeSecurity.sha256(of: source) == resolvedFile.sha256 else {
                        throw ModManagerError.stagedFileChanged(resolvedFile.path)
                    }
                } else {
                    source = transactionURL.appending(path: "generated/Boreal.ini")
                    try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try resolvedFile.content?.write(to: source, options: .atomic)
                }
                let oldFile = old.files.values.first { $0.path.caseInsensitiveCompare(resolvedFile.path) == .orderedSame }
                let backup = try prepareBackup(
                    destination: destination,
                    gameDirectory: gameDirectory,
                    path: resolvedFile.path,
                    oldFile: oldFile
                )
                try replace(source: source, destination: destination)
                nextFiles[key] = ModDeploymentFile(
                    path: resolvedFile.path,
                    owner: resolvedFile.owner,
                    sha256: resolvedFile.sha256,
                    source: resolvedFile.source ?? "generated/Boreal.ini",
                    backup: backup.path,
                    originalHash: backup.originalHash
                )
            }

            for oldFile in old.files.values where resolved[oldFile.path.lowercased()] == nil {
                let destination = GTASAModLoaderAdapter.append(oldFile.path, to: gameRoot)
                guard fileManager.fileExists(atPath: destination.path) else { continue }
                if let backup = oldFile.backup {
                    let backupURL = GTASAModLoaderAdapter.append(backup, to: gameDirectory)
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
                profileFingerprint: ModProfileFingerprint.make(mods: state.mods, plugins: []),
                files: nextFiles,
                pluginFilePath: nil,
                pluginFileHash: nil,
                pluginFileBackup: nil,
                pluginFileOriginalHash: nil
            )
            try saveJSON(next, at: deploymentURL)
            try saveProfile(
                gameID: state.gameID,
                profileID: state.profileID,
                profileName: state.profileName,
                mods: state.mods,
                plugins: []
            )
            return try load(gameID: state.gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: state.profileID)
        } catch {
            for (path, original) in transactionOriginals {
                let destination = GTASAModLoaderAdapter.append(path, to: gameRoot)
                try? fileManager.removeItem(at: destination)
                try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: original, to: destination)
            }
            for path in transactionMissingPaths {
                try? fileManager.removeItem(at: GTASAModLoaderAdapter.append(path, to: gameRoot))
            }
            throw error
        }
    }

    func profiles(for gameID: UUID) -> [ModProfileDescriptor] {
        let directory = gameURL(for: gameID).appending(path: "profiles", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
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
        guard !trimmed.isEmpty, trimmed.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
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
            let archiveURL = append(archive, to: gameDirectory)
            if fileManager.fileExists(atPath: archiveURL.path) { try fileManager.removeItem(at: archiveURL) }
        }
        let stagingURL = append(mod.stagingRelativePath, to: gameDirectory)
        if fileManager.fileExists(atPath: stagingURL.path) { try fileManager.removeItem(at: stagingURL) }
        var next = state
        next.mods.removeAll { $0.id == modID }
        try saveProfile(gameID: state.gameID, profileID: state.profileID, profileName: state.profileName, mods: next.mods, plugins: [])
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

    func deploymentHealth(for state: ModGameState, gameRoot: URL?, pluginsFile: URL?) -> ModDeploymentHealth {
        var externalChanges: [String] = []
        let fileManager = FileManager.default
        if let gameRoot {
            for entry in state.deployment.files.values {
                let destination = GTASAModLoaderAdapter.append(entry.path, to: gameRoot)
                guard fileManager.fileExists(atPath: destination.path),
                      (try? RuntimeSecurity.sha256(of: destination)) == entry.sha256 else {
                    externalChanges.append(entry.path)
                    continue
                }
            }
        } else if !state.deployment.files.isEmpty {
            externalChanges.append("game root")
        }
        let vanillaFilesProtected = state.deployment.deployedAt == nil || state.deployment.files.values.allSatisfy { entry in
            guard entry.originalHash != nil else { return true }
            guard let backup = entry.backup else { return false }
            return fileManager.fileExists(atPath: GTASAModLoaderAdapter.append(backup, to: gameURL(for: state.gameID)).path)
        }
        let deployedOwners = Set(state.deployment.files.values.map(\.owner)).subtracting([Self.generatedOwner])
        return ModDeploymentHealth(
            deployedModCount: deployedOwners.count,
            managedFileCount: state.deployment.files.count,
            pluginsSynchronized: true,
            vanillaFilesProtected: vanillaFilesProtected,
            externalChanges: Array(Set(externalChanges)).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            validation: state.validation,
            pendingChanges: state.pendingChanges,
            lastDeployment: state.deployment.deployedAt
        )
    }

    func repairRuntime(gameRoot: URL?) throws -> ModRuntimeState? {
        guard let gameRoot else { throw ModManagerError.gameRootUnavailable }
        try GTASAModLoaderAdapter.prepareManagedLayout(in: gameRoot)
        return GTASAModLoaderAdapter.runtimeState(in: gameRoot)
    }

    func launchArguments(for gameRoot: URL?) -> [String] {
        ["-modprof", "Boreal"]
    }
}

extension GTASAModManager {
    static let profilePath = "modloader/.profiles/Boreal.ini"
    static let generatedOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    struct ResolvedFile {
        let path: String
        let owner: UUID
        let source: String?
        let content: Data?
        let sha256: String
    }

    struct BackupInfo {
        let path: String?
        let originalHash: String?
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

    func archiveFormat(for archive: URL) throws -> ModArchiveFormat {
        guard FileManager.default.isReadableFile(atPath: archive.path),
              let format = ModArchiveFormat(fileExtension: archive.pathExtension) else {
            throw ModManagerError.unsupportedArchive(archive)
        }
        return format
    }

    func append(_ relativePath: String, to root: URL) -> URL {
        GTASAModLoaderAdapter.append(relativePath, to: root)
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

    func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        return !components.isEmpty && !components.contains("..") && !components.contains(where: { $0.contains(":") })
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

    func findPayloadRoot(in extracted: URL) throws -> URL {
        var current = extracted
        while true {
            let children = try FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles])
            let files = children.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                    && $0.lastPathComponent != ".DS_Store"
                    && !$0.pathComponents.contains("__MACOSX")
            }
            let directories = children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            if !files.isEmpty { return current }
            guard directories.count == 1, let child = directories.first else { return current }
            let name = child.lastPathComponent.lowercased()
            current = child
            if ["modloader", "cleo", "scripts"].contains(name) { return current }
        }
    }

    func extract(_ archive: URL, format: ModArchiveFormat) throws -> URL {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appending(path: "boreal-gta-mod-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            case .loosePak:
                throw ModManagerError.archiveToolUnavailable(format)
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
        case .loosePak:
            throw ModManagerError.archiveToolUnavailable(format)
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

    func scanManifests(in gameDirectory: URL) -> [InstalledMod] {
        let staging = gameDirectory.appending(path: "Staging", directoryHint: .isDirectory)
        guard let children = try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { try? read(InstalledMod.self, at: $0.appending(path: "manifest.json")) }.sorted { $0.priority < $1.priority }
    }

    private func scanExternalMods(in gameRoot: URL?, deployment: ModDeploymentManifest) -> [InstalledMod] {
        guard let gameRoot else { return [] }
        let fileManager = FileManager.default
        let managedPaths = Set(deployment.files.values.map { $0.path.lowercased() })
        let modloaderRoot = gameRoot.appending(path: "modloader", directoryHint: .isDirectory)
        var result: [InstalledMod] = []

        if let children = try? fileManager.contentsOfDirectory(
            at: modloaderRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let lowercased = child.lastPathComponent.lowercased()
                guard ![".data", ".profiles", "boreal"].contains(lowercased),
                      let files = try? contentFiles(in: child) else { continue }
                let classified = GTASAModLoaderAdapter.classify(files: files)
                if let mod = ExternalModDiscovery.makeMod(
                    adapter: adapter,
                    name: child.lastPathComponent,
                    detectionKey: "modloader/\(child.lastPathComponent)",
                    files: files,
                    relativeTo: child,
                    contentType: classified.0,
                    requirements: classified.2
                ) {
                    result.append(mod)
                }
            }
        }

        var rootFiles: [URL] = []
        if let children = try? fileManager.contentsOfDirectory(
            at: gameRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                if (try? child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    let extensionName = child.pathExtension.lowercased()
                    guard ["asi", "cs", "cleo"].contains(extensionName),
                          !GTASAModLoaderAdapter.rootOverlayFiles.contains(child.lastPathComponent.lowercased()),
                          !managedPaths.contains(child.lastPathComponent.lowercased()) else { continue }
                    rootFiles.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          ["scripts", "cleo"].contains(child.lastPathComponent.lowercased()),
                          let files = try? contentFiles(in: child) {
                    rootFiles.append(contentsOf: files)
                }
            }
        }
        rootFiles = rootFiles.filter {
            ExternalModDiscovery.relativePath(of: $0, from: gameRoot).map { !managedPaths.contains($0.lowercased()) } ?? false
        }
        if !rootFiles.isEmpty {
            let classified = GTASAModLoaderAdapter.classify(files: rootFiles)
            if let mod = ExternalModDiscovery.makeMod(
                adapter: adapter,
                name: "External GTA San Andreas files",
                detectionKey: "root-overlay",
                files: rootFiles,
                relativeTo: gameRoot,
                contentType: classified.0,
                requirements: classified.2
            ) {
                result.append(mod)
            }
        }
        return result
    }

    func resolvedFiles(for mods: [InstalledMod], gameDirectory: URL) throws -> [String: ResolvedFile] {
        var result: [String: ResolvedFile] = [:]
        for mod in mods.sorted(by: { $0.priority < $1.priority }) where mod.enabled {
            guard mod.deployStrategy != .manual else { continue }
            for file in mod.files {
                guard isSafeRelativePath(file.relativePath) else { throw ModManagerError.invalidRelativePath(file.relativePath) }
                let target: String
                switch mod.deployStrategy {
                case .rootOverlay:
                    target = file.relativePath
                case .modLoader, .scripts, .cleo, .manual, .dragonAgeOverride, .dragonAgeDazip:
                    target = "modloader/Boreal/\(modDirectoryName(for: mod))/\(file.relativePath)"
                case .unrealPaks:
                    continue
                }
                result[target.lowercased()] = ResolvedFile(
                    path: target,
                    owner: mod.id,
                    source: "\(mod.stagingRelativePath)/files/\(file.relativePath)",
                    content: nil,
                    sha256: file.sha256
                )
            }
        }
        return result
    }

    func modDirectoryName(for mod: InstalledMod) -> String {
        let sanitized = mod.name.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" { return String(scalar) }
            return "-"
        }.joined().split(separator: "-").joined(separator: "-").lowercased()
        let name = sanitized.isEmpty ? "mod" : sanitized
        return "\(name)-\(mod.id.uuidString.prefix(8).lowercased())"
    }

    func profileText(for state: ModGameState) -> String {
        var lines = [
            "; Generated by Boreal. The Boreal profile is the source of truth.",
            "[Profiles.Boreal.Config]",
            "Parents = $None",
            "ExcludeAllMods = true",
            "",
            "[Profiles.Boreal.IncludeMods]"
        ]
        let enabled = state.mods.filter { $0.enabled && $0.deployStrategy != .manual }
        for mod in enabled.sorted(by: { $0.priority < $1.priority }) {
            lines.append("Boreal/\(modDirectoryName(for: mod)) = true")
        }
        lines.append("")
        lines.append("[Profiles.Boreal.Priority]")
        for mod in enabled.sorted(by: { $0.priority < $1.priority }) {
            let priority = min(100, max(1, mod.priority + 1))
            lines.append("Boreal/\(modDirectoryName(for: mod)) = \(priority)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func validateManagedFiles(_ files: [String: ModDeploymentFile], gameRoot: URL) throws {
        for path in files.values.map(\.path) {
            guard isSafeRelativePath(path) else { throw ModManagerError.invalidRelativePath(path) }
            let destination = GTASAModLoaderAdapter.append(path, to: gameRoot)
            if FileManager.default.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The managed GTA SA destination is unsafe: \(path)")
                }
            }
        }
    }

    func preflightExternalChanges(_ files: [String: ModDeploymentFile], gameRoot: URL) throws {
        for entry in files.values {
            let destination = GTASAModLoaderAdapter.append(entry.path, to: gameRoot)
            guard FileManager.default.fileExists(atPath: destination.path) else { continue }
            guard try RuntimeSecurity.sha256(of: destination) == entry.sha256 else {
                throw ModManagerError.externalFileChanged(entry.path)
            }
        }
    }

    func prepareBackup(destination: URL, gameDirectory: URL, path: String, oldFile: ModDeploymentFile?) throws -> BackupInfo {
        let fileManager = FileManager.default
        if let oldFile { return BackupInfo(path: oldFile.backup, originalHash: oldFile.originalHash) }
        guard fileManager.fileExists(atPath: destination.path) else { return BackupInfo(path: nil, originalHash: nil) }
        let originalHash = try RuntimeSecurity.sha256(of: destination)
        let backupRelative = "Backups/\(UUID().uuidString)-\(path.replacingOccurrences(of: "/", with: "_"))"
        let backup = GTASAModLoaderAdapter.append(backupRelative, to: gameDirectory)
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

    func isModStorageReferenced(
        _ mod: InstalledMod,
        gameID: UUID,
        excludingProfileID: String
    ) -> Bool {
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
