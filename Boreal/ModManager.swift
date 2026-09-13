import Foundation

// MARK: - Mod domain

nonisolated enum ModArchiveFormat: String, Codable, CaseIterable, Sendable {
    case zip
    case sevenZip = "7z"
    case rar

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "zip": self = .zip
        case "7z": self = .sevenZip
        case "rar": self = .rar
        default: return nil
        }
    }
}

nonisolated enum BethesdaPluginType: String, Codable, CaseIterable, Sendable {
    case esm
    case esp
    case esl

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "esm": self = .esm
        case "esp": self = .esp
        case "esl": self = .esl
        default: return nil
        }
    }

    var fallbackClassification: BethesdaPluginClassification {
        switch self {
        case .esm: .master
        case .esp: .plugin
        case .esl: .light
        }
    }
}

nonisolated enum BethesdaPluginClassification: String, Codable, CaseIterable, Sendable {
    case plugin
    case master
    case light

    var displayName: String {
        switch self {
        case .plugin: "ESP"
        case .master: "Master"
        case .light: "Light"
        }
    }
}

nonisolated struct BethesdaPluginHeader: Hashable, Sendable {
    var flags: UInt32
    var classification: BethesdaPluginClassification
    var masters: [String]
}

nonisolated struct ModFile: Codable, Hashable, Sendable, Identifiable {
    var relativePath: String
    var sha256: String
    var size: Int64

    var id: String { relativePath }
}

nonisolated struct BethesdaPlugin: Codable, Hashable, Sendable, Identifiable {
    var filename: String
    var type: BethesdaPluginType
    var classification: BethesdaPluginClassification
    var masters: [String]
    var headerFlags: UInt32
    var headerParsed: Bool
    var enabled: Bool
    var loadOrder: Int
    var modID: UUID?

    init(
        filename: String,
        type: BethesdaPluginType,
        classification: BethesdaPluginClassification? = nil,
        masters: [String] = [],
        headerFlags: UInt32 = 0,
        headerParsed: Bool = false,
        enabled: Bool,
        loadOrder: Int,
        modID: UUID?
    ) {
        self.filename = filename
        self.type = type
        self.classification = classification ?? type.fallbackClassification
        self.masters = masters
        self.headerFlags = headerFlags
        self.headerParsed = headerParsed
        self.enabled = enabled
        self.loadOrder = loadOrder
        self.modID = modID
    }

    private enum CodingKeys: String, CodingKey {
        case filename, type, classification, masters, headerFlags, headerParsed, enabled, loadOrder, modID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decode(String.self, forKey: .filename)
        type = try container.decode(BethesdaPluginType.self, forKey: .type)
        classification = try container.decodeIfPresent(BethesdaPluginClassification.self, forKey: .classification) ?? type.fallbackClassification
        masters = try container.decodeIfPresent([String].self, forKey: .masters) ?? []
        headerFlags = try container.decodeIfPresent(UInt32.self, forKey: .headerFlags) ?? 0
        headerParsed = try container.decodeIfPresent(Bool.self, forKey: .headerParsed) ?? false
        enabled = try container.decode(Bool.self, forKey: .enabled)
        loadOrder = try container.decode(Int.self, forKey: .loadOrder)
        modID = try container.decodeIfPresent(UUID.self, forKey: .modID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filename, forKey: .filename)
        try container.encode(type, forKey: .type)
        try container.encode(classification, forKey: .classification)
        try container.encode(masters, forKey: .masters)
        try container.encode(headerFlags, forKey: .headerFlags)
        try container.encode(headerParsed, forKey: .headerParsed)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(loadOrder, forKey: .loadOrder)
        try container.encodeIfPresent(modID, forKey: .modID)
    }

    var displayType: String { classification.displayName }

    func withHeader(_ header: BethesdaPluginHeader?) -> BethesdaPlugin {
        guard let header else { return self }
        var value = self
        value.classification = header.classification
        value.masters = header.masters
        value.headerFlags = header.flags
        value.headerParsed = true
        return value
    }

    var id: String {
        "\(modID?.uuidString ?? "base"):\(filename.lowercased())"
    }
}

nonisolated struct InstalledMod: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var version: String?
    var enabled: Bool
    var priority: Int
    var archiveRelativePath: String?
    var stagingRelativePath: String
    var installedAt: Date
    var files: [ModFile]
    var plugins: [BethesdaPlugin]

    init(
        id: UUID = UUID(),
        name: String,
        version: String? = nil,
        enabled: Bool = true,
        priority: Int,
        archiveRelativePath: String? = nil,
        stagingRelativePath: String,
        installedAt: Date = .now,
        files: [ModFile],
        plugins: [BethesdaPlugin]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.enabled = enabled
        self.priority = priority
        self.archiveRelativePath = archiveRelativePath
        self.stagingRelativePath = stagingRelativePath
        self.installedAt = installedAt
        self.files = files
        self.plugins = plugins
    }
}

nonisolated struct ModConflict: Hashable, Sendable, Identifiable {
    let relativePath: String
    let modIDs: [UUID]
    let winnerModID: UUID

    var id: String { relativePath }
    var overriddenModIDs: [UUID] { modIDs.filter { $0 != winnerModID } }
}

nonisolated struct ModDeploymentFile: Codable, Hashable, Sendable {
    var path: String
    var owner: UUID
    var sha256: String
    var source: String
    var backup: String?
    var originalHash: String?
}

nonisolated struct ModDeploymentManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int = 1
    var gameID: UUID
    var deployedAt: Date?
    var profileFingerprint: String?
    var files: [String: ModDeploymentFile]
    var pluginFilePath: String?
    var pluginFileHash: String?
    var pluginFileBackup: String?
    var pluginFileOriginalHash: String?

    static func empty(gameID: UUID) -> ModDeploymentManifest {
        ModDeploymentManifest(gameID: gameID, deployedAt: nil, profileFingerprint: nil, files: [:])
    }
}

nonisolated struct ModMissingMaster: Hashable, Sendable, Identifiable {
    let plugin: String
    let master: String

    var id: String { "(plugin.lowercased())::(master.lowercased())" }
}

nonisolated struct ModValidationReport: Hashable, Sendable {
    let missingMasters: [ModMissingMaster]
    let invalidPluginHeaders: [String]
    let fullPluginCount: Int
    let lightPluginCount: Int

    static let fullPluginLimit = 254
    static let lightPluginLimit = 4096

    var exceedsFullPluginLimit: Bool { fullPluginCount > Self.fullPluginLimit }
    var exceedsLightPluginLimit: Bool { lightPluginCount > Self.lightPluginLimit }
    var isBlocking: Bool {
        !missingMasters.isEmpty || !invalidPluginHeaders.isEmpty || exceedsFullPluginLimit || exceedsLightPluginLimit
    }

    var blockingIssueCount: Int {
        missingMasters.count + invalidPluginHeaders.count
            + (exceedsFullPluginLimit ? 1 : 0)
            + (exceedsLightPluginLimit ? 1 : 0)
    }

    static func make(mods: [InstalledMod], plugins: [BethesdaPlugin]) -> ModValidationReport {
        let enabledModIDs = Set(mods.filter(\.enabled).map(\.id))
        let active = plugins.filter { plugin in
            plugin.enabled && (plugin.modID == nil || enabledModIDs.contains(plugin.modID!))
        }
        let available = Set(active.map { $0.filename.lowercased() })
        let missing = active.flatMap { plugin in
            plugin.masters
                .filter { !available.contains($0.lowercased()) }
                .map { ModMissingMaster(plugin: plugin.filename, master: $0) }
        }
        return ModValidationReport(
            missingMasters: missing.sorted {
                if $0.plugin.caseInsensitiveCompare($1.plugin) != .orderedSame {
                    return $0.plugin.localizedStandardCompare($1.plugin) == .orderedAscending
                }
                return $0.master.localizedStandardCompare($1.master) == .orderedAscending
            },
            invalidPluginHeaders: active
                .filter { !$0.headerParsed }
                .map(\.filename)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            fullPluginCount: active.filter { $0.classification != .light }.count,
            lightPluginCount: active.filter { $0.classification == .light }.count
        )
    }
}

nonisolated struct ModDeploymentHealth: Hashable, Sendable {
    let deployedModCount: Int
    let managedFileCount: Int
    let pluginsSynchronized: Bool
    let vanillaFilesProtected: Bool
    let externalChanges: [String]
    let validation: ModValidationReport
    let pendingChanges: Bool
    let lastDeployment: Date?

    var needsAttention: Bool {
        pendingChanges || !externalChanges.isEmpty || !pluginsSynchronized || !vanillaFilesProtected || validation.isBlocking
    }
}

nonisolated struct ModProfileDescriptor: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
}

nonisolated struct ModGameState: Hashable, Sendable {
    let gameID: UUID
    var profileID: String
    var profileName: String
    var mods: [InstalledMod]
    var plugins: [BethesdaPlugin]
    var deployment: ModDeploymentManifest

    var conflicts: [ModConflict] {
        ModConflictResolver.conflicts(in: mods)
    }

    var activeModCount: Int { mods.filter(\.enabled).count }
    var conflictCount: Int { conflicts.count }
    var validation: ModValidationReport { ModValidationReport.make(mods: mods, plugins: plugins) }
    var pendingChanges: Bool {
        deployment.profileFingerprint != ModProfileFingerprint.make(mods: mods, plugins: plugins)
    }
}

nonisolated struct ModInstallPreview: Identifiable, Sendable {
    let id: UUID
    let gameID: UUID
    let archiveURL: URL
    let archiveName: String
    let format: ModArchiveFormat
    let detectedRoot: String
    let fileCount: Int
    let pluginCount: Int

    init(
        id: UUID = UUID(),
        gameID: UUID,
        archiveURL: URL,
        archiveName: String,
        format: ModArchiveFormat,
        detectedRoot: String,
        fileCount: Int,
        pluginCount: Int
    ) {
        self.id = id
        self.gameID = gameID
        self.archiveURL = archiveURL
        self.archiveName = archiveName
        self.format = format
        self.detectedRoot = detectedRoot
        self.fileCount = fileCount
        self.pluginCount = pluginCount
    }
}

nonisolated enum ModManagerError: LocalizedError, Sendable {
    case unsupportedArchive(URL)
    case archiveToolUnavailable(ModArchiveFormat)
    case archiveToolFailed(String)
    case unsafeArchivePath(String)
    case extractedArchiveEmpty
    case dataRootNotFound(URL)
    case symbolicLinkNotAllowed(URL)
    case unsupportedGame(String)
    case gameRootUnavailable
    case invalidRelativePath(String)
    case duplicatePath(String)
    case stagedFileChanged(String)
    case externalFileChanged(String)
    case missingPluginMasters([ModMissingMaster])
    case invalidPluginHeaders([String])
    case pluginLimitExceeded(full: Int, light: Int)
    case invalidProfileName
    case profileAlreadyExists(String)
    case deploymentFailed(String)
    case pluginsFileUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedArchive(let url):
            "Boreal supports ZIP, RAR and 7z mod archives. This file is not a supported archive: \(url.lastPathComponent)."
        case .archiveToolUnavailable(let format):
            format == .zip
                ? "The system ZIP extraction tool is unavailable."
                : "A 7-Zip-compatible command is required to extract \(format.rawValue.uppercased()) archives. Install 7-Zip and try again."
        case .archiveToolFailed(let detail):
            "Boreal couldn’t read the mod archive: \(detail)"
        case .unsafeArchivePath(let path):
            "The mod archive contains an unsafe path: \(path)"
        case .extractedArchiveEmpty:
            "The mod archive did not contain any files."
        case .dataRootNotFound(let url):
            "Boreal couldn’t find a Skyrim Data root in the extracted archive: \(url.lastPathComponent)."
        case .symbolicLinkNotAllowed(let url):
            "Symbolic links are not allowed in a mod archive: \(url.lastPathComponent)."
        case .unsupportedGame(let name):
            "Boreal’s mod manager does not support \(name) yet. Skyrim Special Edition is supported in this version."
        case .gameRootUnavailable:
            "The installed game folder is unavailable. Connect the game volume before managing mods."
        case .invalidRelativePath(let path):
            "The mod contains an invalid relative path: \(path)"
        case .duplicatePath(let path):
            "The mod contains duplicate files that differ only by letter case: \(path)"
        case .stagedFileChanged(let path):
            "A staged mod file changed outside Boreal, so deployment was stopped: \(path)"
        case .externalFileChanged(let path):
            "A file managed by Boreal changed outside the mod manager, so deployment was stopped: \(path)"
        case .missingPluginMasters(let missing):
            "Deployment is blocked because enabled plugins have missing or disabled masters: \(missing.map { "\($0.plugin) requires \($0.master)" }.joined(separator: "; "))"
        case .invalidPluginHeaders(let plugins):
            "Deployment is blocked because Boreal could not parse these plugin headers: \(plugins.joined(separator: ", "))"
        case .pluginLimitExceeded(let full, let light):
            "Deployment is blocked because Skyrim's plugin limit would be exceeded: Full \(full)/\(ModValidationReport.fullPluginLimit), Light \(light)/\(ModValidationReport.lightPluginLimit)."
        case .invalidProfileName:
            "Choose a profile name containing at least one letter or number."
        case .profileAlreadyExists(let name):
            "A mod profile named \(name) already exists."
        case .deploymentFailed(let detail):
            "Boreal couldn’t deploy the selected mods: \(detail)"
        case .pluginsFileUnavailable:
            "Boreal couldn’t locate Skyrim’s plugins.txt inside the selected Wine environment."
        }
    }
}

// MARK: - Skyrim adapter

nonisolated enum SkyrimModAdapter {
    static let supportedDataDirectories: Set<String> = [
        "meshes", "textures", "scripts", "interface", "sound", "music", "strings", "skse"
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
    /// Existing user directories are preferred; a fresh managed prefix uses
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
        for user in userNames {
            let url = users
                .appending(path: user, directoryHint: .isDirectory)
                .appending(path: "AppData/Local/Skyrim Special Edition", directoryHint: .isDirectory)
                .appending(path: "plugins.txt")
            if fileManager.fileExists(atPath: url.path) || fileManager.fileExists(atPath: url.deletingLastPathComponent().path) {
                return url
            }
        }
        return nil
    }

    static func pluginType(for filename: String) -> BethesdaPluginType? {
        BethesdaPluginType(fileExtension: URL(fileURLWithPath: filename).pathExtension)
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
              let flags = readUInt32(data, offset: 8) else { return nil }

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
               !masters.contains(where: { $0.caseInsensitiveCompare(master) == .orderedSame }) {
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

nonisolated enum ModConflictResolver {
    static func conflicts(in mods: [InstalledMod]) -> [ModConflict] {
        var owners: [String: [(mod: InstalledMod, file: ModFile)]] = [:]
        for mod in mods where mod.enabled {
            for file in mod.files {
                owners[file.relativePath.lowercased(), default: []].append((mod, file))
            }
        }
        return owners.compactMap { key, values in
            guard values.count > 1,
                  let winner = values.max(by: { $0.mod.priority < $1.mod.priority }) else { return nil }
            let ordered = values.sorted { $0.mod.priority < $1.mod.priority }
            return ModConflict(
                relativePath: ordered.last?.file.relativePath ?? key,
                modIDs: ordered.map { $0.mod.id },
                winnerModID: winner.mod.id
            )
        }.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }
}

nonisolated enum ModProfileFingerprint {
    static func make(mods: [InstalledMod], plugins: [BethesdaPlugin]) -> String {
        let modPart = mods.sorted { $0.priority < $1.priority }.map { mod in
            let files = mod.files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
                .map { "\($0.relativePath)=\($0.sha256)" }
                .joined(separator: ";")
            return "\(mod.id.uuidString):\(mod.enabled ? 1 : 0):\(mod.priority):\(files)"
        }.joined(separator: "|")
        let pluginPart = plugins.sorted { $0.loadOrder < $1.loadOrder }.map {
            "\($0.filename.lowercased()):\($0.enabled ? 1 : 0):\($0.loadOrder):\($0.modID?.uuidString ?? "base"):\($0.classification.rawValue):\($0.masters.map { $0.lowercased() }.joined(separator: ","))"
        }.joined(separator: "|")
        return modPart + "##" + pluginPart
    }
}

nonisolated struct ModProfile: Codable, Sendable {
    var schemaVersion: Int = 2
    var gameID: UUID
    var name: String
    var mods: [InstalledMod]
    var plugins: [BethesdaPlugin]
    var updatedAt: Date

    init(
        gameID: UUID,
        name: String,
        mods: [InstalledMod],
        plugins: [BethesdaPlugin],
        updatedAt: Date = .now
    ) {
        self.gameID = gameID
        self.name = name
        self.mods = mods
        self.plugins = plugins
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, gameID, name, mods, plugins, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        gameID = try container.decode(UUID.self, forKey: .gameID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default"
        mods = try container.decode([InstalledMod].self, forKey: .mods)
        plugins = try container.decode([BethesdaPlugin].self, forKey: .plugins)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

nonisolated struct ModManager: Sendable {
    let rootURL: URL

    init(applicationSupportURL: URL) {
        rootURL = applicationSupportURL.appending(path: "Mods", directoryHint: .isDirectory)
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
            let dataRoot = try findDataRoot(in: extracted)
            let files = try contentFiles(in: dataRoot)
            let plugins = files.compactMap { SkyrimModAdapter.pluginType(for: $0.lastPathComponent) }
            return ModInstallPreview(
                gameID: gameID,
                archiveURL: pendingURL,
                archiveName: archive.lastPathComponent,
                format: format,
                detectedRoot: relativeDisplayPath(dataRoot, from: extracted),
                fileCount: files.count,
                pluginCount: plugins.count
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
        let gameURL = gameURL(for: gameID)
        let resolvedProfileID = normalizedProfileID(profileID ?? activeProfileID(for: gameID))
        let profileURL = profileURL(for: gameID, profileID: resolvedProfileID)
        let deploymentURL = gameURL.appending(path: "deployment.json")
        let profile = try read(ModProfile.self, at: profileURL)
        let deployment = (try? read(ModDeploymentManifest.self, at: deploymentURL)) ?? .empty(gameID: gameID)
        var mods = profile?.mods ?? scanManifests(in: gameURL)
        mods = mods.sorted { $0.priority == $1.priority ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.priority < $1.priority }
        for index in mods.indices { mods[index].priority = index }

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
            deployment: resolvedDeployment
        )
    }

    func install(
        preview: ModInstallPreview,
        gameRoot: URL?,
        pluginsFile: URL?,
        profileID: String = "default"
    ) throws -> ModGameState {
        let fileManager = FileManager.default
        let format = try archiveFormat(for: preview.archiveURL)
        let extracted = try extract(preview.archiveURL, format: format)
        defer { try? fileManager.removeItem(at: extracted) }
        let dataRoot = try findDataRoot(in: extracted)
        let sourceFiles = try contentFiles(in: dataRoot)
        guard !sourceFiles.isEmpty else { throw ModManagerError.extractedArchiveEmpty }

        let gameDirectory = gameURL(for: preview.gameID)
        let stagingID = UUID()
        let stagingDirectory = gameDirectory.appending(path: "Staging/\(stagingID.uuidString)/files", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        do {
            var files: [ModFile] = []
            var seen: Set<String> = []
            for source in sourceFiles {
                let relative = try relativePath(of: source, from: dataRoot)
                let key = relative.lowercased()
                guard seen.insert(key).inserted else { throw ModManagerError.duplicatePath(relative) }
                let destination = append(relative, to: stagingDirectory)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: destination)
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw ModManagerError.symbolicLinkNotAllowed(source) }
                files.append(ModFile(
                    relativePath: relative,
                    sha256: try RuntimeSecurity.sha256(of: source),
                    size: Int64(values.fileSize ?? 0)
                ))
            }

            let current = try load(gameID: preview.gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: profileID)
            let modID = stagingID
            let archiveDirectory = gameDirectory.appending(path: "Archives", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let archiveName = "\(modID.uuidString)-\(preview.archiveName)"
            let archiveDestination = archiveDirectory.appending(path: archiveName)
            try fileManager.copyItem(at: preview.archiveURL, to: archiveDestination)

            let pluginRecords = files.compactMap { file -> BethesdaPlugin? in
                guard let type = SkyrimModAdapter.pluginType(for: file.relativePath) else { return nil }
                let source = append(file.relativePath, to: stagingDirectory)
                let header = SkyrimModAdapter.inspectPlugin(at: source)
                return BethesdaPlugin(
                    filename: URL(fileURLWithPath: file.relativePath).lastPathComponent,
                    type: type,
                    classification: header?.classification,
                    masters: header?.masters ?? [],
                    headerFlags: header?.flags ?? 0,
                    headerParsed: header != nil,
                    enabled: true,
                    loadOrder: current.plugins.count,
                    modID: modID
                )
            }
            let mod = InstalledMod(
                id: modID,
                name: URL(fileURLWithPath: preview.archiveName).deletingPathExtension().lastPathComponent,
                priority: current.mods.count,
                archiveRelativePath: "Archives/\(archiveName)",
                stagingRelativePath: "Staging/\(modID.uuidString)",
                files: files,
                plugins: pluginRecords
            )
            var mods = current.mods
            mods.append(mod)
            var plugins = current.plugins
            plugins.append(contentsOf: pluginRecords)
            try saveProfile(
                gameID: preview.gameID,
                profileID: current.profileID,
                profileName: current.profileName,
                mods: mods,
                plugins: plugins,
                gameDirectory: gameDirectory
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
        let old = (try? read(ModDeploymentManifest.self, at: gameDirectory.appending(path: "deployment.json"))) ?? .empty(gameID: state.gameID)

        let validation = state.validation
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
        try validateManagedFiles(old.files, dataRoot: dataRoot)
        try preflightExternalChanges(old.files, dataRoot: dataRoot)
        if let oldPluginPath = old.pluginFilePath,
           let oldPluginHash = old.pluginFileHash,
           let currentPluginURL = pluginsFile,
           oldPluginPath == currentPluginURL.standardizedFileURL.path,
           fileManager.fileExists(atPath: currentPluginURL.path),
           try RuntimeSecurity.sha256(of: currentPluginURL) != oldPluginHash {
            throw ModManagerError.externalFileChanged(currentPluginURL.path)
        }

        let transactionURL = gameDirectory.appending(path: ".transactions/\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: transactionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transactionURL) }
        let changedPaths = Set(old.files.values.map(\.path)).union(resolved.values.map { $0.file.relativePath })
        var transactionOriginals: [String: URL] = [:]
        var transactionMissingPaths: Set<String> = []
        var transactionPluginOriginal: URL?
        var transactionPluginWasMissing = false
        do {
            for path in changedPaths {
                let destination = append(path, to: dataRoot)
                guard fileManager.fileExists(atPath: destination.path) else {
                    transactionMissingPaths.insert(path)
                    continue
                }
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw ModManagerError.deploymentFailed("The destination is not a regular file: \(path)")
                }
                let backup = append(path, to: transactionURL)
                try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: destination, to: backup)
                transactionOriginals[path] = backup
            }

            var nextFiles: [String: ModDeploymentFile] = [:]
            for (key, resolvedFile) in resolved {
                let destination = append(resolvedFile.file.relativePath, to: dataRoot)
                let source = append(resolvedFile.file.relativePath, to: append(resolvedFile.mod.stagingRelativePath + "/files", to: gameDirectory))
                let actualSourceHash = try RuntimeSecurity.sha256(of: source)
                guard actualSourceHash == resolvedFile.file.sha256 else {
                    throw ModManagerError.stagedFileChanged(resolvedFile.file.relativePath)
                }
                let oldFile = old.files.values.first { $0.path.caseInsensitiveCompare(resolvedFile.file.relativePath) == .orderedSame }
                let backupInfo = try prepareBackup(
                    destination: destination,
                    dataRoot: dataRoot,
                    gameDirectory: gameDirectory,
                    path: resolvedFile.file.relativePath,
                    oldFile: oldFile
                )
                try replace(source: source, destination: destination)
                nextFiles[key] = ModDeploymentFile(
                    path: resolvedFile.file.relativePath,
                    owner: resolvedFile.mod.id,
                    sha256: resolvedFile.file.sha256,
                    source: "\(resolvedFile.mod.stagingRelativePath)/files/\(resolvedFile.file.relativePath)",
                    backup: backupInfo.path,
                    originalHash: backupInfo.originalHash
                )
            }

            for (_, oldFile) in old.files where resolved[oldFile.path.lowercased()] == nil {
                let path = oldFile.path
                let destination = append(path, to: dataRoot)
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
                profileFingerprint: ModProfileFingerprint.make(mods: state.mods, plugins: state.plugins),
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
                state.plugins,
                mods: state.mods,
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
                plugins: state.plugins,
                gameDirectory: gameDirectory
            )
            return try load(gameID: state.gameID, gameRoot: gameRoot, pluginsFile: pluginsFile, profileID: state.profileID)
        } catch {
            for (path, original) in transactionOriginals {
                let destination = append(path, to: dataRoot)
                try? fileManager.removeItem(at: destination)
                try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: original, to: destination)
            }
            for path in transactionMissingPaths {
                try? fileManager.removeItem(at: append(path, to: dataRoot))
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

    func activateProfile(_ profileID: String, for gameID: UUID) throws {
        let normalized = normalizedProfileID(profileID)
        let url = activeProfileURL(for: gameID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(normalized.utf8).write(to: url, options: .atomic)
    }

    func deploymentHealth(
        for state: ModGameState,
        gameRoot: URL?,
        pluginsFile: URL?
    ) -> ModDeploymentHealth {
        let fileManager = FileManager.default
        var externalChanges: [String] = []
        if let dataRoot = gameRoot.flatMap({ SkyrimModAdapter.dataRoot(for: $0) }) {
            for entry in state.deployment.files.values {
                let destination = append(entry.path, to: dataRoot)
                guard fileManager.fileExists(atPath: destination.path),
                      (try? RuntimeSecurity.sha256(of: destination)) == entry.sha256 else {
                    externalChanges.append(entry.path)
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
            pluginsSynchronized = (try? RuntimeSecurity.sha256(of: pluginsFile)) == hash
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
        let normalizedPlugins = plugins.enumerated().map { index, plugin -> BethesdaPlugin in
            var value = plugin
            value.loadOrder = index
            return value
        }
        let profile = ModProfile(gameID: gameID, name: profileName, mods: normalizedMods, plugins: normalizedPlugins, updatedAt: .now)
        try saveJSON(profile, at: profileURL(for: gameID, profileID: profileID))
        for mod in normalizedMods {
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
        var result = plugins.filter { $0.modID == nil || validModIDs.contains($0.modID!) }
        let existingKeys = Set(result.map { "\($0.modID?.uuidString ?? "base"):\($0.filename.lowercased())" })
        for mod in mods {
            for plugin in mod.plugins {
                let key = "\(mod.id.uuidString):\(plugin.filename.lowercased())"
                guard !existingKeys.contains(key) else { continue }
                result.append(plugin)
            }
        }
        for index in result.indices { result[index].loadOrder = index }
        return result
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
                source = append(file.relativePath, to: append(mod.stagingRelativePath + "/files", to: gameDirectory))
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

    private func resolvedFiles(for mods: [InstalledMod], gameDirectory: URL) throws -> [String: ResolvedFile] {
        var result: [String: ResolvedFile] = [:]
        for mod in mods.sorted(by: { $0.priority < $1.priority }) where mod.enabled {
            for file in mod.files {
                guard isSafeRelativePath(file.relativePath) else { throw ModManagerError.invalidRelativePath(file.relativePath) }
                result[file.relativePath.lowercased()] = ResolvedFile(mod: mod, file: file)
            }
        }
        return result
    }

    private func validateManagedFiles(_ files: [String: ModDeploymentFile], dataRoot: URL) throws {
        for path in files.values.map(\.path) {
            guard isSafeRelativePath(path) else { throw ModManagerError.invalidRelativePath(path) }
            let destination = append(path, to: dataRoot)
            if FileManager.default.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else { throw ModManagerError.deploymentFailed("The managed destination is unsafe: \(path)") }
            }
        }
    }

    private func preflightExternalChanges(_ files: [String: ModDeploymentFile], dataRoot: URL) throws {
        for entry in files.values {
            let path = entry.path
            let destination = append(path, to: dataRoot)
            guard FileManager.default.fileExists(atPath: destination.path) else { continue }
            guard try RuntimeSecurity.sha256(of: destination) == entry.sha256 else {
                throw ModManagerError.externalFileChanged(path)
            }
        }
    }

    private struct BackupInfo {
        let path: String?
        let originalHash: String?
    }

    private func prepareBackup(
        destination: URL,
        dataRoot: URL,
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
        let effective = plugins.sorted { $0.loadOrder < $1.loadOrder }.filter { plugin in
            guard let modID = plugin.modID else { return true }
            return mods.first(where: { $0.id == modID })?.enabled == true
        }
        let text = effective.map { "\($0.enabled ? "*" : "")\($0.filename)" }.joined(separator: "\n") + (effective.isEmpty ? "" : "\n")
        let data = Data(text.utf8)
        if fileManager.fileExists(atPath: url.path),
           old.pluginFilePath == url.standardizedFileURL.path,
           let oldHash = old.pluginFileHash {
            let currentHash = try RuntimeSecurity.sha256(of: url)
            guard currentHash == oldHash else { throw ModManagerError.externalFileChanged(url.path) }
        }
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
