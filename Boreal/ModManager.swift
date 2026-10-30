import Foundation

nonisolated struct ModManager: Sendable {
    let rootURL: URL

    init(applicationSupportURL: URL) {
        rootURL = applicationSupportURL.appending(path: "Mods", directoryHint: .isDirectory)
    }

    func inspect(archive: URL, gameID: UUID) throws -> ModInstallPreview {
        try inspect(archive: archive, gameID: gameID, gameRoot: nil, pluginsFile: nil)
    }

    func inspect(archive: URL, gameID: UUID, gameRoot: URL?, pluginsFile: URL?) throws -> ModInstallPreview {
        let hasSecurityScope = archive.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { archive.stopAccessingSecurityScopedResource() } }

        let format = try archiveFormat(for: archive)
        let pendingRoot = gameURL(for: gameID).appending(path: "Archives/.pending", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        let pendingURL = pendingRoot.appending(path: "\(UUID().uuidString)-\(archive.lastPathComponent)")
        try FileManager.default.copyItem(at: archive, to: pendingURL)

        do {
            let extracted = try extract(pendingURL, format: format)
            defer { try? FileManager.default.removeItem(at: extracted) }
            let archiveFiles = try contentFiles(in: extracted)
            let fomod = try FomodInstaller.findConfig(in: extracted)
            if fomod.script != nil {
                throw FomodInstallerError.unsupported(["C# FOMOD scripts are not supported. Use an XML-based installer."])
            }

            let current = try load(gameID: gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: nil)
            if let configURL = fomod.config, let packageRoot = fomod.packageRoot {
                let dataRoot = gameRoot.flatMap { SkyrimModAdapter.dataRoot(for: $0) }
                let existingFiles: Set<String>
                if let dataRoot, let files = try? contentFiles(in: dataRoot) {
                    existingFiles = Set(files.compactMap { try? relativePath(of: $0, from: dataRoot).lowercased() })
                } else {
                    existingFiles = []
                }
                let environment = FomodEnvironment(
                    existingFiles: existingFiles,
                    activePlugins: Set(current.plugins.filter(\.enabled).map { $0.filename.lowercased() }),
                    gameVersion: FomodInstaller.gameVersion(executableAt: gameRoot?.appending(path: "SkyrimSE.exe"))
                )
                let plan = try FomodInstaller.parse(
                    configURL: configURL,
                    packageRoot: packageRoot,
                    extractedRoot: extracted,
                    environment: environment
                )
                let selection = plan.initialSelection()
                let warnings = plan.moduleDependencyIssues + plan.supportIssues
                let resolved = plan.isInstallable && plan.selectionIssue(for: selection) == nil
                    ? try plan.resolvedFiles(for: selection, packageRoot: packageRoot)
                    : []
                let pluginCount = resolved.filter { SkyrimModAdapter.pluginType(for: $0.destination) != nil }.count
                let totalSize = resolved.reduce(Int64.zero) { total, file in
                    total + Int64((try? file.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                return ModInstallPreview(
                    gameID: gameID,
                    archiveURL: pendingURL,
                    archiveName: archive.lastPathComponent,
                    format: format,
                    detectedRoot: relativeDisplayPath(packageRoot, from: extracted),
                    fileCount: resolved.count,
                    pluginCount: pluginCount,
                    adapter: .skyrimSpecialEdition,
                    contentType: plan.isInstallable ? .skyrimData : .manual,
                    deployStrategy: plan.isInstallable ? .skyrimDataFolder : .manual,
                    warnings: warnings,
                    canInstallAutomatically: plan.isInstallable,
                    totalSize: totalSize,
                    existingModID: ModIdentity.existingModID(for: archive.lastPathComponent, in: current),
                    fomodPlan: plan,
                    fomodSelection: selection
                )
            }
            let scriptExtenderEntries = try archiveFiles.map { file in
                SkyrimScriptExtenderArchiveEntry(path: try relativePath(of: file, from: extracted), url: file)
            }
            if let scriptExtender = SkyrimScriptExtenderArchive.inspect(
                entries: scriptExtenderEntries,
                installedGameVersion: FomodInstaller.gameVersion(executableAt: gameRoot?.appending(path: "SkyrimSE.exe"))
            ) {
                let totalSize = scriptExtender.files.reduce(Int64.zero) { total, payload in
                    total + Int64((try? payload.source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                return ModInstallPreview(
                    gameID: gameID,
                    archiveURL: pendingURL,
                    archiveName: archive.lastPathComponent,
                    format: format,
                    detectedRoot: scriptExtender.detectedRoot,
                    fileCount: scriptExtender.files.count,
                    pluginCount: 0,
                    adapter: .skyrimSpecialEdition,
                    contentType: .skyrimScriptExtender,
                    deployStrategy: .skyrimScriptExtender,
                    warnings: scriptExtender.warnings,
                    canInstallAutomatically: scriptExtender.canInstallAutomatically,
                    totalSize: totalSize,
                    existingModID: ModIdentity.existingModID(for: archive.lastPathComponent, in: current)
                )
            }
            let dataRoot: URL
            do {
                dataRoot = try findDataRoot(in: extracted)
            } catch {
                let rootPayloads = archiveFiles.compactMap { file -> String? in
                    guard let relative = try? relativePath(of: file, from: extracted),
                          !isInstallerMetadata(relative),
                          !isInformationalFile(relative) else { return nil }
                    return relative
                }
                if !rootPayloads.isEmpty {
                    let examples = rootPayloads.prefix(4).joined(separator: ", ")
                    throw ModManagerError.skyrimManualInstallationRequired([
                        "Boreal could not find a Skyrim Data folder and cannot install these files at the game root: \(examples)."
                    ])
                }
                throw error
            }
            let files = try contentFiles(in: dataRoot)
            let plugins = files.compactMap { SkyrimModAdapter.pluginType(for: $0.lastPathComponent) }
            var warnings: [String] = []
            let unhandledPaths = archiveFiles.compactMap { file -> String? in
                let dataPath = dataRoot.standardizedFileURL.path
                guard !file.standardizedFileURL.path.hasPrefix(dataPath + "/"),
                      let relative = try? relativePath(of: file, from: extracted),
                      !isInstallerMetadata(relative),
                      !isInformationalFile(relative) else { return nil }
                return relative
            }.sorted()
            if !unhandledPaths.isEmpty {
                let examples = unhandledPaths.prefix(4).joined(separator: ", ")
                let remainder = unhandledPaths.count > 4 ? " and \(unhandledPaths.count - 4) more" : ""
                warnings.append("Files outside Skyrim’s Data folder would be skipped: \(examples)\(remainder).")
            }
            return ModInstallPreview(
                gameID: gameID,
                archiveURL: pendingURL,
                archiveName: archive.lastPathComponent,
                format: format,
                detectedRoot: relativeDisplayPath(dataRoot, from: extracted),
                fileCount: files.count,
                pluginCount: plugins.count,
                contentType: warnings.isEmpty ? .skyrimData : .manual,
                deployStrategy: warnings.isEmpty ? .skyrimDataFolder : .manual,
                warnings: warnings,
                canInstallAutomatically: warnings.isEmpty,
                totalSize: files.reduce(Int64.zero) { total, file in
                    total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
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
        profileID: String? = nil,
        auxiliaryRoot: URL? = nil
    ) throws -> ModGameState {
        let gameURL = gameURL(for: gameID)
        let resolvedProfileID = normalizedProfileID(profileID ?? activeProfileID(for: gameID))
        let profileURL = profileURL(for: gameID, profileID: resolvedProfileID)
        let deploymentURL = gameURL.appending(path: "deployment.json")
        let profile = try read(ModProfile.self, at: profileURL)
        let deployment = try ModProfileStorage.loadDeployment(at: deploymentURL, gameID: gameID)
        var plugins: [BethesdaPlugin]
        if let profile {
            // The profile is Boreal's canonical state. plugins.txt is only an
            // output artifact and must not repopulate an intentionally empty
            // or disabled profile.
            plugins = profile.plugins
        } else {
            plugins = readPluginsFile(pluginsFile)
            if plugins.isEmpty, let gameRoot, let dataRoot = SkyrimModAdapter.dataRoot(for: gameRoot) {
                plugins = scanBasePlugins(in: dataRoot)
            }
        }

        let storedMods = profile?.mods ?? scanManifests(in: gameURL)
        let discoveredMods = scanExternalMods(
            in: gameRoot,
            deployment: deployment,
            knownPlugins: plugins
        )
        var mods = ExternalModDiscovery.merge(managed: storedMods, discovered: discoveredMods)
        mods = mods.sorted { $0.priority == $1.priority ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.priority < $1.priority }
        for index in mods.indices { mods[index].priority = index }
        plugins.append(contentsOf: discoveredMods.flatMap(\.plugins))
        plugins = reconcilePlugins(plugins, with: mods)
        plugins = enrichPluginMetadata(plugins, mods: mods, gameRoot: gameRoot, gameDirectory: gameURL)
        for index in mods.indices {
            mods[index].plugins = plugins.filter { $0.modID == mods[index].id }
        }
        let currentFingerprint = ModProfileFingerprint.make(mods: mods, plugins: plugins)
        var resolvedDeployment = deployment
        if deployment.profileFingerprint == nil && mods.isEmpty {
            resolvedDeployment.profileFingerprint = currentFingerprint
        }
        return ModGameState(
            gameID: gameID,
            profileID: resolvedProfileID,
            profileName: profile?.name ?? (resolvedProfileID == "default" ? "Default" : resolvedProfileID),
            mods: mods,
            plugins: plugins,
            deployment: resolvedDeployment,
            adapter: .skyrimSpecialEdition,
            runtime: nil
        )
    }

    func install(
        preview: ModInstallPreview,
        gameRoot: URL?,
        pluginsFile: URL?,
        profileID: String = "default",
        auxiliaryRoot: URL? = nil
    ) throws -> ModGameState {
        guard preview.canInstallAutomatically else {
            throw ModManagerError.skyrimManualInstallationRequired(preview.warnings)
        }
        let fileManager = FileManager.default
        let format = try archiveFormat(for: preview.archiveURL)
        let extracted = try extract(preview.archiveURL, format: format)
        defer { try? fileManager.removeItem(at: extracted) }
        let sourceFiles: [(source: URL, destination: String, destinationRoot: ModFileDestinationRoot, stagedPath: String)]
        if let plan = preview.fomodPlan {
            let packageRoot = plan.packageRootRelativePath.split(separator: "/").reduce(extracted) {
                $0.appending(path: String($1), directoryHint: .isDirectory)
            }
            let resolved = try plan.resolvedFiles(for: preview.fomodSelection, packageRoot: packageRoot)
            sourceFiles = resolved.map {
                (source: $0.sourceURL, destination: $0.destination, destinationRoot: .data, stagedPath: $0.destination)
            }
        } else if preview.contentType == .skyrimScriptExtender {
            guard let gameRoot,
                  let inspection = SkyrimScriptExtenderArchive.inspect(
                      entries: try contentFiles(in: extracted).map {
                          SkyrimScriptExtenderArchiveEntry(path: try relativePath(of: $0, from: extracted), url: $0)
                      },
                      installedGameVersion: FomodInstaller.gameVersion(executableAt: gameRoot.appending(path: "SkyrimSE.exe"))
                  ),
                  inspection.canInstallAutomatically else {
                throw ModManagerError.skyrimManualInstallationRequired([
                    "The SKSE archive no longer matches the installed Skyrim version or is missing required files."
                ])
            }
            sourceFiles = inspection.files.map {
                (source: $0.source, destination: $0.relativePath, destinationRoot: $0.destinationRoot, stagedPath: $0.stagedSourcePath)
            }
        } else {
            let dataRoot = try findDataRoot(in: extracted)
            sourceFiles = try contentFiles(in: dataRoot).map { source in
                let relative = try relativePath(of: source, from: dataRoot)
                return (source: source, destination: relative, destinationRoot: .data, stagedPath: relative)
            }
        }
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
            var seen: Set<String> = []
            for payload in sourceFiles {
                let source = payload.source
                let relative = payload.destination
                let key = payload.destinationRoot.key(for: relative)
                guard seen.insert(key).inserted else { throw ModManagerError.duplicatePath(relative) }
                guard isSafeRelativePath(relative), isSafeRelativePath(payload.stagedPath) else {
                    throw ModManagerError.invalidRelativePath(relative)
                }
                let destination = append(payload.stagedPath, to: stagingDirectory)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: destination)
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw ModManagerError.symbolicLinkNotAllowed(source) }
                files.append(ModFile(
                    relativePath: relative,
                    sha256: try RuntimeSecurity.sha256(of: source),
                    size: Int64(values.fileSize ?? 0),
                    stagedSourcePath: payload.stagedPath == relative ? nil : payload.stagedPath,
                    destinationRoot: payload.destinationRoot
                ))
            }

            let modID = replacement?.id ?? stagingID
            let archiveDirectory = gameDirectory.appending(path: "Archives", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let archiveName = "\(stagingID.uuidString)-\(preview.archiveName)"
            let archiveDestination = archiveDirectory.appending(path: archiveName)
            try fileManager.copyItem(at: preview.archiveURL, to: archiveDestination)

            let pluginRecords = files.compactMap { file -> BethesdaPlugin? in
                guard file.destinationRoot == .data else { return nil }
                guard let type = SkyrimModAdapter.pluginType(for: file.relativePath) else { return nil }
                let source = append(file.stagedPath, to: stagingDirectory)
                let header = SkyrimModAdapter.inspectPlugin(at: source)
                let previous = replacement?.plugins.first {
                    $0.filename.caseInsensitiveCompare(URL(fileURLWithPath: file.relativePath).lastPathComponent) == .orderedSame
                }
                return BethesdaPlugin(
                    filename: URL(fileURLWithPath: file.relativePath).lastPathComponent,
                    type: type,
                    classification: header?.classification,
                    masters: header?.masters ?? [],
                    headerFlags: header?.flags ?? 0,
                    headerParsed: header != nil,
                    enabled: previous?.enabled ?? true,
                    loadOrder: previous?.loadOrder ?? current.plugins.count,
                    modID: modID
                )
            }
            let mod = InstalledMod(
                id: modID,
                name: URL(fileURLWithPath: preview.archiveName).deletingPathExtension().lastPathComponent,
                version: replacement?.version,
                enabled: replacement?.enabled ?? true,
                priority: replacement?.priority ?? current.mods.count,
                archiveRelativePath: "Archives/\(archiveName)",
                stagingRelativePath: "Staging/\(stagingID.uuidString)",
                installedAt: .now,
                files: files,
                plugins: pluginRecords,
                contentType: preview.contentType,
                deployStrategy: preview.deployStrategy
            )
            var mods = current.mods
            if let index = replacement.flatMap({ replacement in mods.firstIndex { $0.id == replacement.id } }) {
                mods[index] = mod
            } else {
                mods.append(mod)
            }
            var plugins = current.plugins.filter { $0.modID != modID }
            plugins.append(contentsOf: pluginRecords)
            try saveProfile(
                gameID: preview.gameID,
                profileID: current.profileID,
                profileName: current.profileName,
                mods: mods,
                plugins: plugins,
                gameDirectory: gameDirectory
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
        try saveProfile(
            gameID: gameID,
            profileID: normalizedProfileID(profileID),
            profileName: profileName,
            mods: mods,
            plugins: plugins,
            gameDirectory: gameURL(for: gameID)
        )
    }

    func deploy(
        state: ModGameState,
        gameRoot: URL?,
        pluginsFile: URL?
    ) throws -> ModGameState {
        guard let gameRoot,
              let dataRoot = SkyrimModAdapter.dataRoot(for: gameRoot) else {
            throw ModManagerError.gameRootUnavailable
        }
        let fileManager = FileManager.default
        let gameDirectory = gameURL(for: state.gameID)
        try fileManager.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let old = try ModProfileStorage.loadDeployment(at: gameDirectory.appending(path: "deployment.json"), gameID: state.gameID)
        let plugins = reconcilePlugins(state.plugins, with: state.mods)

        let validation = ModValidationReport.make(mods: state.mods, plugins: plugins)
        if !validation.missingMasters.isEmpty {
            throw ModManagerError.missingPluginMasters(validation.missingMasters)
        }
        if !validation.invalidPluginHeaders.isEmpty {
            throw ModManagerError.invalidPluginHeaders(validation.invalidPluginHeaders)
        }
        if validation.exceedsFullPluginLimit || validation.exceedsLightPluginLimit {
            throw ModManagerError.pluginLimitExceeded(full: validation.fullPluginCount, light: validation.lightPluginCount)
        }

        let resolved = try resolvedFiles(for: state.mods, gameDirectory: gameDirectory)
        try validateManagedFiles(old.files, gameRoot: gameRoot, dataRoot: dataRoot)
        try preflightExternalChanges(old.files, gameRoot: gameRoot, dataRoot: dataRoot)
        let transactionURL = gameDirectory.appending(path: ".transactions/\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: transactionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transactionURL) }
        var changedTargets: [String: DeploymentTarget] = [:]
        for entry in old.files.values {
            let target = DeploymentTarget(path: entry.path, root: entry.destinationRoot)
            changedTargets[target.key] = target
        }
        for resolvedFile in resolved.values {
            let target = DeploymentTarget(path: resolvedFile.file.relativePath, root: resolvedFile.file.destinationRoot)
            changedTargets[target.key] = target
        }
        var transactionOriginals: [String: URL] = [:]
        var transactionMissingPaths: Set<String> = []
        var transactionPluginOriginal: URL?
        var transactionPluginWasMissing = false
        do {
            for (key, target) in changedTargets {
                let destination = target.url(gameRoot: gameRoot, dataRoot: dataRoot)
                guard fileManager.fileExists(atPath: destination.path) else {
                    transactionMissingPaths.insert(key)
                    continue
                }
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The destination is not a regular file: \(target.displayPath)")
                }
                let backup = append(key, to: transactionURL)
                try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: destination, to: backup)
                transactionOriginals[key] = backup
            }

            var nextFiles: [String: ModDeploymentFile] = [:]
            for (key, resolvedFile) in resolved {
                let target = DeploymentTarget(path: resolvedFile.file.relativePath, root: resolvedFile.file.destinationRoot)
                let destination = target.url(gameRoot: gameRoot, dataRoot: dataRoot)
                let source = append(resolvedFile.file.stagedPath, to: append(resolvedFile.mod.stagingRelativePath + "/files", to: gameDirectory))
                let actualSourceHash = try RuntimeSecurity.sha256(of: source)
                guard actualSourceHash == resolvedFile.file.sha256 else {
                    throw ModManagerError.stagedFileChanged(target.displayPath)
                }
                let oldFile = old.files[key]
                let backupInfo = try prepareBackup(
                    destination: destination,
                    gameDirectory: gameDirectory,
                    path: key,
                    oldFile: oldFile
                )
                try replace(source: source, destination: destination)
                nextFiles[key] = ModDeploymentFile(
                    path: resolvedFile.file.relativePath,
                    owner: resolvedFile.mod.id,
                    sha256: resolvedFile.file.sha256,
                    source: "\(resolvedFile.mod.stagingRelativePath)/files/\(resolvedFile.file.stagedPath)",
                    backup: backupInfo.path,
                    originalHash: backupInfo.originalHash,
                    destinationRoot: resolvedFile.file.destinationRoot
                )
            }

            for (key, oldFile) in old.files where resolved[key] == nil {
                let target = DeploymentTarget(path: oldFile.path, root: oldFile.destinationRoot)
                let destination = target.url(gameRoot: gameRoot, dataRoot: dataRoot)
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
                profileFingerprint: ModProfileFingerprint.make(mods: state.mods, plugins: plugins),
                files: nextFiles,
                pluginFilePath: old.pluginFilePath,
                pluginFileHash: old.pluginFileHash,
                pluginFileBackup: old.pluginFileBackup,
                pluginFileOriginalHash: old.pluginFileOriginalHash
            )
            if let pluginsFile, fileManager.fileExists(atPath: pluginsFile.path) {
                let original = transactionURL.appending(path: "plugins-original.txt")
                try fileManager.copyItem(at: pluginsFile, to: original)
                transactionPluginOriginal = original
            } else if pluginsFile != nil {
                transactionPluginWasMissing = true
            }
            try synchronizePlugins(
                plugins,
                mods: state.mods,
                gameRoot: gameRoot,
                at: pluginsFile,
                gameDirectory: gameDirectory,
                old: old,
                next: &next,
                transactionURL: transactionURL
            )
            try saveJSON(next, at: gameDirectory.appending(path: "deployment.json"))
            try saveProfile(
                gameID: state.gameID,
                profileID: state.profileID,
                profileName: state.profileName,
                mods: state.mods,
                plugins: plugins,
                gameDirectory: gameDirectory
            )
            var deployedState = try load(
                gameID: state.gameID,
                gameRoot: gameRoot,
                pluginsFile: pluginsFile,
                profileID: state.profileID
            )
            let deployedFingerprint = ModProfileFingerprint.make(
                mods: deployedState.mods,
                plugins: deployedState.plugins
            )
            if next.profileFingerprint != deployedFingerprint {
                next.profileFingerprint = deployedFingerprint
                try saveJSON(next, at: gameDirectory.appending(path: "deployment.json"))
                deployedState.deployment = next
            }
            return deployedState
        } catch {
            for (key, original) in transactionOriginals {
                guard let target = changedTargets[key] else { continue }
                let destination = target.url(gameRoot: gameRoot, dataRoot: dataRoot)
                try? fileManager.removeItem(at: destination)
                try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: original, to: destination)
            }
            for key in transactionMissingPaths {
                guard let target = changedTargets[key] else { continue }
                try? fileManager.removeItem(at: target.url(gameRoot: gameRoot, dataRoot: dataRoot))
            }
            if let pluginsFile, let original = transactionPluginOriginal {
                try? fileManager.removeItem(at: pluginsFile)
                try? fileManager.createDirectory(at: pluginsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: original, to: pluginsFile)
            } else if let pluginsFile, transactionPluginWasMissing {
                try? fileManager.removeItem(at: pluginsFile)
            }
            throw error
        }
    }

    // MARK: Paths and persistence

    private func gameURL(for gameID: UUID) -> URL {
        rootURL.appending(path: gameID.uuidString, directoryHint: .isDirectory)
    }

    func profiles(for gameID: UUID) -> [ModProfileDescriptor] {
        let profilesDirectory = gameURL(for: gameID).appending(path: "profiles", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: profilesDirectory,
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
        guard profileID != "default" || trimmed.caseInsensitiveCompare("default") == .orderedSame else {
            throw ModManagerError.invalidProfileName
        }
        guard !profiles(for: state.gameID).contains(where: { $0.id.caseInsensitiveCompare(profileID) == .orderedSame }) else {
            throw ModManagerError.profileAlreadyExists(trimmed)
        }
        try saveProfile(
            gameID: state.gameID,
            profileID: profileID,
            profileName: trimmed,
            mods: state.mods,
            plugins: state.plugins,
            gameDirectory: gameURL(for: state.gameID)
        )
        try activateProfile(profileID, for: state.gameID)
        var created = state
        created.profileID = profileID
        created.profileName = trimmed
        return created
    }

    func removeMod(_ modID: UUID, from state: ModGameState) throws -> ModGameState {
        guard let mod = state.mods.first(where: { $0.id == modID }), !mod.isExternallyDetected else { return state }
        let gameDirectory = gameURL(for: state.gameID)
        var next = state
        next.mods.removeAll { $0.id == modID }
        next.plugins.removeAll { $0.modID == modID }
        try saveProfile(
            gameID: state.gameID,
            profileID: state.profileID,
            profileName: state.profileName,
            mods: next.mods,
            plugins: next.plugins,
            gameDirectory: gameDirectory
        )
        try ModProfileStorage.removeUnreferencedPackage(mod, in: gameDirectory, excludingProfileID: state.profileID)
        return next
    }

    func stagedModURL(gameID: UUID, modID: UUID) -> URL? {
        let directory = gameURL(for: gameID).appending(path: "Staging/\(modID.uuidString)", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }

    func activateProfile(_ profileID: String, for gameID: UUID) throws {
        let normalized = normalizedProfileID(profileID)
        let url = activeProfileURL(for: gameID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(normalized.utf8).write(to: url, options: .atomic)
    }

    func deploymentHealth(
        for state: ModGameState,
        gameRoot: URL?,
        pluginsFile: URL?,
        auxiliaryRoot: URL? = nil
    ) -> ModDeploymentHealth {
        let fileManager = FileManager.default
        var externalChanges: [String] = []
        if let gameRoot, let dataRoot = SkyrimModAdapter.dataRoot(for: gameRoot) {
            for entry in state.deployment.files.values {
                let target = DeploymentTarget(path: entry.path, root: entry.destinationRoot)
                guard isSafeRelativePath(target.path) else {
                    externalChanges.append("Invalid managed path")
                    continue
                }
                let destination = target.url(gameRoot: gameRoot, dataRoot: dataRoot)
                guard fileManager.fileExists(atPath: destination.path),
                      (try? RuntimeSecurity.sha256(of: destination)) == entry.sha256 else {
                    externalChanges.append(target.displayPath)
                    continue
                }
            }
        }

        let activePluginCount = state.plugins.filter { plugin in
            guard plugin.enabled else { return false }
            guard let modID = plugin.modID else { return true }
            return state.mods.first(where: { $0.id == modID })?.enabled == true
        }.count
        var pluginsSynchronized = state.deployment.deployedAt == nil
        if let path = state.deployment.pluginFilePath,
           let hash = state.deployment.pluginFileHash,
           let pluginsFile,
           path == pluginsFile.standardizedFileURL.path,
           fileManager.fileExists(atPath: pluginsFile.path) {
            let expected = SkyrimModAdapter.pluginsFileData(
                plugins: state.plugins,
                mods: state.mods,
                gameRoot: gameRoot
            )
            pluginsSynchronized = (try? Data(contentsOf: pluginsFile)) == expected
                && (try? RuntimeSecurity.sha256(of: pluginsFile)) == hash
        } else if activePluginCount > 0, state.deployment.deployedAt != nil {
            pluginsSynchronized = false
        }
        if !pluginsSynchronized, state.deployment.deployedAt != nil {
            externalChanges.append("plugins.txt")
        }

        let vanillaFilesProtected = state.deployment.deployedAt == nil || state.deployment.files.values.allSatisfy { entry in
            guard entry.originalHash != nil else { return true }
            guard let backup = entry.backup else { return false }
            return fileManager.fileExists(atPath: append(backup, to: gameURL(for: state.gameID)).path)
        }
        let deployedOwners = Set(state.deployment.files.values.map(\.owner))
        return ModDeploymentHealth(
            deployedModCount: deployedOwners.count,
            managedFileCount: state.deployment.files.count,
            pluginsSynchronized: pluginsSynchronized,
            vanillaFilesProtected: vanillaFilesProtected,
            externalChanges: Array(Set(externalChanges)).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            validation: state.validation,
            pendingChanges: state.pendingChanges,
            lastDeployment: state.deployment.deployedAt
        )
    }

    private func profileURL(for gameID: UUID, profileID: String) -> URL {
        gameURL(for: gameID)
            .appending(path: "profiles", directoryHint: .isDirectory)
            .appending(path: "\(normalizedProfileID(profileID)).json")
    }

    private func activeProfileURL(for gameID: UUID) -> URL {
        gameURL(for: gameID).appending(path: "active-profile.txt")
    }

    private func activeProfileID(for gameID: UUID) -> String {
        guard let data = try? Data(contentsOf: activeProfileURL(for: gameID)),
              let value = String(data: data, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "default"
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedProfileID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("default") == .orderedSame { return "default" }
        let scalarValues = trimmed.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return String(scalar)
            }
            return "-"
        }
        let result = scalarValues.joined().split(separator: "-").joined(separator: "-").lowercased()
        return result.isEmpty ? "profile-\(UUID().uuidString.prefix(8).lowercased())" : result
    }

    private func saveProfile(
        gameID: UUID,
        profileID: String,
        profileName: String,
        mods: [InstalledMod],
        plugins: [BethesdaPlugin],
        gameDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: gameDirectory.appending(path: "profiles", directoryHint: .isDirectory), withIntermediateDirectories: true)
        let normalizedMods = mods.enumerated().map { index, mod -> InstalledMod in
            var value = mod
            value.priority = index
            return value
        }
        let canonicalPlugins = reconcilePlugins(plugins, with: normalizedMods)
        let normalizedPlugins = canonicalPlugins.enumerated().map { index, plugin -> BethesdaPlugin in
            var value = plugin
            value.loadOrder = index
            return value
        }
        let normalizedModsWithPlugins = normalizedMods.map { mod -> InstalledMod in
            var value = mod
            value.plugins = normalizedPlugins.filter { $0.modID == mod.id }
            return value
        }
        let profile = ModProfile(gameID: gameID, name: profileName, mods: normalizedModsWithPlugins, plugins: normalizedPlugins, updatedAt: .now)
        try saveJSON(profile, at: profileURL(for: gameID, profileID: profileID))
        for mod in normalizedModsWithPlugins where !mod.isExternallyDetected {
            let manifestURL = append("\(mod.stagingRelativePath)/manifest.json", to: gameDirectory)
            try saveJSON(mod, at: manifestURL)
        }
    }

    private func scanManifests(in gameDirectory: URL) -> [InstalledMod] {
        let staging = gameDirectory.appending(path: "Staging", directoryHint: .isDirectory)
        guard let children = try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return children.compactMap { child in
            try? read(InstalledMod.self, at: child.appending(path: "manifest.json"))
        }.sorted { $0.priority < $1.priority }
    }

    private func scanExternalMods(
        in gameRoot: URL?,
        deployment: ModDeploymentManifest,
        knownPlugins: [BethesdaPlugin]
    ) -> [InstalledMod] {
        guard let gameRoot,
              let dataRoot = SkyrimModAdapter.dataRoot(for: gameRoot),
              let children = try? FileManager.default.contentsOfDirectory(
                  at: dataRoot,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        let managedPaths = Set(deployment.files.values
            .filter { $0.destinationRoot == .data }
            .map { $0.path.lowercased() })
        let pluginFiles = children.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && SkyrimModAdapter.pluginType(for: $0.lastPathComponent) != nil
                && !SkyrimModAdapter.isBasePlugin($0.lastPathComponent)
                && !managedPaths.contains($0.lastPathComponent.lowercased())
        }
        var groups: [String: [URL]] = [:]
        for plugin in pluginFiles {
            groups[ModIdentity.key(for: plugin.lastPathComponent), default: []].append(plugin)
        }

        for file in children where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            guard file.pathExtension.caseInsensitiveCompare("bsa") == .orderedSame,
                  !managedPaths.contains(file.lastPathComponent.lowercased()),
                  !SkyrimModAdapter.isBaseArchive(file.lastPathComponent) else { continue }
            let key = ModIdentity.key(for: file.deletingPathExtension().lastPathComponent)
            groups[key, default: []].append(file)
        }

        var result: [InstalledMod] = []
        for key in groups.keys.sorted() {
            let files = groups[key] ?? []
            guard let pluginURL = files.first(where: { SkyrimModAdapter.pluginType(for: $0.lastPathComponent) != nil }) else {
                if let mod = ExternalModDiscovery.makeMod(
                    adapter: .skyrimSpecialEdition,
                    name: files.first?.deletingPathExtension().lastPathComponent ?? "External Skyrim files",
                    detectionKey: "data/\(key)",
                    files: files,
                    relativeTo: dataRoot,
                    contentType: .skyrimData,
                    deployStrategy: .skyrimDataFolder
                ) {
                    result.append(mod)
                }
                continue
            }

            let detectionKey = "data/\(key)"
            let modID = ModIdentity.externalID(adapter: .skyrimSpecialEdition, detectionKey: detectionKey)
            let configured = knownPlugins.first {
                $0.filename.caseInsensitiveCompare(pluginURL.lastPathComponent) == .orderedSame
            }
            var plugin = BethesdaPlugin(
                filename: pluginURL.lastPathComponent,
                type: SkyrimModAdapter.pluginType(for: pluginURL.lastPathComponent)!,
                enabled: configured?.enabled ?? true,
                loadOrder: configured?.loadOrder ?? 0,
                modID: modID
            ).withHeader(SkyrimModAdapter.inspectPlugin(at: pluginURL))
            guard var mod = ExternalModDiscovery.makeMod(
                adapter: .skyrimSpecialEdition,
                name: pluginURL.deletingPathExtension().lastPathComponent,
                detectionKey: detectionKey,
                files: files,
                relativeTo: dataRoot,
                contentType: .skyrimData,
                deployStrategy: .skyrimDataFolder,
                plugins: [plugin]
            ) else { continue }
            plugin.modID = mod.id
            mod.plugins = [plugin]
            result.append(mod)
        }

        let sksePlugins = dataRoot.appending(path: "SKSE/Plugins", directoryHint: .isDirectory)
        if let files = try? FileManager.default.contentsOfDirectory(
            at: sksePlugins,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for file in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let relative = "SKSE/Plugins/\(file.lastPathComponent)"
                guard !managedPaths.contains(relative.lowercased()) else { continue }
                if let mod = ExternalModDiscovery.makeMod(
                    adapter: .skyrimSpecialEdition,
                    name: "SKSE plugin — \(file.deletingPathExtension().lastPathComponent)",
                    detectionKey: relative,
                    files: [file],
                    relativeTo: dataRoot,
                    contentType: .coreComponent
                ) {
                    result.append(mod)
                }
            }
        }
        return result
    }

    private func isModStorageReferenced(
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

    private func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func saveJSON<T: Encodable>(_ value: T, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func archiveFormat(for archive: URL) throws -> ModArchiveFormat {
        guard FileManager.default.isReadableFile(atPath: archive.path),
              let format = ModArchiveFormat(fileExtension: archive.pathExtension) else {
            throw ModManagerError.unsupportedArchive(archive)
        }
        return format
    }

    private func append(_ relativePath: String, to root: URL) -> URL {
        relativePath.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }
    }

    private func relativePath(of url: URL, from root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { throw ModManagerError.invalidRelativePath(path) }
        let relative = String(path.dropFirst(rootPath.count + 1)).replacingOccurrences(of: "\\", with: "/")
        guard isSafeRelativePath(relative) else { throw ModManagerError.invalidRelativePath(relative) }
        return relative
    }

    private func relativeDisplayPath(_ url: URL, from root: URL) -> String {
        (try? relativePath(of: url, from: root)) ?? "/"
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        return !components.isEmpty && !components.contains("..") && !components.contains(where: { $0.contains(":") })
    }

    private func contentFiles(in root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { throw ModManagerError.extractedArchiveEmpty }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw ModManagerError.symbolicLinkNotAllowed(url) }
            if values.isRegularFile == true {
                if url.lastPathComponent == ".DS_Store" || url.pathComponents.contains("__MACOSX") { continue }
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func isInstallerMetadata(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains {
            $0.caseInsensitiveCompare("fomod") == .orderedSame
        }
    }

    private func isInformationalFile(_ relativePath: String) -> Bool {
        let filename = URL(fileURLWithPath: relativePath).lastPathComponent.lowercased()
        let informationalPrefixes = ["readme", "license", "licence", "changelog", "credits"]
        if informationalPrefixes.contains(where: filename.hasPrefix) { return true }
        return ["txt", "md", "rtf", "pdf", "html", "htm", "png", "jpg", "jpeg", "gif", "webp"]
            .contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
    }

    private func findDataRoot(in extracted: URL) throws -> URL {
        let fileManager = FileManager.default
        let root = extracted.standardizedFileURL
        let candidates = [root] + (fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])?.compactMap { url -> URL? in
            guard let url = url as? URL,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let relative = try? relativePath(of: url, from: root),
                  relative.split(separator: "/").count <= 4 else { return nil }
            return url
        } ?? [])

        let dataDirectories = candidates.filter { $0.lastPathComponent.caseInsensitiveCompare("Data") == .orderedSame && hasDataContent($0) }
        if let data = dataDirectories.min(by: { $0.pathComponents.count < $1.pathComponents.count }) { return data }
        if hasDataContent(root) { return root }
        if let best = candidates.filter({ hasDataContent($0) }).max(by: { dataScore($0) < dataScore($1) }) { return best }
        throw ModManagerError.dataRootNotFound(extracted)
    }

    private func hasDataContent(_ directory: URL) -> Bool {
        guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return false }
        return children.contains { child in
            let name = child.lastPathComponent.lowercased()
            if Self.isPluginFilename(name) || name.hasSuffix(".bsa") { return true }
            return Self.isKnownDataDirectory(name) && (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func dataScore(_ directory: URL) -> Int {
        guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return 0 }
        return children.reduce(0) { score, child in
            let name = child.lastPathComponent.lowercased()
            if Self.isPluginFilename(name) { return score + 4 }
            if name.hasSuffix(".bsa") { return score + 3 }
            return score + (Self.isKnownDataDirectory(name) ? 2 : 0)
        }
    }

    private static func isKnownDataDirectory(_ name: String) -> Bool { SkyrimModAdapter.supportedDataDirectories.contains(name) }
    private static func isPluginFilename(_ name: String) -> Bool { [".esm", ".esp", ".esl"].contains { name.hasSuffix($0) } }

    private func extract(_ archive: URL, format: ModArchiveFormat) throws -> URL {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appending(path: "boreal-mod-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            case .loosePak, .dzip:
                throw ModManagerError.archiveToolUnavailable(format)
            }
            _ = try contentFiles(in: temporary)
            return temporary
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func archiveEntries(_ archive: URL, format: ModArchiveFormat) throws -> [String] {
        switch format {
        case .zip:
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else { throw ModManagerError.archiveToolUnavailable(format) }
            let output = try run(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-Z1", archive.path])
            return output.split(whereSeparator: \.isNewline).map(String.init)
        case .sevenZip, .rar:
            guard let tool = sevenZipTool() else { throw ModManagerError.archiveToolUnavailable(format) }
            let output = try run(tool, arguments: ["l", "-slt", archive.path])
            let archivePath = archive.standardizedFileURL.path
            return output.split(whereSeparator: \.isNewline).compactMap { line in
                let value = String(line)
                guard value.hasPrefix("Path = ") else { return nil }
                let path = String(value.dropFirst("Path = ".count))
                // 7-Zip emits the archive itself as the first Path entry.
                // It is metadata, not an archive member. Do not weaken the
                // traversal check for any other absolute path.
                let listedPath = URL(fileURLWithPath: path).standardizedFileURL.path
                guard !path.isEmpty,
                      path != archive.lastPathComponent,
                      listedPath != archivePath else { return nil }
                return path
            }
        case .loosePak, .dzip:
            throw ModManagerError.archiveToolUnavailable(format)
        }
    }

    private func sevenZipTool() -> URL? {
        ["/opt/homebrew/bin/7z", "/opt/homebrew/bin/7zz", "/usr/local/bin/7z", "/usr/local/bin/7zz", "/usr/bin/7z"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func run(_ executable: URL, arguments: [String]) throws -> String {
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

    private func reconcilePlugins(_ plugins: [BethesdaPlugin], with mods: [InstalledMod]) -> [BethesdaPlugin] {
        let validModIDs = Set(mods.map(\.id))
        let orderedPlugins = plugins.enumerated()
            .filter { $0.element.modID == nil || validModIDs.contains($0.element.modID!) }
            .sorted {
                if $0.element.loadOrder != $1.element.loadOrder {
                    return $0.element.loadOrder < $1.element.loadOrder
                }
                return $0.offset < $1.offset
            }
            .map(\.element)
        var result: [BethesdaPlugin] = []
        var indicesByFilename: [String: Int] = [:]

        func insertOrReconcile(_ plugin: BethesdaPlugin) {
            let key = plugin.filename.lowercased()
            guard let existingIndex = indicesByFilename[key] else {
                indicesByFilename[key] = result.count
                result.append(plugin)
                return
            }
            guard shouldPreferPluginOwner(plugin, over: result[existingIndex], mods: mods) else { return }
            var replacement = plugin
            replacement.enabled = result[existingIndex].enabled
            replacement.loadOrder = result[existingIndex].loadOrder
            result[existingIndex] = replacement
        }

        for plugin in orderedPlugins { insertOrReconcile(plugin) }
        for mod in mods {
            for plugin in mod.plugins {
                insertOrReconcile(plugin)
            }
        }
        for index in result.indices { result[index].loadOrder = index }
        return result
    }

    private func shouldPreferPluginOwner(
        _ candidate: BethesdaPlugin,
        over current: BethesdaPlugin,
        mods: [InstalledMod]
    ) -> Bool {
        guard candidate.modID != current.modID else { return false }

        func rank(_ plugin: BethesdaPlugin) -> (kind: Int, priority: Int) {
            guard let modID = plugin.modID,
                  let mod = mods.first(where: { $0.id == modID }) else { return (1, Int.min) }
            if mod.isExternallyDetected { return (2, mod.priority) }
            return (mod.enabled ? 3 : 0, mod.priority)
        }

        let candidateRank = rank(candidate)
        let currentRank = rank(current)
        if candidateRank.kind != currentRank.kind { return candidateRank.kind > currentRank.kind }
        return candidateRank.priority > currentRank.priority
    }

    private func readPluginsFile(_ url: URL?) -> [BethesdaPlugin] {
        guard let url,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).enumerated().compactMap { index, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let enabled = line.hasPrefix("*")
            let filename = enabled ? String(line.dropFirst()) : line
            guard let type = SkyrimModAdapter.pluginType(for: filename), !filename.isEmpty else { return nil }
            return BethesdaPlugin(filename: filename, type: type, enabled: enabled, loadOrder: index, modID: nil)
        }
    }

    private func scanBasePlugins(in dataRoot: URL) -> [BethesdaPlugin] {
        guard let children = try? FileManager.default.contentsOfDirectory(at: dataRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        let plugins: [BethesdaPlugin] = children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { url -> BethesdaPlugin? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let type = SkyrimModAdapter.pluginType(for: url.lastPathComponent) else { return nil }
            let header = SkyrimModAdapter.inspectPlugin(at: url)
            return BethesdaPlugin(filename: url.lastPathComponent, type: type, enabled: true, loadOrder: 0, modID: nil)
                .withHeader(header)
        }.enumerated().map { index, plugin in
            var value = plugin
            value.loadOrder = index
            return value
        }
        return plugins
    }

    private func enrichPluginMetadata(
        _ plugins: [BethesdaPlugin],
        mods: [InstalledMod],
        gameRoot: URL?,
        gameDirectory: URL
    ) -> [BethesdaPlugin] {
        let dataRoot = gameRoot.flatMap { SkyrimModAdapter.dataRoot(for: $0) }
        return plugins.map { plugin in
            let source: URL?
            if let modID = plugin.modID,
               let mod = mods.first(where: { $0.id == modID }),
               let file = mod.files.first(where: {
                   URL(fileURLWithPath: $0.relativePath).lastPathComponent.caseInsensitiveCompare(plugin.filename) == .orderedSame
               }) {
                source = mod.isExternallyDetected
                    ? dataRoot?.appending(path: file.relativePath)
                    : append(file.relativePath, to: append(mod.stagingRelativePath + "/files", to: gameDirectory))
            } else {
                source = dataRoot?.appending(path: plugin.filename)
            }
            return plugin.withHeader(source.flatMap { SkyrimModAdapter.inspectPlugin(at: $0) })
        }
    }

    private struct ResolvedFile {
        let mod: InstalledMod
        let file: ModFile
    }

    private struct DeploymentTarget {
        let path: String
        let root: ModFileDestinationRoot

        var key: String { root.key(for: path) }
        var displayPath: String { root.displayPath(path) }

        func url(gameRoot: URL, dataRoot: URL) -> URL {
            ModFileDestination.url(root: root, relativePath: path, gameRoot: gameRoot, dataRoot: dataRoot)
        }
    }

    private func resolvedFiles(for mods: [InstalledMod], gameDirectory: URL) throws -> [String: ResolvedFile] {
        var result: [String: ResolvedFile] = [:]
        for mod in mods.sorted(by: { $0.priority < $1.priority }) where mod.enabled && !mod.isExternallyDetected {
            for file in mod.files {
                guard isSafeRelativePath(file.relativePath), isSafeRelativePath(file.stagedPath) else {
                    throw ModManagerError.invalidRelativePath(file.relativePath)
                }
                result[file.id] = ResolvedFile(mod: mod, file: file)
            }
        }
        return result
    }

    private func validateManagedFiles(
        _ files: [String: ModDeploymentFile],
        gameRoot: URL,
        dataRoot: URL
    ) throws {
        for entry in files.values {
            let target = DeploymentTarget(path: entry.path, root: entry.destinationRoot)
            guard isSafeRelativePath(target.path) else { throw ModManagerError.invalidRelativePath(target.path) }
            let destination = target.url(gameRoot: gameRoot, dataRoot: dataRoot)
            if FileManager.default.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The managed destination is unsafe: \(target.displayPath)")
                }
            }
        }
    }

    private func preflightExternalChanges(
        _ files: [String: ModDeploymentFile],
        gameRoot: URL,
        dataRoot: URL
    ) throws {
        for entry in files.values {
            let target = DeploymentTarget(path: entry.path, root: entry.destinationRoot)
            let destination = target.url(gameRoot: gameRoot, dataRoot: dataRoot)
            guard FileManager.default.fileExists(atPath: destination.path) else { continue }
            guard try RuntimeSecurity.sha256(of: destination) == entry.sha256 else {
                throw ModManagerError.externalFileChanged(target.displayPath)
            }
        }
    }

    private struct BackupInfo {
        let path: String?
        let originalHash: String?
    }

    private func prepareBackup(
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

    private func replace(source: URL, destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func synchronizePlugins(
        _ plugins: [BethesdaPlugin],
        mods: [InstalledMod],
        gameRoot: URL,
        at url: URL?,
        gameDirectory: URL,
        old: ModDeploymentManifest,
        next: inout ModDeploymentManifest,
        transactionURL: URL
    ) throws {
        guard let url else {
            if mods.contains(where: { !$0.plugins.isEmpty && $0.enabled }) { throw ModManagerError.pluginsFileUnavailable }
            return
        }
        let fileManager = FileManager.default
        let data = SkyrimModAdapter.pluginsFileData(plugins: plugins, mods: mods, gameRoot: gameRoot)
        // plugins.txt is a generated output. The active profile is the source
        // of truth, so restore its plugin list during deployment even if a
        // launcher or another tool changed the output file.
        if next.pluginFileBackup == nil, fileManager.fileExists(atPath: url.path) {
            let originalHash = try RuntimeSecurity.sha256(of: url)
            let backupRelative = "Backups/\(UUID().uuidString)-plugins.txt"
            let backup = append(backupRelative, to: gameDirectory)
            try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: url, to: backup)
            next.pluginFileBackup = backupRelative
            next.pluginFileOriginalHash = originalHash
        }
        let temporary = transactionURL.appending(path: "plugins.txt")
        try fileManager.createDirectory(at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: temporary, options: .atomic)
        try replace(source: temporary, destination: url)
        next.pluginFilePath = url.standardizedFileURL.path
        next.pluginFileHash = try RuntimeSecurity.sha256(of: url)
    }
}
