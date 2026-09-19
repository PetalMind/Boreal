import Foundation

// MARK: - GTA San Andreas — The Definitive Edition

/// The Definitive Edition is an Unreal Engine game. This adapter manages
/// Unreal PAK mods and CLEO Redux scripts supported by the installed runtime.
nonisolated enum GTASADefinitiveEditionAdapter {
    static let adapter: ModGameAdapter = .gtaSanAndreasDefinitiveEdition

    static func supports(game: StoreLibraryGame) -> Bool {
        GTASAModLoaderAdapter.isDefinitiveEdition(game: game)
    }

    static func gameRoot(
        installationRoot: URL?,
        executable: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let executable {
            var current = executable.standardizedFileURL.deletingLastPathComponent()
            for _ in 0..<8 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }
        if let installationRoot {
            var current = installationRoot.standardizedFileURL
            if current.pathExtension.caseInsensitiveCompare("exe") == .orderedSame {
                current.deleteLastPathComponent()
            }
            for _ in 0..<4 {
                candidates.append(current)
                current.deleteLastPathComponent()
            }
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            let paks = paksRoot(in: candidate)
            let executable = candidate.appending(path: "Gameface/Binaries/Win64/SanAndreas.exe")
            if fileManager.isReadableFile(atPath: executable.path)
                || isDirectory(paks, fileManager: fileManager) {
                return candidate
            }
        }
        return nil
    }

    static func paksRoot(in gameRoot: URL) -> URL {
        gameRoot.appending(path: "Gameface/Content/Paks", directoryHint: .isDirectory)
    }

    static func managedPaksRoot(in gameRoot: URL) -> URL {
        paksRoot(in: gameRoot).appending(path: "~mods", directoryHint: .isDirectory)
    }

    static func destinationPath(for relativePath: String) -> String {
        "Gameface/Content/Paks/~mods/\(relativePath)"
    }

    static func cleoDestinationPath(for filename: String) -> String {
        let destinationName: String
        if filename.lowercased().hasSuffix(".js"), !filename.lowercased().hasSuffix("[fs].js") {
            destinationName = String(filename.dropLast(3)) + "[fs].js"
        } else {
            destinationName = filename
        }
        return "Gameface/Binaries/Win64/CLEO/\(destinationName)"
    }

    static func isDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

nonisolated struct GTASADefinitiveEditionModManager: GameModManaging, Sendable {
    let rootURL: URL
    private let archiveSupport: GTASAModManager

    init(applicationSupportURL: URL) {
        rootURL = applicationSupportURL.appending(path: "Mods/gta-sa-definitive", directoryHint: .isDirectory)
        archiveSupport = GTASAModManager(applicationSupportURL: applicationSupportURL)
    }

    var adapter: ModGameAdapter { .gtaSanAndreasDefinitiveEdition }

    func inspect(archive: URL, gameID: UUID) throws -> ModInstallPreview {
        let format = try archiveSupport.archiveFormat(for: archive)
        let pendingRoot = gameURL(for: gameID).appending(path: "Archives/.pending", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        let pendingURL = pendingRoot.appending(path: UUID().uuidString + "-" + archive.lastPathComponent)
        try FileManager.default.copyItem(at: archive, to: pendingURL)

        do {
            let extracted = try archiveSupport.extract(pendingURL, format: format)
            defer { try? FileManager.default.removeItem(at: extracted) }
            let files = try archiveSupport.contentFiles(in: extracted)
            let pakFiles = files.filter { $0.pathExtension.caseInsensitiveCompare("pak") == .orderedSame }
            let cleoFiles = files.filter { isCleoFile($0) }
            let useCleo = pakFiles.isEmpty && cleoFiles.contains {
                $0.pathExtension.caseInsensitiveCompare("js") == .orderedSame
            }
            guard !pakFiles.isEmpty || useCleo else {
                throw ModManagerError.deploymentFailed(
                    "The archive must contain an Unreal Engine .pak file or a CLEO Redux .js script."
                )
            }
            let selectedFiles = useCleo ? cleoFiles : pakFiles
            let ignoredFiles = files.count - selectedFiles.count
            var warnings = [
                useCleo
                    ? "CLEO Redux JavaScript files will be installed into Gameface/Binaries/Win64/CLEO."
                    : "Unreal Engine .pak files will be installed into Gameface/Content/Paks/~mods."
            ]
            if ignoredFiles > 0 {
                warnings.append("\(ignoredFiles) unrelated file(s) will not be installed.")
            }
            let relativeNames = try selectedFiles.map {
                useCleo
                    ? try cleoRelativePath($0, extracted: extracted)
                    : try pakRelativePath($0, extracted: extracted)
            }
            guard Set(relativeNames.map { $0.lowercased() }).count == relativeNames.count else {
                throw ModManagerError.duplicatePath("Two files have the same destination filename.")
            }
            return ModInstallPreview(
                gameID: gameID,
                archiveURL: pendingURL,
                archiveName: archive.lastPathComponent,
                format: format,
                detectedRoot: useCleo
                    ? "Gameface/Binaries/Win64/CLEO"
                    : "Gameface/Content/Paks/~mods",
                fileCount: selectedFiles.count,
                pluginCount: useCleo
                    ? selectedFiles.filter { $0.pathExtension.caseInsensitiveCompare("js") == .orderedSame }.count
                    : 0,
                adapter: adapter,
                contentType: useCleo ? .cleo : .unrealPak,
                deployStrategy: useCleo ? .cleo : .unrealPaks,
                requirements: useCleo
                    ? ["CLEO Redux x64", "Ultimate ASI Loader x64 as version.dll", "IniFiles64.cleo"]
                    : [],
                warnings: warnings,
                canInstallAutomatically: true,
                totalSize: selectedFiles.reduce(Int64(0)) {
                    $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
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
        var resolvedDeployment = deployment
        let fingerprint = ModProfileFingerprint.make(mods: mods, plugins: [])
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
            throw ModManagerError.deploymentFailed("This archive cannot be installed automatically.")
        }
        let fileManager = FileManager.default
        let extracted = try archiveSupport.extract(preview.archiveURL, format: try archiveSupport.archiveFormat(for: preview.archiveURL))
        defer { try? fileManager.removeItem(at: extracted) }
        let allFiles = try archiveSupport.contentFiles(in: extracted)
        let pakFiles = allFiles.filter { $0.pathExtension.caseInsensitiveCompare("pak") == .orderedSame }
        let cleoFiles = allFiles.filter { isCleoFile($0) }
        let useCleo = preview.contentType == .cleo
        let sourceFiles = useCleo ? cleoFiles : pakFiles
        guard !sourceFiles.isEmpty else {
            throw ModManagerError.deploymentFailed(
                useCleo
                    ? "This archive does not contain CLEO Redux files."
                    : "This archive does not contain an Unreal Engine .pak file."
            )
        }

        let gameDirectory = gameURL(for: preview.gameID)
        let stagingID = UUID()
        let stagingDirectory = gameDirectory.appending(path: "Staging/\(stagingID.uuidString)/files", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        do {
            var files: [ModFile] = []
            var seen = Set<String>()
            for source in sourceFiles {
                let relative = useCleo
                    ? try cleoRelativePath(source, extracted: extracted)
                    : try pakRelativePath(source, extracted: extracted)
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

            let current = try load(gameID: preview.gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: profileID)
            let archiveDirectory = gameDirectory.appending(path: "Archives", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let archiveName = "\(stagingID.uuidString)-\(preview.archiveName)"
            try fileManager.copyItem(at: preview.archiveURL, to: archiveDirectory.appending(path: archiveName))
            let mod = InstalledMod(
                id: stagingID,
                name: URL(fileURLWithPath: preview.archiveName).deletingPathExtension().lastPathComponent,
                priority: current.mods.count,
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
            mods.append(mod)
            try saveProfile(
                gameID: preview.gameID,
                profileID: current.profileID,
                profileName: current.profileName,
                mods: mods,
                plugins: []
            )
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
        guard let gameRoot else { throw ModManagerError.gameRootUnavailable }
        let fileManager = FileManager.default
        let gameDirectory = gameURL(for: state.gameID)
        let deploymentURL = gameDirectory.appending(path: "deployment.json")
        let old = (try? read(ModDeploymentManifest.self, at: deploymentURL)) ?? .empty(gameID: state.gameID)
        let resolved = try resolvedFiles(for: state.mods)
        try validateManagedFiles(old.files, gameRoot: gameRoot)
        let desiredHashes = resolved.values.reduce(into: [String: String]()) { result, resolvedFile in
            result[resolvedFile.destination.lowercased()] = resolvedFile.file.sha256
        }
        try preflightExternalChanges(old.files, desiredHashes: desiredHashes, gameRoot: gameRoot)

        let transactionURL = gameDirectory.appending(path: ".transactions/\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: transactionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transactionURL) }
        let changedPaths = Set(old.files.values.map(\.path)).union(resolved.values.map(\.destination))
        var originals: [String: URL] = [:]
        var missingPaths = Set<String>()
        do {
            for path in changedPaths {
                let destination = append(path, to: gameRoot)
                guard fileManager.fileExists(atPath: destination.path) else {
                    missingPaths.insert(path)
                    continue
                }
                originals[path] = try copyTransactionOriginal(destination, relativePath: path, to: transactionURL)
            }

            var nextFiles: [String: ModDeploymentFile] = [:]
            for resolvedFile in resolved.values {
                let destination = append(resolvedFile.destination, to: gameRoot)
                let source = append(
                    "\(resolvedFile.mod.stagingRelativePath)/files/\(resolvedFile.file.relativePath)",
                    to: gameDirectory
                )
                guard try RuntimeSecurity.sha256(of: source) == resolvedFile.file.sha256 else {
                    throw ModManagerError.stagedFileChanged(resolvedFile.file.relativePath)
                }
                let oldFile = old.files.values.first {
                    $0.path.caseInsensitiveCompare(resolvedFile.destination) == .orderedSame
                }
                let backup = try prepareBackup(
                    destination: destination,
                    gameDirectory: gameDirectory,
                    path: resolvedFile.destination,
                    oldFile: oldFile
                )
                try replace(source: source, destination: destination)
                nextFiles[resolvedFile.destination.lowercased()] = ModDeploymentFile(
                    path: resolvedFile.destination,
                    owner: resolvedFile.mod.id,
                    sha256: resolvedFile.file.sha256,
                    source: "\(resolvedFile.mod.stagingRelativePath)/files/\(resolvedFile.file.relativePath)",
                    backup: backup.path,
                    originalHash: backup.originalHash
                )
            }

            for oldFile in old.files.values where nextFiles[oldFile.path.lowercased()] == nil {
                let destination = append(oldFile.path, to: gameRoot)
                guard fileManager.fileExists(atPath: destination.path) else { continue }
                if let backup = oldFile.backup,
                   fileManager.fileExists(atPath: append(backup, to: gameDirectory).path) {
                    try replace(source: append(backup, to: gameDirectory), destination: destination)
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
            for (path, original) in originals {
                let destination = append(path, to: gameRoot)
                try? fileManager.removeItem(at: destination)
                try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: original, to: destination)
            }
            for path in missingPaths {
                try? fileManager.removeItem(at: append(path, to: gameRoot))
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
        try saveProfile(
            gameID: state.gameID,
            profileID: profileID,
            profileName: trimmed,
            mods: state.mods,
            plugins: []
        )
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
        if let archive = mod.archiveRelativePath {
            let archiveURL = append(archive, to: gameDirectory)
            if fileManager.fileExists(atPath: archiveURL.path) { try fileManager.removeItem(at: archiveURL) }
        }
        let stagingURL = append(mod.stagingRelativePath, to: gameDirectory)
        if fileManager.fileExists(atPath: stagingURL.path) { try fileManager.removeItem(at: stagingURL) }
        var next = state
        next.mods.removeAll { $0.id == modID }
        try saveProfile(
            gameID: state.gameID,
            profileID: state.profileID,
            profileName: state.profileName,
            mods: next.mods,
            plugins: []
        )
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
        var externalChanges: [String] = []
        if let gameRoot {
            for entry in state.deployment.files.values {
                let destination = append(entry.path, to: gameRoot)
                guard FileManager.default.fileExists(atPath: destination.path),
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
            return FileManager.default.fileExists(atPath: append(backup, to: gameURL(for: state.gameID)).path)
        }
        let deployedOwners = Set(state.deployment.files.values.map(\.owner))
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

    func repairRuntime(gameRoot: URL?) throws -> ModRuntimeState? { nil }

    func launchArguments(for gameRoot: URL?) -> [String] { [] }
}

private extension GTASADefinitiveEditionModManager {
    struct ResolvedFile {
        let destination: String
        let mod: InstalledMod
        let file: ModFile
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

    func scanManifests(in gameDirectory: URL) -> [InstalledMod] {
        let staging = gameDirectory.appending(path: "Staging", directoryHint: .isDirectory)
        guard let children = try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { try? read(InstalledMod.self, at: $0.appending(path: "manifest.json")) }
            .sorted { $0.priority < $1.priority }
    }

    func resolvedFiles(for mods: [InstalledMod]) throws -> [String: ResolvedFile] {
        var result: [String: ResolvedFile] = [:]
        for mod in mods.sorted(by: { $0.priority < $1.priority }) where mod.enabled {
            guard mod.deployStrategy == .unrealPaks || mod.deployStrategy == .cleo else { continue }
            for file in mod.files {
                guard archiveSupport.isSafeRelativePath(file.relativePath) else {
                    throw ModManagerError.invalidRelativePath(file.relativePath)
                }
                let destination: String
                if mod.deployStrategy == .cleo {
                    guard isCleoFileName(file.relativePath) else {
                        throw ModManagerError.invalidRelativePath(file.relativePath)
                    }
                    destination = GTASADefinitiveEditionAdapter.cleoDestinationPath(for: file.relativePath)
                } else {
                    guard file.relativePath.lowercased().hasSuffix(".pak") else {
                        throw ModManagerError.invalidRelativePath(file.relativePath)
                    }
                    destination = GTASADefinitiveEditionAdapter.destinationPath(for: file.relativePath)
                }
                result[destination.lowercased()] = ResolvedFile(destination: destination, mod: mod, file: file)
            }
        }
        return result
    }

    func validateManagedFiles(_ files: [String: ModDeploymentFile], gameRoot: URL) throws {
        for path in files.values.map(\.path) {
            guard archiveSupport.isSafeRelativePath(path) else { throw ModManagerError.invalidRelativePath(path) }
            let destination = append(path, to: gameRoot)
            if FileManager.default.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The managed Definitive Edition destination is unsafe: \(path)")
                }
            }
        }
    }

    func preflightExternalChanges(
        _ files: [String: ModDeploymentFile],
        desiredHashes: [String: String],
        gameRoot: URL
    ) throws {
        for entry in files.values {
            let destination = append(entry.path, to: gameRoot)
            guard FileManager.default.fileExists(atPath: destination.path) else { continue }
            let currentHash = try RuntimeSecurity.sha256(of: destination)
            guard currentHash == entry.sha256 else {
                // A previous manual repair or an external installer may have
                // already placed the exact file selected by the current
                // profile. It is safe to reconcile that state during this
                // deployment; arbitrary third-party changes remain blocked.
                if desiredHashes[entry.path.lowercased()] == currentHash { continue }
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

    func copyTransactionOriginal(_ source: URL, relativePath: String, to directory: URL) throws -> URL {
        let backup = append(relativePath, to: directory)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: backup)
        return backup
    }

    func replace(source: URL, destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }

    func append(_ relativePath: String, to root: URL) -> URL {
        relativePath.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }
    }

    func pakRelativePath(_ source: URL, extracted: URL) throws -> String {
        _ = try archiveSupport.relativePath(of: source, from: extracted)
        let name = source.lastPathComponent
        guard !name.isEmpty, name.lowercased().hasSuffix(".pak") else {
            throw ModManagerError.invalidRelativePath(name)
        }
        return name
    }

    func cleoRelativePath(_ source: URL, extracted: URL) throws -> String {
        _ = try archiveSupport.relativePath(of: source, from: extracted)
        let name = source.lastPathComponent
        guard isCleoFileName(name) else {
            throw ModManagerError.invalidRelativePath(name)
        }
        return name
    }

    func isCleoFile(_ url: URL) -> Bool {
        isCleoFileName(url.lastPathComponent)
    }

    func isCleoFileName(_ name: String) -> Bool {
        ["js", "ini", "cfg", "txt"].contains(URL(fileURLWithPath: name).pathExtension.lowercased())
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
