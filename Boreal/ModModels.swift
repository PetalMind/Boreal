import Foundation

// MARK: - Mod domain

nonisolated enum ModArchiveFormat: String, Codable, CaseIterable, Sendable {
    case zip
    case sevenZip = "7z"
    case rar
    case dzip
    /// A standalone Unreal PAK is copied as a mod payload instead of extracted.
    /// This format is used only by the GTA San Andreas — Definitive Edition adapter.
    case loosePak = "pak"

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "zip": self = .zip
        case "7z": self = .sevenZip
        case "rar": self = .rar
        case "dzip": self = .dzip
        default: return nil
        }
    }
}

nonisolated enum ModGameAdapter: String, Codable, CaseIterable, Sendable, Hashable {
    case skyrimSpecialEdition
    case gtaSanAndreas
    case gtaSanAndreasDefinitiveEdition
    case dragonAgeOrigins
    case witcher2
    case witcher3

    var displayName: String {
        switch self {
        case .skyrimSpecialEdition: "Skyrim Special Edition"
        case .gtaSanAndreas: "GTA San Andreas"
        case .gtaSanAndreasDefinitiveEdition: "GTA San Andreas — Definitive Edition"
        case .dragonAgeOrigins: "Dragon Age: Origins"
        case .witcher2: "The Witcher 2: Assassins of Kings"
        case .witcher3: "The Witcher 3: Wild Hunt"
        }
    }
}

nonisolated enum ModContentType: String, Codable, CaseIterable, Sendable, Hashable {
    case modLoader
    case asiPlugin
    case cleo
    case coreComponent
    case rootOverlay
    case unrealPak
    case config
    case dragonAgeOverride
    case dragonAgeDazip
    case witcher2CookedPC
    case witcher2UserContent
    case witcher3Mod
    case witcher3DLC
    case witcher3GameFiles
    case skyrimData
    case skyrimScriptExtender
    case manual
    case unknown

    var displayName: String {
        switch self {
        case .modLoader: "Mod Loader"
        case .asiPlugin: "ASI Plugin"
        case .cleo: "CLEO Script"
        case .coreComponent: "Core Component"
        case .rootOverlay: "Root Overlay"
        case .unrealPak: "Unreal Pak"
        case .config: "Configuration"
        case .dragonAgeOverride: "Dragon Age Override"
        case .dragonAgeDazip: "Dragon Age DAZIP"
        case .witcher2CookedPC: "The Witcher 2 CookedPC"
        case .witcher2UserContent: "The Witcher 2 User Content"
        case .witcher3Mod: "The Witcher 3 Mod Folder"
        case .witcher3DLC: "The Witcher 3 DLC Folder"
        case .witcher3GameFiles: "The Witcher 3 Game Files"
        case .skyrimData: "Skyrim Data Files"
        case .skyrimScriptExtender: "Skyrim Script Extender"
        case .manual: "Manual Installer"
        case .unknown: "Unknown"
        }
    }
}

nonisolated enum ModInstallationSource: String, Codable, CaseIterable, Sendable, Hashable {
    case boreal
    case external

    var displayName: String {
        switch self {
        case .boreal: "Managed by Boreal"
        case .external: "Detected outside Boreal"
        }
    }
}

nonisolated enum ModDeployStrategy: String, Codable, CaseIterable, Sendable, Hashable {
    case modLoader
    case rootOverlay
    case scripts
    case cleo
    case manual
    case unrealPaks
    case dragonAgeOverride
    case dragonAgeDazip
    case witcher2CookedPC
    case witcher2UserContent
    case witcher3GameRoot
    case skyrimDataFolder
    case skyrimScriptExtender

    var displayName: String {
        switch self {
        case .modLoader: "Mod Loader"
        case .rootOverlay: "Game root"
        case .scripts: "Scripts"
        case .cleo: "CLEO"
        case .manual: "Manual"
        case .unrealPaks: "Unreal Paks"
        case .dragonAgeOverride: "Dragon Age Override"
        case .dragonAgeDazip: "Dragon Age DAZIP"
        case .witcher2CookedPC: "CookedPC"
        case .witcher2UserContent: "User Content"
        case .witcher3GameRoot: "The Witcher 3 Game Folder"
        case .skyrimDataFolder: "Skyrim Data Folder"
        case .skyrimScriptExtender: "Game Folder + Skyrim Data"
        }
    }
}

nonisolated enum ModRuntimeCompatibility: String, Codable, CaseIterable, Sendable, Hashable {
    case ready
    case missingComponents
    case unknownExecutableVersion
    case unsupportedExecutable

    var displayName: String {
        switch self {
        case .ready: "Ready for modding"
        case .missingComponents: "Runtime components missing"
        case .unknownExecutableVersion: "Executable version not verified"
        case .unsupportedExecutable: "Unsupported executable"
        }
    }
}

nonisolated struct ModRuntimeState: Codable, Hashable, Sendable {
    let adapter: ModGameAdapter
    let executablePath: String?
    let executableVersion: String?
    let executableHash: String?
    let asiLoaderInstalled: Bool
    let modLoaderInstalled: Bool
    let cleoInstalled: Bool
    let compatibility: ModRuntimeCompatibility

    var isReady: Bool { compatibility == .ready }

    var installedComponentCount: Int {
        [asiLoaderInstalled, modLoaderInstalled, cleoInstalled].filter { $0 }.count
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
    /// Original staged path retained when a legacy Witcher 3 archive wrapper
    /// is flattened to the directory layout the game actually loads.
    var stagedSourcePath: String? = nil
    /// Skyrim SKSE packages also contain files installed beside SkyrimSE.exe.
    /// Existing profiles omit this field and continue to target Data.
    var destinationRoot: ModFileDestinationRoot = .data

    var id: String { destinationRoot.key(for: relativePath) }
    var stagedPath: String { stagedSourcePath ?? relativePath }

    private enum CodingKeys: String, CodingKey {
        case relativePath, sha256, size, stagedSourcePath, destinationRoot
    }

    init(
        relativePath: String,
        sha256: String,
        size: Int64,
        stagedSourcePath: String? = nil,
        destinationRoot: ModFileDestinationRoot = .data
    ) {
        self.relativePath = relativePath
        self.sha256 = sha256
        self.size = size
        self.stagedSourcePath = stagedSourcePath
        self.destinationRoot = destinationRoot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        sha256 = try container.decode(String.self, forKey: .sha256)
        size = try container.decode(Int64.self, forKey: .size)
        stagedSourcePath = try container.decodeIfPresent(String.self, forKey: .stagedSourcePath)
        destinationRoot = try container.decodeIfPresent(ModFileDestinationRoot.self, forKey: .destinationRoot) ?? .data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(sha256, forKey: .sha256)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(stagedSourcePath, forKey: .stagedSourcePath)
        try container.encode(destinationRoot, forKey: .destinationRoot)
    }
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
    var id: UUID
    var name: String
    var version: String?
    var enabled: Bool
    var priority: Int
    var archiveRelativePath: String?
    var stagingRelativePath: String
    var installedAt: Date
    var files: [ModFile]
    var plugins: [BethesdaPlugin]
    var contentType: ModContentType
    var deployStrategy: ModDeployStrategy
    var requirements: [String]
    var warnings: [String]
    var installationSource: ModInstallationSource
    var detectionKey: String?

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
        plugins: [BethesdaPlugin],
        contentType: ModContentType = .unknown,
        deployStrategy: ModDeployStrategy = .modLoader,
        requirements: [String] = [],
        warnings: [String] = [],
        installationSource: ModInstallationSource = .boreal,
        detectionKey: String? = nil
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
        self.contentType = contentType
        self.deployStrategy = deployStrategy
        self.requirements = requirements
        self.warnings = warnings
        self.installationSource = installationSource
        self.detectionKey = detectionKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, enabled, priority, archiveRelativePath, stagingRelativePath
        case installedAt, files, plugins, contentType, deployStrategy, requirements, warnings
        case installationSource, detectionKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        priority = try container.decode(Int.self, forKey: .priority)
        archiveRelativePath = try container.decodeIfPresent(String.self, forKey: .archiveRelativePath)
        stagingRelativePath = try container.decode(String.self, forKey: .stagingRelativePath)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        files = try container.decode([ModFile].self, forKey: .files)
        plugins = try container.decode([BethesdaPlugin].self, forKey: .plugins)
        contentType = try container.decodeIfPresent(ModContentType.self, forKey: .contentType) ?? .unknown
        deployStrategy = try container.decodeIfPresent(ModDeployStrategy.self, forKey: .deployStrategy) ?? .modLoader
        requirements = try container.decodeIfPresent([String].self, forKey: .requirements) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        installationSource = try container.decodeIfPresent(ModInstallationSource.self, forKey: .installationSource) ?? .boreal
        detectionKey = try container.decodeIfPresent(String.self, forKey: .detectionKey)
    }

    var isExternallyDetected: Bool { installationSource == .external }
}

nonisolated enum ModConflictKind: String, Codable, CaseIterable, Sendable, Hashable {
    case directReplacement
    case potentialRuntime
    case mergeable

    var displayName: String {
        switch self {
        case .directReplacement: "Direct replacement"
        case .potentialRuntime: "Potential runtime conflict"
        case .mergeable: "Mergeable data"
        }
    }
}

nonisolated enum ModConflictResolutionStrategy: Sendable, Hashable {
    /// The Witcher 3 mod load order gives precedence to the earliest priority entry.
    case priorityFirst
    /// Boreal writes these files directly, so the last staged mod replaces earlier copies.
    case priorityLast
    /// Script Merger can combine some script and bundle conflicts, but needs a review for others.
    case scriptMerger
    /// The conflict is detected, but Boreal cannot identify a safe automatic resolution.
    case manual
}

nonisolated struct ModConflict: Hashable, Sendable, Identifiable {
    let relativePath: String
    let modIDs: [UUID]
    let winnerModID: UUID
    let kind: ModConflictKind
    let resolutionStrategy: ModConflictResolutionStrategy

    init(
        relativePath: String,
        modIDs: [UUID],
        winnerModID: UUID,
        kind: ModConflictKind = .directReplacement,
        resolutionStrategy: ModConflictResolutionStrategy = .manual
    ) {
        self.relativePath = relativePath
        self.modIDs = modIDs
        self.winnerModID = winnerModID
        self.kind = kind
        self.resolutionStrategy = resolutionStrategy
    }

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
    var destinationRoot: ModFileDestinationRoot = .data

    private enum CodingKeys: String, CodingKey {
        case path, owner, sha256, source, backup, originalHash, destinationRoot
    }

    init(
        path: String,
        owner: UUID,
        sha256: String,
        source: String,
        backup: String?,
        originalHash: String?,
        destinationRoot: ModFileDestinationRoot = .data
    ) {
        self.path = path
        self.owner = owner
        self.sha256 = sha256
        self.source = source
        self.backup = backup
        self.originalHash = originalHash
        self.destinationRoot = destinationRoot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        owner = try container.decode(UUID.self, forKey: .owner)
        sha256 = try container.decode(String.self, forKey: .sha256)
        source = try container.decode(String.self, forKey: .source)
        backup = try container.decodeIfPresent(String.self, forKey: .backup)
        originalHash = try container.decodeIfPresent(String.self, forKey: .originalHash)
        destinationRoot = try container.decodeIfPresent(ModFileDestinationRoot.self, forKey: .destinationRoot) ?? .data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(owner, forKey: .owner)
        try container.encode(sha256, forKey: .sha256)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(backup, forKey: .backup)
        try container.encodeIfPresent(originalHash, forKey: .originalHash)
        try container.encode(destinationRoot, forKey: .destinationRoot)
    }
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
    /// Package directory names written to The Witcher 2 UserContent.ini by
    /// Boreal. Older manifests decode with an empty list.
    var managedUserContentPackages: [String] = []
    /// Mod directory sections Boreal owns in The Witcher 3 `mods.settings`.
    /// Older manifests decode with an empty list.
    var managedWitcher3ModFolders: [String] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, gameID, deployedAt, profileFingerprint, files
        case pluginFilePath, pluginFileHash, pluginFileBackup, pluginFileOriginalHash
        case managedUserContentPackages
        case managedWitcher3ModFolders
    }

    init(
        schemaVersion: Int = 1,
        gameID: UUID,
        deployedAt: Date?,
        profileFingerprint: String?,
        files: [String: ModDeploymentFile],
        pluginFilePath: String? = nil,
        pluginFileHash: String? = nil,
        pluginFileBackup: String? = nil,
        pluginFileOriginalHash: String? = nil,
        managedUserContentPackages: [String] = [],
        managedWitcher3ModFolders: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.gameID = gameID
        self.deployedAt = deployedAt
        self.profileFingerprint = profileFingerprint
        self.files = files
        self.pluginFilePath = pluginFilePath
        self.pluginFileHash = pluginFileHash
        self.pluginFileBackup = pluginFileBackup
        self.pluginFileOriginalHash = pluginFileOriginalHash
        self.managedUserContentPackages = managedUserContentPackages
        self.managedWitcher3ModFolders = managedWitcher3ModFolders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        gameID = try container.decode(UUID.self, forKey: .gameID)
        deployedAt = try container.decodeIfPresent(Date.self, forKey: .deployedAt)
        profileFingerprint = try container.decodeIfPresent(String.self, forKey: .profileFingerprint)
        files = try container.decode([String: ModDeploymentFile].self, forKey: .files)
        pluginFilePath = try container.decodeIfPresent(String.self, forKey: .pluginFilePath)
        pluginFileHash = try container.decodeIfPresent(String.self, forKey: .pluginFileHash)
        pluginFileBackup = try container.decodeIfPresent(String.self, forKey: .pluginFileBackup)
        pluginFileOriginalHash = try container.decodeIfPresent(String.self, forKey: .pluginFileOriginalHash)
        managedUserContentPackages = try container.decodeIfPresent([String].self, forKey: .managedUserContentPackages) ?? []
        managedWitcher3ModFolders = try container.decodeIfPresent([String].self, forKey: .managedWitcher3ModFolders) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(gameID, forKey: .gameID)
        try container.encodeIfPresent(deployedAt, forKey: .deployedAt)
        try container.encodeIfPresent(profileFingerprint, forKey: .profileFingerprint)
        try container.encode(files, forKey: .files)
        try container.encodeIfPresent(pluginFilePath, forKey: .pluginFilePath)
        try container.encodeIfPresent(pluginFileHash, forKey: .pluginFileHash)
        try container.encodeIfPresent(pluginFileBackup, forKey: .pluginFileBackup)
        try container.encodeIfPresent(pluginFileOriginalHash, forKey: .pluginFileOriginalHash)
        try container.encode(managedUserContentPackages, forKey: .managedUserContentPackages)
        try container.encode(managedWitcher3ModFolders, forKey: .managedWitcher3ModFolders)
    }

    static func empty(gameID: UUID) -> ModDeploymentManifest {
        ModDeploymentManifest(gameID: gameID, deployedAt: nil, profileFingerprint: nil, files: [:])
    }
}

nonisolated struct ModMissingMaster: Hashable, Sendable, Identifiable {
    let plugin: String
    let master: String

    var id: String { "\(plugin.lowercased())::\(master.lowercased())" }
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
            invalidPluginHeaders:
                active
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
    var adapter: ModGameAdapter = .skyrimSpecialEdition
    var runtime: ModRuntimeState? = nil
    /// Optional secondary data root used by adapters whose mods live outside
    /// the game installation, such as The Witcher 2 UserContent directory.
    var auxiliaryRoot: URL? = nil

    var conflicts: [ModConflict] {
        adapter == .witcher3 ? Witcher3ConflictResolver.conflicts(in: mods) : ModConflictResolver.conflicts(in: mods)
    }

    var activeModCount: Int { mods.filter(\.enabled).count }
    var conflictCount: Int { conflicts.count }
    var validation: ModValidationReport { ModValidationReport.make(mods: mods, plugins: plugins) }
    var pendingChanges: Bool {
        let hasChangesToTrack =
            mods.contains(where: { !$0.isExternallyDetected })
            || (adapter == .witcher3 && !mods.isEmpty)
            || deployment.deployedAt != nil
        guard hasChangesToTrack else { return false }
        return deployment.profileFingerprint
            != ModProfileFingerprint.make(
                mods: mods,
                plugins: plugins,
                includeExternallyDetected: adapter == .witcher3
            )
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
    let adapter: ModGameAdapter
    let contentType: ModContentType
    let deployStrategy: ModDeployStrategy
    let requirements: [String]
    let warnings: [String]
    let canInstallAutomatically: Bool
    let totalSize: Int64
    let existingModID: UUID?
    let fomodPlan: FomodInstallPlan?
    let fomodSelection: FomodSelectionState

    var isUpdate: Bool { existingModID != nil }

    init(
        id: UUID = UUID(),
        gameID: UUID,
        archiveURL: URL,
        archiveName: String,
        format: ModArchiveFormat,
        detectedRoot: String,
        fileCount: Int,
        pluginCount: Int,
        adapter: ModGameAdapter = .skyrimSpecialEdition,
        contentType: ModContentType = .unknown,
        deployStrategy: ModDeployStrategy = .modLoader,
        requirements: [String] = [],
        warnings: [String] = [],
        canInstallAutomatically: Bool = true,
        totalSize: Int64 = 0,
        existingModID: UUID? = nil,
        fomodPlan: FomodInstallPlan? = nil,
        fomodSelection: FomodSelectionState = FomodSelectionState()
    ) {
        self.id = id
        self.gameID = gameID
        self.archiveURL = archiveURL
        self.archiveName = archiveName
        self.format = format
        self.detectedRoot = detectedRoot
        self.fileCount = fileCount
        self.pluginCount = pluginCount
        self.adapter = adapter
        self.contentType = contentType
        self.deployStrategy = deployStrategy
        self.requirements = requirements
        self.warnings = warnings
        self.canInstallAutomatically = canInstallAutomatically
        self.totalSize = totalSize
        self.existingModID = existingModID
        self.fomodPlan = fomodPlan
        self.fomodSelection = fomodSelection
    }

    func applyingFomodSelection(_ selection: FomodSelectionState) -> ModInstallPreview {
        ModInstallPreview(
            id: id,
            gameID: gameID,
            archiveURL: archiveURL,
            archiveName: archiveName,
            format: format,
            detectedRoot: detectedRoot,
            fileCount: fileCount,
            pluginCount: pluginCount,
            adapter: adapter,
            contentType: contentType,
            deployStrategy: deployStrategy,
            requirements: requirements,
            warnings: warnings,
            canInstallAutomatically: canInstallAutomatically,
            totalSize: totalSize,
            existingModID: existingModID,
            fomodPlan: fomodPlan,
            fomodSelection: selection
        )
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
    case dragonAgeDocumentsUnavailable
    case dragonAgeManifestUnavailable
    case dragonAgeArchiveInvalid(String)
    case witcher2DocumentsUnavailable
    case witcher2ArchiveInvalid(String)
    case witcher3DocumentsUnavailable
    case witcher3ArchiveInvalid(String)
    case invalidRelativePath(String)
    case duplicatePath(String)
    case stagedFileChanged(String)
    case deployedFileMismatch(String)
    case externalFileChanged(String)
    case missingPluginMasters([ModMissingMaster])
    case invalidPluginHeaders([String])
    case pluginLimitExceeded(full: Int, light: Int)
    case invalidProfileName
    case profileAlreadyExists(String)
    case deploymentFailed(String)
    case pluginsFileUnavailable
    case skyrimManualInstallationRequired([String])

    var errorDescription: String? {
        switch self {
        case .unsupportedArchive(let url):
            "Boreal supports ZIP, RAR, 7z, Witcher 2 DZIP and Dragon Age DAZIP mod archives. This file is not a supported archive: \(url.lastPathComponent)."
        case .archiveToolUnavailable(let format):
            if format == .loosePak {
                "A standalone Unreal PAK file is copied directly and does not use an archive extraction tool."
            } else if format == .dzip {
                "A standalone Witcher 2 DZIP file is copied directly and does not use an archive extraction tool."
            } else if format == .zip {
                "The system ZIP extraction tool is unavailable."
            } else {
                "A 7-Zip-compatible command is required to extract \(format.rawValue.uppercased()) archives. Install 7-Zip and try again."
            }
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
            "Boreal’s mod manager does not support \(name) yet."
        case .gameRootUnavailable:
            "The installed game folder is unavailable. Connect the game volume before managing mods."
        case .dragonAgeDocumentsUnavailable:
            "Boreal couldn’t locate Dragon Age: Origins’ Wine Documents folder. The game must be installed in a managed Wine environment with a writable drive_c/users folder."
        case .dragonAgeManifestUnavailable:
            "This Dragon Age: Origins DAZIP does not contain a readable Manifest.xml and cannot be registered safely."
        case .dragonAgeArchiveInvalid(let detail):
            "Boreal couldn’t interpret this Dragon Age: Origins mod archive: \(detail)"
        case .witcher2DocumentsUnavailable:
            "Boreal couldn’t locate The Witcher 2 user-content directory inside the managed Wine prefix."
        case .witcher2ArchiveInvalid(let detail):
            "Boreal couldn’t interpret this The Witcher 2 mod archive: \(detail)"
        case .witcher3DocumentsUnavailable:
            "Boreal couldn’t locate The Witcher 3 Documents folder inside the linked Wine prefix. It is needed to store mod enablement and load order."
        case .witcher3ArchiveInvalid(let detail):
            "Boreal couldn’t interpret this The Witcher 3 mod archive: \(detail)"
        case .invalidRelativePath(let path):
            "The mod contains an invalid relative path: \(path)"
        case .duplicatePath(let path):
            "The mod contains duplicate files that differ only by letter case: \(path)"
        case .stagedFileChanged(let path):
            "A staged mod file changed outside Boreal, so deployment was stopped: \(path)"
        case .deployedFileMismatch(let path):
            "Boreal deployed a mod file but its SHA-256 does not match the staged archive: \(path)"
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
        case .skyrimManualInstallationRequired(let details):
            "Boreal can’t install this Skyrim archive automatically. \(details.isEmpty ? "This archive needs an interactive or game-root installer." : details.joined(separator: " "))"
        }
    }
}

// MARK: - Skyrim adapter

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
