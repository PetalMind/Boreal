import Foundation

// MARK: - Domain model

/// A provider identity is one value instead of two independently optional
/// fields. The legacy `storeProvider`/`storeExternalID` properties remain on
/// the UI-facing models for backward compatibility and are bridged below.
nonisolated struct StoreReference: Codable, Hashable, Sendable {
    let provider: GameLibraryProvider
    let externalID: String
}

nonisolated enum InstallationLocation: Codable, Hashable, Sendable {
    case managed(relativePath: String)
    case external(path: String)
}

nonisolated enum ExecutableRole: String, Codable, CaseIterable, Hashable, Sendable {
    case game
    case launcher
    case configuration
    case benchmark
    case editor
    case server
    case utility
}

nonisolated enum ExecutableArchitecture: String, Codable, Hashable, Sendable {
    case x86
    case x86_64
}

/// The persisted installation lifecycle is deliberately independent from
/// `ApplicationStatus`. A game can have an installation record whose files
/// are currently missing, while its provider metadata and history remain
/// available to the library.
nonisolated enum InstallationState: String, Codable, Hashable, Sendable {
    case unknown
    case installing
    case installed
    case missing
    case volumeUnavailable
    case broken
    case uninstalled

    var representsAnInstallation: Bool {
        switch self {
        case .unknown, .uninstalled: false
        case .installing, .installed, .missing, .volumeUnavailable, .broken: true
        }
    }

    var isLaunchable: Bool { self == .installed }
}

/// Identity of the volume on which an installation was recorded. Absolute
/// paths alone are not sufficient for removable disks because another volume
/// can later appear at the same mount point.
nonisolated struct InstallationVolumeIdentity: Codable, Hashable, Sendable {
    var volumeUUID: String?
    var relativePath: String?
    var securityScopedBookmark: Data?

    static func capture(
        at url: URL,
        location: InstallationLocation
    ) -> InstallationVolumeIdentity {
        let volumeUUID: String? = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        let relativePath: String?
        switch location {
        case .managed(let path):
            relativePath = path
        case .external:
            let components = url.standardizedFileURL.pathComponents
            if components.count > 3, components[1] == "Volumes" {
                relativePath = "/" + components.dropFirst(3).joined(separator: "/")
            } else {
                relativePath = url.standardizedFileURL.path
            }
        }
        let bookmark: Data?
        if case .external = location {
            bookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } else {
            bookmark = nil
        }
        return InstallationVolumeIdentity(
            volumeUUID: volumeUUID,
            relativePath: relativePath,
            securityScopedBookmark: bookmark
        )
    }
}

nonisolated struct GameExecutable: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var relativePath: String
    var role: ExecutableRole
    var architecture: ExecutableArchitecture?

    init(
        id: UUID = UUID(),
        relativePath: String,
        role: ExecutableRole = .game,
        architecture: ExecutableArchitecture? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.role = role
        self.architecture = architecture
    }
}

nonisolated struct GameMetadata: Codable, Hashable, Sendable {
    var developer: String?
    var summary: String?
    var artworkPath: String?
    var customArtworkPath: String? = nil
    var customArtworkOriginalPath: String?
    var customArtworkCrop: ArtworkCrop?
    var portraitImageURL: String?
    var headerImageURL: String?
    var backgroundImageURL: String?
    var screenshotURLs: [String]?
    var videos: [StoreVideo]?
    var storeRating: StoreRating?
    var supportsWindows: Bool?
    var supportsNativeMacOS: Bool?
    var compatibility: CommunityCompatibility?

    init(from game: StoreLibraryGame) {
        developer = game.developer
        summary = game.summary
        artworkPath = game.artworkPath
        customArtworkPath = game.customArtworkPath
        customArtworkOriginalPath = game.customArtworkOriginalPath
        customArtworkCrop = game.customArtworkCrop
        portraitImageURL = game.portraitImageURL
        headerImageURL = game.headerImageURL
        backgroundImageURL = game.backgroundImageURL
        screenshotURLs = game.screenshotURLs
        videos = game.videos
        storeRating = game.storeRating
        supportsWindows = game.supportsWindows
        supportsNativeMacOS = game.supportsNativeMacOS
        compatibility = game.compatibility
    }
}

nonisolated struct Game: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var storeReference: StoreReference?
    var metadata: GameMetadata

    init(id: UUID, title: String, storeReference: StoreReference?, metadata: GameMetadata) {
        self.id = id
        self.title = title
        self.storeReference = storeReference
        self.metadata = metadata
    }
}

nonisolated struct GameInstallation: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let gameID: UUID
    var storeReference: StoreReference?
    var displayName: String?
    var location: InstallationLocation
    var platform: StoreGameInstallationPlatform
    var environmentID: UUID?
    var executables: [GameExecutable]
    var installedSize: Int64?
    var state: InstallationState
    var selectedExecutableID: UUID?
    var volumeIdentity: InstallationVolumeIdentity?
    var preparationState: GamePreparationState
    var providerBuildID: String?
    var installedVersion: String?
    var language: String?
    var selectedDLCs: [String]?
    var lastVerifiedAt: Date?
    var installedAt: Date?
    var lastSeenAt: Date?
    var runtimeUsed: String?
    var helperVersionUsed: String?
    var contentFingerprint: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        gameID: UUID,
        storeReference: StoreReference? = nil,
        displayName: String? = nil,
        location: InstallationLocation,
        platform: StoreGameInstallationPlatform,
        environmentID: UUID? = nil,
        executables: [GameExecutable] = [],
        installedSize: Int64? = nil,
        state: InstallationState = .installed,
        selectedExecutableID: UUID? = nil,
        volumeIdentity: InstallationVolumeIdentity? = nil,
        preparationState: GamePreparationState = .notPrepared,
        providerBuildID: String? = nil,
        installedVersion: String? = nil,
        language: String? = nil,
        selectedDLCs: [String]? = nil,
        lastVerifiedAt: Date? = nil,
        installedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        runtimeUsed: String? = nil,
        helperVersionUsed: String? = nil,
        contentFingerprint: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.gameID = gameID
        self.storeReference = storeReference
        self.displayName = displayName
        self.location = location
        self.platform = platform
        self.environmentID = environmentID
        self.executables = executables
        self.installedSize = installedSize
        self.state = state
        self.selectedExecutableID = selectedExecutableID
        self.volumeIdentity = volumeIdentity
        self.preparationState = preparationState
        self.providerBuildID = providerBuildID
        self.installedVersion = installedVersion
        self.language = language
        self.selectedDLCs = selectedDLCs
        self.lastVerifiedAt = lastVerifiedAt
        self.installedAt = installedAt
        self.lastSeenAt = lastSeenAt
        self.runtimeUsed = runtimeUsed
        self.helperVersionUsed = helperVersionUsed
        self.contentFingerprint = contentFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, gameID, storeReference, displayName, location, platform
        case environmentID, executables, installedSize, state
        case selectedExecutableID, volumeIdentity, preparationState
        case providerBuildID, installedVersion, language, selectedDLCs
        case lastVerifiedAt, installedAt, lastSeenAt, runtimeUsed
        case helperVersionUsed, contentFingerprint, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        gameID = try container.decode(UUID.self, forKey: .gameID)
        storeReference = try container.decodeIfPresent(StoreReference.self, forKey: .storeReference)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        location = try container.decode(InstallationLocation.self, forKey: .location)
        platform = try container.decode(StoreGameInstallationPlatform.self, forKey: .platform)
        environmentID = try container.decodeIfPresent(UUID.self, forKey: .environmentID)
        executables = try container.decodeIfPresent([GameExecutable].self, forKey: .executables) ?? []
        installedSize = try container.decodeIfPresent(Int64.self, forKey: .installedSize)
        state = try container.decodeIfPresent(InstallationState.self, forKey: .state) ?? .installed
        selectedExecutableID = try container.decodeIfPresent(UUID.self, forKey: .selectedExecutableID)
        volumeIdentity = try container.decodeIfPresent(InstallationVolumeIdentity.self, forKey: .volumeIdentity)
        preparationState = try container.decodeIfPresent(GamePreparationState.self, forKey: .preparationState) ?? .notPrepared
        providerBuildID = try container.decodeIfPresent(String.self, forKey: .providerBuildID)
        installedVersion = try container.decodeIfPresent(String.self, forKey: .installedVersion)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        selectedDLCs = try container.decodeIfPresent([String].self, forKey: .selectedDLCs)
        lastVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastVerifiedAt)
        installedAt = try container.decodeIfPresent(Date.self, forKey: .installedAt)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        runtimeUsed = try container.decodeIfPresent(String.self, forKey: .runtimeUsed)
        helperVersionUsed = try container.decodeIfPresent(String.self, forKey: .helperVersionUsed)
        contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(gameID, forKey: .gameID)
        try container.encodeIfPresent(storeReference, forKey: .storeReference)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(location, forKey: .location)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(environmentID, forKey: .environmentID)
        try container.encode(executables, forKey: .executables)
        try container.encodeIfPresent(installedSize, forKey: .installedSize)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(selectedExecutableID, forKey: .selectedExecutableID)
        try container.encodeIfPresent(volumeIdentity, forKey: .volumeIdentity)
        try container.encode(preparationState, forKey: .preparationState)
        try container.encodeIfPresent(providerBuildID, forKey: .providerBuildID)
        try container.encodeIfPresent(installedVersion, forKey: .installedVersion)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(selectedDLCs, forKey: .selectedDLCs)
        try container.encodeIfPresent(lastVerifiedAt, forKey: .lastVerifiedAt)
        try container.encodeIfPresent(installedAt, forKey: .installedAt)
        try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try container.encodeIfPresent(runtimeUsed, forKey: .runtimeUsed)
        try container.encodeIfPresent(helperVersionUsed, forKey: .helperVersionUsed)
        try container.encodeIfPresent(contentFingerprint, forKey: .contentFingerprint)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Storage layout

nonisolated struct BorealStorageLayout: Sendable {
    let rootURL: URL
    let libraryURL: URL
    let favoritesURL: URL
    let sessionsURL: URL
    let downloadsURL: URL
    let appStateURL: URL
    let legacyLibraryURL: URL

    init(applicationSupportURL: URL) {
        rootURL = applicationSupportURL
        let libraryDirectory = applicationSupportURL.appending(path: "Library", directoryHint: .isDirectory)
        libraryURL = libraryDirectory.appending(path: "library.json")
        favoritesURL = libraryDirectory.appending(path: "favorites.json")
        sessionsURL = libraryDirectory.appending(path: "sessions.json")
        downloadsURL = libraryDirectory.appending(path: "downloads.json")
        appStateURL = applicationSupportURL.appending(path: "State/app-state.json")
        legacyLibraryURL = applicationSupportURL.appending(path: "library.json")
    }

    var environmentsURL: URL { rootURL.appending(path: "Environments", directoryHint: .isDirectory) }
    var runtimesURL: URL { rootURL.appending(path: "Runtimes", directoryHint: .isDirectory) }
    var gamesURL: URL { rootURL.appending(path: "Games", directoryHint: .isDirectory) }
}

nonisolated enum BorealStorageCategory: String, CaseIterable, Hashable, Identifiable, Sendable {
    case games
    case environments
    case runtimes
    case caches
    case downloads
    case logs
    case snapshots
    case saveBackups

    var id: Self { self }

    var title: String {
        switch self {
        case .games: "Games"
        case .environments: "Environments"
        case .runtimes: "Runtimes"
        case .caches: "Caches"
        case .downloads: "Downloads"
        case .logs: "Diagnostics & Logs"
        case .snapshots: "Environment snapshots"
        case .saveBackups: "Save backups"
        }
    }

    var subtitle: String {
        switch self {
        case .games: "Installed game files measured at their actual locations."
        case .environments: "Wine prefixes and environment configuration."
        case .runtimes: "Installed compatibility runtimes and their components."
        case .caches: "Regeneratable shader and metadata data."
        case .downloads: "Downloaded installers and transfer data."
        case .logs: "Environment and diagnostic logs."
        case .snapshots: "Restore points for environment changes."
        case .saveBackups: "Copies of detected game save locations."
        }
    }

    var symbol: String {
        switch self {
        case .games: "gamecontroller.fill"
        case .environments: "externaldrive.fill"
        case .runtimes: "gearshape.2.fill"
        case .caches: "sparkles"
        case .downloads: "arrow.down.circle.fill"
        case .logs: "doc.text.magnifyingglass"
        case .snapshots: "clock.arrow.circlepath"
        case .saveBackups: "externaldrive.badge.timemachine"
        }
    }
}

nonisolated enum BorealCleanupRisk: String, Sendable {
    case safe
    case regeneratable
    case destructive

    var title: String {
        switch self {
        case .safe: "Safe"
        case .regeneratable: "Regeneratable"
        case .destructive: "Destructive"
        }
    }
}

nonisolated struct BorealStorageItem: Identifiable, Sendable {
    let category: BorealStorageCategory
    let name: String
    let detail: String?
    let bytes: Int64
    let risk: BorealCleanupRisk
    let isEstimated: Bool
    let location: URL?

    var id: String { "\(category.rawValue):\(location?.standardizedFileURL.path ?? name)" }
}

nonisolated struct BorealStorageReport: Sendable {
    let scannedAt: Date
    let items: [BorealStorageItem]

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    func items(for category: BorealStorageCategory) -> [BorealStorageItem] {
        items.filter { $0.category == category }.sorted {
            if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func bytes(for category: BorealStorageCategory) -> Int64 {
        items(for: category).reduce(0) { $0 + $1.bytes }
    }
}

/// Measures only paths Boreal already owns or has recorded in its library.
/// The scanner is deliberately read-only; cleanup remains a separate action.
nonisolated enum BorealStorageScanner {
    static func scan(
        layout: BorealStorageLayout,
        applications: [WindowsApplication],
        storeGames: [StoreLibraryGame],
        environments: [WindowsEnvironment],
        installations: [GameInstallation] = []
    ) -> BorealStorageReport {
        let fileManager = FileManager.default
        var measurements: [BorealStorageItem] = []
        var gameRoots: [URL] = []

        let canonicalInstallations = installations.isEmpty
            ? InstallationMigration.fromLegacy(applications: applications, storeGames: storeGames, layout: layout)
            : installations
        for installation in canonicalInstallations where installation.state.representsAnInstallation {
            guard let game = storeGames.first(where: {
                $0.id == installation.gameID || $0.storeReference == installation.storeReference
            }) else { continue }
            let root = InstallationStateResolver.resolvedLocation(for: installation, layout: layout).standardizedFileURL
            guard appendIfNew(root, to: &gameRoots) else { continue }
            let shaderRoots = shaderPaths(gameURL: root, prefixURL: nil, applicationSupportURL: layout.rootURL)
            let downloadRoots = downloadPaths(in: [root])
            let measuredBytes = size(of: root, excluding: shaderRoots + downloadRoots, fileManager: fileManager)
            let bytes = measuredBytes ?? installation.installedSize ?? 0
            guard bytes > 0 else { continue }
            measurements.append(BorealStorageItem(
                category: .games,
                name: game.name,
                detail: game.provider.rawValue,
                bytes: bytes,
                risk: .destructive,
                isEstimated: measuredBytes == nil,
                location: root
            ))
        }

        let linkedGameKeys = Set(canonicalInstallations.compactMap { installation in
            installation.storeReference.map { "\($0.provider.rawValue):\($0.externalID)" }
        })
        for application in applications where !application.isSteamRuntimeHost
            && !application.isInstallerOnly
            && !application.usesStoreMetadataOnly {
            let key = application.storeProvider.map { "\($0.rawValue):\(application.storeExternalID ?? "")" }
            guard key == nil || !linkedGameKeys.contains(key ?? "") else { continue }
            guard application.storageBytes > 0 else { continue }
            measurements.append(BorealStorageItem(
                category: .games,
                name: application.name,
                detail: "Installed application",
                bytes: application.storageBytes,
                risk: .destructive,
                isEstimated: true,
                location: URL(fileURLWithPath: application.executablePath).deletingLastPathComponent()
            ))
        }

        var environmentRoots: [URL] = []
        var environmentLogRoots: [URL] = []
        for environment in environments {
            let root = environment.rootPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? layout.environmentsURL.appending(path: environment.id.uuidString, directoryHint: .isDirectory)
            let standardizedRoot = root.standardizedFileURL
            guard appendIfNew(standardizedRoot, to: &environmentRoots) else { continue }
            let logs = environment.logsPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? standardizedRoot.appending(path: "Logs", directoryHint: .isDirectory)
            _ = appendIfNew(logs.standardizedFileURL, to: &environmentLogRoots)
            let shaderRoots = shaderPaths(gameURL: nil, prefixURL: environment.prefixPath.map { URL(fileURLWithPath: $0, isDirectory: true) }, applicationSupportURL: layout.rootURL)
            let measuredBytes = size(of: standardizedRoot, excluding: shaderRoots + [logs], fileManager: fileManager)
            let bytes = measuredBytes ?? environment.storageBytes
            guard bytes > 0 else { continue }
            let applicationCount = applicationCount(in: environment.id, applications: applications)
            measurements.append(BorealStorageItem(
                category: .environments,
                name: environment.name,
                detail: "\(applicationCount) \(applicationCount == 1 ? "application" : "applications")",
                bytes: bytes,
                risk: .destructive,
                isEstimated: measuredBytes == nil,
                location: standardizedRoot
            ))
        }

        let runtimeRoots = runtimeDirectories(in: layout.runtimesURL, fileManager: fileManager)
        var runtimeIDsInUse: [String: Int] = [:]
        for environment in environments {
            if let runtimeID = environment.runtimeID { runtimeIDsInUse[runtimeID, default: 0] += 1 }
        }
        for root in runtimeRoots {
            let manifestURL = root.appending(path: "installed-runtime.json")
            let runtime = try? JSONDecoder().decode(InstalledRuntime.self, from: Data(contentsOf: manifestURL))
            let runtimeID = runtime?.id ?? root.lastPathComponent
            let name = runtime?.displayName ?? root.lastPathComponent
            let usedBy = runtimeIDsInUse[runtimeID] ?? 0
            let detail = usedBy > 0 ? "Used by \(usedBy) \(usedBy == 1 ? "environment" : "environments")" : "Not used by an environment"
            let downloads = downloadPaths(in: [root])
            let measuredBytes = size(of: root, excluding: downloads, fileManager: fileManager)
            let bytes = measuredBytes ?? 0
            guard bytes > 0 else { continue }
            measurements.append(BorealStorageItem(
                category: .runtimes,
                name: name,
                detail: detail,
                bytes: bytes,
                risk: .destructive,
                isEstimated: false,
                location: root
            ))
        }

        let downloadRoots = uniqueURLs([
            layout.rootURL.appending(path: "Downloads", directoryHint: .isDirectory),
            layout.rootURL.appending(path: ".downloads", directoryHint: .isDirectory),
            layout.runtimesURL.appending(path: ".downloads", directoryHint: .isDirectory)
        ])
        for root in downloadRoots {
            guard let bytes = size(of: root, excluding: [], fileManager: fileManager), bytes > 0 else { continue }
            measurements.append(BorealStorageItem(
                category: .downloads,
                name: downloadTitle(for: root),
                detail: "Downloaded files",
                bytes: bytes,
                risk: .safe,
                isEstimated: false,
                location: root
            ))
        }

        let durableRoots: [(BorealStorageCategory, String, URL)] = [
            (.snapshots, "Environment snapshots", layout.rootURL.appending(path: "Snapshots", directoryHint: .isDirectory)),
            (.saveBackups, "Save backups", layout.rootURL.appending(path: "SaveBackups", directoryHint: .isDirectory))
        ]
        for (category, name, root) in durableRoots {
            guard let bytes = size(of: root, excluding: [], fileManager: fileManager), bytes > 0 else { continue }
            measurements.append(BorealStorageItem(
                category: category,
                name: name,
                detail: "Boreal recovery data",
                bytes: bytes,
                risk: .safe,
                isEstimated: false,
                location: root
            ))
        }

        let knownInstallerPaths = uniqueURLs(applications.compactMap { application in
            guard application.installerPath.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: application.installerPath).standardizedFileURL
        })
        for installer in knownInstallerPaths {
            guard fileManager.fileExists(atPath: installer.path), let bytes = fileSize(of: installer, fileManager: fileManager), bytes > 0 else { continue }
            measurements.append(BorealStorageItem(
                category: .downloads,
                name: installer.deletingPathExtension().lastPathComponent,
                detail: "Installer",
                bytes: bytes,
                risk: .safe,
                isEstimated: false,
                location: installer
            ))
        }

        measurements.append(contentsOf: cacheMeasurements(layout: layout, gameRoots: gameRoots, environments: environments, fileManager: fileManager))

        for logs in environmentLogRoots {
            guard let bytes = size(of: logs, excluding: [], fileManager: fileManager), bytes > 0 else { continue }
            let environmentName = environments.first {
                let path = $0.logsPath ?? layout.environmentsURL.appending(path: $0.id.uuidString).appending(path: "Logs").path
                return URL(fileURLWithPath: path).standardizedFileURL == logs
            }?.name
            measurements.append(BorealStorageItem(
                category: .logs,
                name: environmentName.map { "\($0) logs" } ?? "Environment logs",
                detail: "Environment diagnostics",
                bytes: bytes,
                risk: .safe,
                isEstimated: false,
                location: logs
            ))
        }

        return BorealStorageReport(scannedAt: .now, items: deduplicated(measurements))
    }

    private static func cacheMeasurements(
        layout: BorealStorageLayout,
        gameRoots: [URL],
        environments: [WindowsEnvironment],
        fileManager: FileManager
    ) -> [BorealStorageItem] {
        var result: [BorealStorageItem] = []
        var paths: [URL] = []
        for root in gameRoots {
            paths.append(contentsOf: shaderPaths(gameURL: root, prefixURL: nil, applicationSupportURL: layout.rootURL))
        }
        for environment in environments {
            let prefix = environment.prefixPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            paths.append(contentsOf: shaderPaths(gameURL: nil, prefixURL: prefix, applicationSupportURL: layout.rootURL))
        }
        for path in uniqueURLs(paths) {
            guard let bytes = size(of: path, excluding: [], fileManager: fileManager), bytes > 0 else { continue }
            result.append(BorealStorageItem(category: .caches, name: "Shader cache", detail: path.deletingLastPathComponent().lastPathComponent, bytes: bytes, risk: .regeneratable, isEstimated: false, location: path))
        }

        let discoveryFiles = [
            layout.rootURL.appending(path: "Discovery/applegamingwiki.json"),
            layout.rootURL.appending(path: "Discovery/applegamingwiki-metadata.json"),
            layout.rootURL.appending(path: "Discovery/applegamingwiki-unavailable.json"),
            layout.rootURL.appending(path: "Discovery/itad-prices.json")
        ]
        let discoveryBytes = discoveryFiles.compactMap { fileSize(of: $0, fileManager: fileManager) }.reduce(0, +)
        if discoveryBytes > 0 {
            result.append(BorealStorageItem(category: .caches, name: "Metadata cache", detail: "Discovery and price data", bytes: discoveryBytes, risk: .regeneratable, isEstimated: false, location: layout.rootURL.appending(path: "Discovery")))
        }
        return result
    }

    private static func shaderPaths(gameURL: URL?, prefixURL: URL?, applicationSupportURL: URL) -> [URL] {
        let report = GameDiskStorage.report(gameURL: gameURL, prefixURL: prefixURL, applicationSupportURL: applicationSupportURL)
        return report.item(.shaders)?.paths ?? []
    }

    private static func runtimeDirectories(in root: URL, fileManager: FileManager) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]))?.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        } ?? []
    }

    private static func downloadPaths(in roots: [URL]) -> [URL] {
        roots.flatMap { root in
            [root.appending(path: "Downloads", directoryHint: .isDirectory), root.appending(path: ".downloads", directoryHint: .isDirectory)]
        }
    }

    private static func applicationCount(in environmentID: UUID, applications: [WindowsApplication]) -> Int {
        applications.filter { $0.environmentID == environmentID && !$0.isSteamRuntimeHost }.count
    }

    private static func appendIfNew(_ url: URL, to urls: inout [URL]) -> Bool {
        let standardized = url.standardizedFileURL
        guard !urls.contains(where: { $0.standardizedFileURL == standardized }) else { return false }
        urls.append(standardized)
        return true
    }

    private static func downloadTitle(for root: URL) -> String {
        if root.path.contains("Runtimes") { return "Runtime installers" }
        return "Downloaded installers"
    }

    private static func size(of root: URL, excluding excluded: [URL], fileManager: FileManager) -> Int64? {
        guard fileManager.fileExists(atPath: root.path) else { return nil }
        let excluded = uniqueURLs(excluded).map(\.standardizedFileURL)
        if let file = fileSize(of: root, fileManager: fileManager) { return file }
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey], options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let standardized = url.standardizedFileURL
            if excluded.contains(where: { standardized.path == $0.path || standardized.path.hasPrefix($0.path + "/") }) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { enumerator.skipDescendants() }
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total > 0 ? total : nil
    }

    private static func fileSize(of url: URL, fileManager: FileManager) -> Int64? {
        guard fileManager.fileExists(atPath: url.path), let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]), values.isRegularFile == true else { return nil }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func deduplicated(_ items: [BorealStorageItem]) -> [BorealStorageItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

nonisolated enum BorealStorageSchema {
    static let current = 3
}

// The catalog intentionally contains no downloads, favorites, sessions, or
// transient launch state. These records are projections of the in-memory
// models, so existing view code can be migrated independently.
nonisolated struct LibraryApplicationRecord: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var publisher: String
    var executableLocation: InstallationLocation
    var installerPath: String
    var installerLocation: InstallationLocation?
    var environmentID: UUID
    var windowsVersion: String
    var graphics: String
    var iconSymbol: String
    var customArtworkPath: String?
    var customArtworkOriginalPath: String?
    var customArtworkCrop: ArtworkCrop?
    var storeReference: StoreReference?
    var storeMetadataOnly: Bool?
    var applicationRole: WindowsApplicationRole?
    var communityCompatibility: CommunityCompatibility?
    var compatibilityProfile: WineCompatibilityProfile?
    var auxiliaryExecutables: [LibraryExecutableRecord]?
    var steamPoolKey: String?

    init(_ application: WindowsApplication, layout: BorealStorageLayout) {
        id = application.id
        name = application.name
        publisher = application.publisher
        executableLocation = StoragePathResolver.location(
            for: URL(fileURLWithPath: application.executablePath),
            layout: layout
        )
        if application.installerPath.hasPrefix("/") {
            installerPath = ""
            installerLocation = StoragePathResolver.location(
                for: URL(fileURLWithPath: application.installerPath),
                layout: layout
            )
        } else {
            installerPath = application.installerPath
            installerLocation = nil
        }
        environmentID = application.environmentID
        windowsVersion = application.windowsVersion
        graphics = application.graphics
        iconSymbol = application.iconSymbol
        customArtworkPath = application.customArtworkPath
        customArtworkOriginalPath = application.customArtworkOriginalPath
        customArtworkCrop = application.customArtworkCrop
        storeReference = application.storeReference
        storeMetadataOnly = application.storeMetadataOnly
        applicationRole = application.applicationRole
        communityCompatibility = application.communityCompatibility
        compatibilityProfile = application.compatibilityProfile
        auxiliaryExecutables = application.auxiliaryExecutables?.map {
            LibraryExecutableRecord($0, layout: layout)
        }
        steamPoolKey = application.steamPoolKey
    }

    func resolve(layout: BorealStorageLayout) -> WindowsApplication {
        let executablePath = StoragePathResolver.resolve(executableLocation, layout: layout)
        let resolvedInstallerPath = installerLocation.map {
            StoragePathResolver.resolve($0, layout: layout).path
        } ?? installerPath
        return WindowsApplication(
            id: id,
            name: name,
            publisher: publisher,
            executablePath: executablePath.path,
            installerPath: resolvedInstallerPath,
            environmentID: environmentID,
            windowsVersion: windowsVersion,
            graphics: graphics,
            iconSymbol: iconSymbol,
            customArtworkPath: customArtworkPath,
            customArtworkOriginalPath: customArtworkOriginalPath,
            customArtworkCrop: customArtworkCrop,
            storeProvider: storeReference?.provider,
            storeExternalID: storeReference?.externalID,
            storeMetadataOnly: storeMetadataOnly,
            communityCompatibility: communityCompatibility,
            compatibilityProfile: compatibilityProfile,
            auxiliaryExecutables: auxiliaryExecutables?.map { $0.resolve(layout: layout) },
            applicationRole: applicationRole,
            steamPoolKey: steamPoolKey
        )
    }
}

nonisolated struct LibraryExecutableRecord: Codable, Hashable, Sendable {
    var executableLocation: InstallationLocation
    var role: AuxiliaryExecutableRole
    var displayName: String

    init(_ executable: AuxiliaryExecutable, layout: BorealStorageLayout) {
        executableLocation = StoragePathResolver.location(
            for: URL(fileURLWithPath: executable.executablePath),
            layout: layout
        )
        role = executable.role
        displayName = executable.displayName
    }

    func resolve(layout: BorealStorageLayout) -> AuxiliaryExecutable {
        AuxiliaryExecutable(
            executablePath: StoragePathResolver.resolve(executableLocation, layout: layout).path,
            role: role,
            displayName: displayName
        )
    }
}

nonisolated struct LibraryGameRecord: Codable, Hashable, Sendable {
    var id: UUID
    var provider: GameLibraryProvider
    var externalID: String
    var name: String
    var metadata: GameMetadata
    var sizeEstimate: StoreGameSizeEstimate?
    var currentPlayerCount: Int?
    var entitlementState: StoreEntitlementState?
    var entitlementGroupID: String?

    init(_ game: StoreLibraryGame) {
        id = game.id
        provider = game.provider
        externalID = game.externalID
        name = game.name
        metadata = GameMetadata(from: game)
        sizeEstimate = game.sizeEstimate
        currentPlayerCount = game.currentPlayerCount
        entitlementState = game.entitlementState
        entitlementGroupID = game.entitlementGroupID
    }

    func resolve() -> StoreLibraryGame {
        StoreLibraryGame(
            id: id,
            provider: provider,
            externalID: externalID,
            name: name,
            developer: metadata.developer,
            summary: metadata.summary,
            artworkPath: metadata.artworkPath,
            customArtworkPath: metadata.customArtworkPath,
            customArtworkOriginalPath: metadata.customArtworkOriginalPath,
            customArtworkCrop: metadata.customArtworkCrop,
            portraitImageURL: metadata.portraitImageURL,
            headerImageURL: metadata.headerImageURL,
            backgroundImageURL: metadata.backgroundImageURL,
            screenshotURLs: metadata.screenshotURLs,
            videos: metadata.videos,
            storeRating: metadata.storeRating,
            supportsWindows: metadata.supportsWindows,
            supportsNativeMacOS: metadata.supportsNativeMacOS,
            sizeEstimate: sizeEstimate,
            compatibility: metadata.compatibility,
            currentPlayerCount: currentPlayerCount,
            entitlementState: entitlementState,
            entitlementGroupID: entitlementGroupID
        )
    }
}

nonisolated struct LibraryDatabase: Codable, Sendable {
    var schemaVersion: Int
    var applications: [LibraryApplicationRecord]
    var games: [LibraryGameRecord]
    var installations: [GameInstallation]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, applications, games, installations
    }

    init(
        schemaVersion: Int,
        applications: [LibraryApplicationRecord],
        games: [LibraryGameRecord],
        installations: [GameInstallation]
    ) {
        self.schemaVersion = schemaVersion
        self.applications = applications
        self.games = games
        self.installations = installations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        applications = try container.decodeIfPresent([LibraryApplicationRecord].self, forKey: .applications) ?? []
        games = try container.decodeIfPresent([LibraryGameRecord].self, forKey: .games) ?? []
        // Version 1 could contain only catalog/application records. Missing
        // installations are migrated from the legacy UI models by the loader.
        installations = try container.decodeIfPresent([GameInstallation].self, forKey: .installations) ?? []
    }
}

nonisolated struct FavoritesDatabase: Codable, Sendable {
    var schemaVersion: Int
    var keys: [String]
}

nonisolated struct SessionsDatabase: Codable, Sendable {
    struct Record: Codable, Sendable {
        var gameID: UUID
        var playtimeMinutes: Int
        var lastPlayed: Date?
        var borealPlaytimeSeconds: TimeInterval?
        var sessions: [GamePlaySession]
    }

    var schemaVersion: Int
    var records: [Record]
}

nonisolated struct DownloadsDatabase: Codable, Sendable {
    var schemaVersion: Int
    var records: [String: StoreDownloadRecord]
}

nonisolated struct AppStateDatabase: Codable, Sendable {
    var schemaVersion: Int
    var lastAutomaticLibraryRefreshAt: Date?
    var runtimeDisplayNameOverrides: [String: String]?
}

/// The old one-file envelope is kept solely as a migration reader and for
/// explicitly supplied legacy/test storage URLs. It is never written by the
/// default storage path after the layered layout is available.
nonisolated struct LegacyBorealState: Codable, Sendable {
    var applications: [WindowsApplication]
    var environments: [WindowsEnvironment]
    var storeGames: [StoreLibraryGame]?
    var storeDownloads: [String: StoreDownloadRecord]?
    var favoriteKeys: [String]?
    var lastAutomaticLibraryRefreshAt: Date?
    var runtimeDisplayNameOverrides: [String: String]?
}

nonisolated enum StoragePathResolver {
    static func location(for url: URL, layout: BorealStorageLayout) -> InstallationLocation {
        let normalized = url.standardizedFileURL
        let managedRoot = layout.gamesURL.standardizedFileURL
        let prefix = managedRoot.path.hasSuffix("/") ? managedRoot.path : managedRoot.path + "/"
        if normalized.path.hasPrefix(prefix) {
            return .managed(relativePath: String(normalized.path.dropFirst(prefix.count)))
        }
        return .external(path: normalized.path)
    }

    static func resolve(_ location: InstallationLocation, layout: BorealStorageLayout) -> URL {
        switch location {
        case .managed(let relativePath):
            return layout.gamesURL.appending(path: relativePath)
        case .external(let path):
            return URL(fileURLWithPath: path)
        }
    }
}

// MARK: - Serialized repositories

/// All writes for one JSON document pass through an actor. `BorealStore` can
/// keep its UI-facing synchronous mutations while the repositories serialize
/// snapshots and prevent interleaved writes from different tasks.
actor JSONStore<Value: Codable & Sendable> {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func save(_ value: Value) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func load() throws -> Value {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}

actor LibraryRepository {
    private let library: JSONStore<LibraryDatabase>
    private let favorites: JSONStore<FavoritesDatabase>
    private let sessions: JSONStore<SessionsDatabase>
    private let downloads: JSONStore<DownloadsDatabase>
    private let appState: JSONStore<AppStateDatabase>

    init(layout: BorealStorageLayout) {
        library = JSONStore(url: layout.libraryURL)
        favorites = JSONStore(url: layout.favoritesURL)
        sessions = JSONStore(url: layout.sessionsURL)
        downloads = JSONStore(url: layout.downloadsURL)
        appState = JSONStore(url: layout.appStateURL)
    }

    func save(_ snapshot: BorealStorageSnapshot) async throws {
        try await library.save(snapshot.library)
        try await favorites.save(snapshot.favorites)
        try await sessions.save(snapshot.sessions)
        try await downloads.save(snapshot.downloads)
        try await appState.save(snapshot.appState)
    }
}

actor EnvironmentRepository {
    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) { self.rootURL = rootURL }

    func all() -> [ManagedBorealEnvironment] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap { child in
            guard child.hasDirectoryPath,
                  let data = try? Data(contentsOf: child.appending(path: "environment.json")),
                  let environment = try? JSONDecoder().decode(ManagedBorealEnvironment.self, from: data) else { return nil }
            return environment
        }
    }
}

actor RuntimeRepository {
    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) { self.rootURL = rootURL }

    func installedDescriptors() -> [InstalledRuntime] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap { child in
            guard child.hasDirectoryPath,
                  let data = try? Data(contentsOf: child.appending(path: "installed-runtime.json")),
                  let runtime = try? JSONDecoder().decode(InstalledRuntime.self, from: data) else { return nil }
            return runtime
        }
    }
}

nonisolated struct BorealStorageSnapshot: Sendable {
    let library: LibraryDatabase
    let favorites: FavoritesDatabase
    let sessions: SessionsDatabase
    let downloads: DownloadsDatabase
    let appState: AppStateDatabase

    init(
        applications: [WindowsApplication],
        storeGames: [StoreLibraryGame],
        favoriteKeys: Set<String>,
        storeDownloads: [String: StoreDownloadRecord],
        lastAutomaticLibraryRefreshAt: Date?,
        layout: BorealStorageLayout,
        runtimeDisplayNameOverrides: [String: String] = [:],
        installations canonicalInstallations: [GameInstallation] = []
    ) {
        let installations = canonicalInstallations.isEmpty
            ? InstallationMigration.fromLegacy(applications: applications, storeGames: storeGames, layout: layout)
            : canonicalInstallations

        library = LibraryDatabase(
            schemaVersion: BorealStorageSchema.current,
            applications: applications.map { LibraryApplicationRecord($0, layout: layout) },
            games: storeGames.map(LibraryGameRecord.init),
            installations: installations
        )
        favorites = FavoritesDatabase(schemaVersion: BorealStorageSchema.current, keys: favoriteKeys.sorted())
        sessions = SessionsDatabase(
            schemaVersion: BorealStorageSchema.current,
            records: storeGames.map {
                SessionsDatabase.Record(
                    gameID: $0.id,
                    playtimeMinutes: $0.playtimeMinutes,
                    lastPlayed: $0.lastPlayed,
                    borealPlaytimeSeconds: $0.borealPlaytimeSeconds,
                    sessions: $0.playSessions ?? []
                )
            }
        )
        downloads = DownloadsDatabase(schemaVersion: BorealStorageSchema.current, records: storeDownloads)
        appState = AppStateDatabase(
            schemaVersion: BorealStorageSchema.current,
            lastAutomaticLibraryRefreshAt: lastAutomaticLibraryRefreshAt,
            runtimeDisplayNameOverrides: runtimeDisplayNameOverrides.isEmpty ? nil : runtimeDisplayNameOverrides
        )
    }
}

nonisolated struct BorealStorageLoadedState: Sendable {
    var applications: [WindowsApplication]
    var environments: [WindowsEnvironment]
    var storeGames: [StoreLibraryGame]
    var installations: [GameInstallation]
    var storeDownloads: [String: StoreDownloadRecord]
    var favoriteKeys: Set<String>
    var lastAutomaticLibraryRefreshAt: Date?
    var runtimeDisplayNameOverrides: [String: String]
}

nonisolated enum BorealStorageLoader {
    static func loadLayered(from layout: BorealStorageLayout) -> BorealStorageLoadedState? {
        guard let library = decode(LibraryDatabase.self, at: layout.libraryURL),
              library.schemaVersion <= BorealStorageSchema.current else { return nil }

        let applications = library.applications.map { $0.resolve(layout: layout) }
        var games = library.games.map { $0.resolve() }
        let migratedInstallations = library.installations.isEmpty
            ? InstallationMigration.fromLegacy(applications: applications, storeGames: games, layout: layout)
            : library.installations
        let installations = migratedInstallations.map {
            InstallationStateResolver.resolve($0, layout: layout)
        }
        for installation in installations where installation.state.representsAnInstallation {
            guard let index = games.firstIndex(where: { $0.id == installation.gameID }) else { continue }
            games[index].isInstalled = installation.state != .uninstalled
            games[index].installedPlatform = installation.platform
            games[index].installPath = StoragePathResolver.resolve(installation.location, layout: layout).path
            games[index].storageBytes = installation.installedSize
        }

        if let sessionDatabase = decode(SessionsDatabase.self, at: layout.sessionsURL),
           sessionDatabase.schemaVersion <= BorealStorageSchema.current {
            for record in sessionDatabase.records {
                guard let index = games.firstIndex(where: { $0.id == record.gameID }) else { continue }
                games[index].playtimeMinutes = record.playtimeMinutes
                games[index].lastPlayed = record.lastPlayed
                games[index].borealPlaytimeSeconds = record.borealPlaytimeSeconds
                games[index].playSessions = record.sessions
            }
        }

        let environments = scanEnvironments(from: layout)
        let downloads = decode(DownloadsDatabase.self, at: layout.downloadsURL)
        let favorites = decode(FavoritesDatabase.self, at: layout.favoritesURL)
        let appState = decode(AppStateDatabase.self, at: layout.appStateURL)

        return BorealStorageLoadedState(
            applications: applications,
            environments: environments,
            storeGames: games,
            installations: installations,
            storeDownloads: (downloads?.schemaVersion ?? 0) <= BorealStorageSchema.current ? (downloads?.records ?? [:]) : [:],
            favoriteKeys: Set((favorites?.schemaVersion ?? 0) <= BorealStorageSchema.current ? (favorites?.keys ?? []) : []),
            lastAutomaticLibraryRefreshAt: (appState?.schemaVersion ?? 0) <= BorealStorageSchema.current ? appState?.lastAutomaticLibraryRefreshAt : nil,
            runtimeDisplayNameOverrides: (appState?.schemaVersion ?? 0) <= BorealStorageSchema.current
                ? (appState?.runtimeDisplayNameOverrides ?? [:])
                : [:]
        )
    }

    static func decodeLegacy(from url: URL) -> LegacyBorealState? {
        decode(LegacyBorealState.self, at: url)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, at url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func scanEnvironments(from layout: BorealStorageLayout) -> [WindowsEnvironment] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: layout.environmentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.compactMap { child in
            guard child.hasDirectoryPath,
                  let data = try? Data(contentsOf: child.appending(path: "environment.json")),
                  let environment = try? JSONDecoder().decode(ManagedBorealEnvironment.self, from: data) else { return nil }
            let architecture = environment.configuration.architecture == WinePrefixArchitecture.win64.rawValue
                ? "64-bit" : "32-bit"
            return WindowsEnvironment(
                id: environment.id,
                name: environment.configuration.name,
                windowsVersion: WineWindowsVersion(rawValue: environment.configuration.windowsVersion)?.displayName ?? environment.configuration.windowsVersion,
                architecture: architecture,
                graphics: environment.configuration.graphicsBackend.displayName,
                runtimeID: environment.runtimeID,
                rootPath: environment.rootURL.path,
                prefixPath: environment.prefixURL.path,
                logsPath: environment.logsURL.path
            )
        }
    }

    static func migrateLegacyEnvironments(_ environments: [WindowsEnvironment], to layout: BorealStorageLayout) {
        let fileManager = FileManager.default
        for environment in environments {
            guard let runtimeID = environment.runtimeID,
                  let rootPath = environment.rootPath,
                  let prefixPath = environment.prefixPath,
                  let logsPath = environment.logsPath else { continue }
            let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            let descriptorURL = rootURL.appending(path: "environment.json")
            guard !fileManager.fileExists(atPath: descriptorURL.path) else { continue }
            let architecture = environment.architecture == "32-bit" ? WinePrefixArchitecture.win32.rawValue : WinePrefixArchitecture.win64.rawValue
            let windowsVersion = WineWindowsVersion.allCases.first(where: { $0.displayName == environment.windowsVersion })?.rawValue ?? "win11"
            let configuration = EnvironmentConfiguration(
                name: environment.name,
                windowsVersion: windowsVersion,
                architecture: architecture
            )
            let managed = ManagedBorealEnvironment(
                id: environment.id,
                configuration: configuration,
                runtimeID: runtimeID,
                rootURL: rootURL,
                prefixURL: URL(fileURLWithPath: prefixPath, isDirectory: true),
                logsURL: URL(fileURLWithPath: logsPath, isDirectory: true),
                state: .ready
            )
            guard let data = try? JSONEncoder().encode(managed) else { continue }
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try? data.write(to: descriptorURL, options: .atomic)
        }
    }
}
