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
    var location: InstallationLocation
    var platform: StoreGameInstallationPlatform
    var environmentID: UUID?
    var executables: [GameExecutable]
    var installedSize: Int64?

    init(
        id: UUID = UUID(),
        gameID: UUID,
        location: InstallationLocation,
        platform: StoreGameInstallationPlatform,
        environmentID: UUID? = nil,
        executables: [GameExecutable] = [],
        installedSize: Int64? = nil
    ) {
        self.id = id
        self.gameID = gameID
        self.location = location
        self.platform = platform
        self.environmentID = environmentID
        self.executables = executables
        self.installedSize = installedSize
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

nonisolated enum BorealStorageSchema {
    static let current = 1
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
    var storeReference: StoreReference?
    var storeMetadataOnly: Bool?
    var communityCompatibility: CommunityCompatibility?
    var compatibilityProfile: WineCompatibilityProfile?
    var auxiliaryExecutables: [LibraryExecutableRecord]?

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
        storeReference = application.storeReference
        storeMetadataOnly = application.storeMetadataOnly
        communityCompatibility = application.communityCompatibility
        compatibilityProfile = application.compatibilityProfile
        auxiliaryExecutables = application.auxiliaryExecutables?.map {
            LibraryExecutableRecord($0, layout: layout)
        }
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
            storeProvider: storeReference?.provider,
            storeExternalID: storeReference?.externalID,
            storeMetadataOnly: storeMetadataOnly,
            communityCompatibility: communityCompatibility,
            compatibilityProfile: compatibilityProfile,
            auxiliaryExecutables: auxiliaryExecutables?.map { $0.resolve(layout: layout) }
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

    init(_ game: StoreLibraryGame) {
        id = game.id
        provider = game.provider
        externalID = game.externalID
        name = game.name
        metadata = GameMetadata(from: game)
        sizeEstimate = game.sizeEstimate
        currentPlayerCount = game.currentPlayerCount
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
            currentPlayerCount: currentPlayerCount
        )
    }
}

nonisolated struct LibraryDatabase: Codable, Sendable {
    var schemaVersion: Int
    var applications: [LibraryApplicationRecord]
    var games: [LibraryGameRecord]
    var installations: [GameInstallation]
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
        layout: BorealStorageLayout
    ) {
        var installations: [GameInstallation] = []
        for game in storeGames where game.isInstalled {
            guard let installPath = game.installPath else { continue }
            let installLocation = StoragePathResolver.location(
                for: URL(fileURLWithPath: installPath),
                layout: layout
            )
            let environmentID = applications.first(where: {
                $0.storeProvider == game.provider
                    && $0.storeExternalID == game.externalID
                    && $0.status != .unavailable
            })?.environmentID
            let installedSize: Int64? = (game.storageBytes ?? 0) > 0
                ? game.storageBytes
                : game.displayedStorageBytes
            let installation = GameInstallation(
                id: game.id,
                gameID: game.id,
                location: installLocation,
                platform: game.installedPlatform ?? .windows,
                environmentID: environmentID,
                installedSize: installedSize
            )
            installations.append(installation)
        }
        for application in applications {
            guard !application.isSteamRuntimeHost else { continue }
            let appURL = URL(fileURLWithPath: application.executablePath)
            let executableArchitecture: ExecutableArchitecture? = switch WindowsExecutableArchitecture.inspect(appURL) {
            case .x86: .x86
            case .x86_64: .x86_64
            case .unknown: nil
            }
            let executable = GameExecutable(
                relativePath: appURL.lastPathComponent,
                role: .game,
                architecture: executableArchitecture
            )
            let installation = GameInstallation(
                id: application.id,
                gameID: application.id,
                location: StoragePathResolver.location(for: appURL.deletingLastPathComponent(), layout: layout),
                platform: .windows,
                environmentID: application.environmentID,
                executables: [executable],
                installedSize: application.storageBytes > 0 ? application.storageBytes : nil
            )
            installations.append(installation)
        }

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
        appState = AppStateDatabase(schemaVersion: BorealStorageSchema.current, lastAutomaticLibraryRefreshAt: lastAutomaticLibraryRefreshAt)
    }
}

nonisolated struct BorealStorageLoadedState: Sendable {
    var applications: [WindowsApplication]
    var environments: [WindowsEnvironment]
    var storeGames: [StoreLibraryGame]
    var storeDownloads: [String: StoreDownloadRecord]
    var favoriteKeys: Set<String>
    var lastAutomaticLibraryRefreshAt: Date?
}

nonisolated enum BorealStorageLoader {
    static func loadLayered(from layout: BorealStorageLayout) -> BorealStorageLoadedState? {
        guard let library = decode(LibraryDatabase.self, at: layout.libraryURL),
              library.schemaVersion <= BorealStorageSchema.current else { return nil }

        let applications = library.applications.map { $0.resolve(layout: layout) }
        var games = library.games.map { $0.resolve() }
        for installation in library.installations {
            guard let index = games.firstIndex(where: { $0.id == installation.gameID }) else { continue }
            games[index].isInstalled = true
            games[index].installedPlatform = installation.platform
            games[index].installPath = StoragePathResolver.resolve(installation.location, layout: layout).path
            games[index].storageBytes = installation.installedSize ?? 0
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
            storeDownloads: (downloads?.schemaVersion ?? 0) <= BorealStorageSchema.current ? (downloads?.records ?? [:]) : [:],
            favoriteKeys: Set((favorites?.schemaVersion ?? 0) <= BorealStorageSchema.current ? (favorites?.keys ?? []) : []),
            lastAutomaticLibraryRefreshAt: (appState?.schemaVersion ?? 0) <= BorealStorageSchema.current ? appState?.lastAutomaticLibraryRefreshAt : nil
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
