import Foundation

// MARK: - Installation service

/// Resolves only the filesystem-backed part of an installation. Provider
/// metadata and the legacy `StoreLibraryGame` flags are not consulted here.
/// This keeps the precedence explicit: filesystem -> persisted installation.
nonisolated enum InstallationStateResolver {
    static func resolve(
        _ installation: GameInstallation,
        layout: BorealStorageLayout,
        fileManager: FileManager = .default
    ) -> GameInstallation {
        var resolved = installation
        let nextState = resolveState(installation, layout: layout, fileManager: fileManager)
        if resolved.state != nextState {
            resolved.state = nextState
            resolved.updatedAt = .now
        }
        return resolved
    }

    static func resolveState(
        _ installation: GameInstallation,
        layout: BorealStorageLayout,
        fileManager: FileManager = .default
    ) -> InstallationState {
        guard installation.state != .uninstalled else { return .uninstalled }
        let location = StoragePathResolver.resolve(installation.location, layout: layout)
        guard fileManager.fileExists(atPath: location.path) else { return .missing }
        if let executable = installation.selectedExecutableID.flatMap({ id in
            installation.executables.first(where: { $0.id == id })
        }) ?? installation.executables.first(where: { $0.role == .game }) {
            let executableURL = location.appending(path: executable.relativePath)
            guard fileManager.fileExists(atPath: executableURL.path) else { return .missing }
        }
        switch installation.state {
        case .broken, .uninstalled: return installation.state
        case .unknown, .installing, .installed, .missing: return .installed
        }
    }
}

/// Converts the old UI-owned installation flags into the new canonical
/// records. It is intentionally deterministic so the migration can be run at
/// startup more than once without creating duplicate installations.
nonisolated enum InstallationMigration {
    static func fromLegacy(
        applications: [WindowsApplication],
        storeGames: [StoreLibraryGame],
        layout: BorealStorageLayout
    ) -> [GameInstallation] {
        var result: [UUID: GameInstallation] = [:]
        let gamesByLink = Dictionary(
            storeGames.map { ($0.storeReference, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for game in storeGames where game.isInstalled {
            guard let path = game.installPath else { continue }
            let installation = GameInstallation(
                id: game.id,
                gameID: game.id,
                storeReference: game.storeReference,
                displayName: game.name,
                location: StoragePathResolver.location(
                    for: URL(fileURLWithPath: path, isDirectory: true),
                    layout: layout
                ),
                platform: game.installedPlatform ?? .windows,
                installedSize: game.displayedStorageBytes,
                state: .installed
            )
            result[game.id] = installation
        }

        for application in applications {
            guard !application.isSteamRuntimeHost, !application.isInstallerOnly else { continue }
            let appURL = URL(fileURLWithPath: application.executablePath)
            let matchedGame = application.storeProvider.flatMap { provider in
                application.storeExternalID.flatMap { externalID in
                    gamesByLink[StoreReference(provider: provider, externalID: externalID)]
                }
            }
            let gameID = matchedGame?.id ?? application.id
            let rootURL: URL
            if let existing = result[gameID] {
                rootURL = StoragePathResolver.resolve(existing.location, layout: layout)
            } else if let installPath = matchedGame?.installPath {
                rootURL = URL(fileURLWithPath: installPath, isDirectory: true)
            } else {
                rootURL = appURL.deletingLastPathComponent()
            }

            let relativePath = relativePath(of: appURL, to: rootURL) ?? appURL.lastPathComponent
            let architecture: ExecutableArchitecture? = switch WindowsExecutableArchitecture.inspect(appURL) {
            case .x86: .x86
            case .x86_64: .x86_64
            case .unknown: nil
            }
            let executable = GameExecutable(
                relativePath: relativePath,
                role: .game,
                architecture: architecture
            )
            if var installation = result[gameID] {
                if !installation.executables.contains(where: { $0.relativePath == executable.relativePath }) {
                    installation.executables.append(executable)
                }
                installation.environmentID = installation.environmentID ?? application.environmentID
                installation.updatedAt = .now
                result[gameID] = installation
            } else {
                result[gameID] = GameInstallation(
                    id: matchedGame?.id ?? application.id,
                    gameID: gameID,
                    storeReference: matchedGame?.storeReference ?? application.storeReference,
                    displayName: matchedGame?.name ?? application.name,
                    location: StoragePathResolver.location(for: rootURL, layout: layout),
                    platform: .windows,
                    environmentID: application.environmentID,
                    executables: [executable],
                    installedSize: application.storageBytes > 0 ? application.storageBytes : nil,
                    state: .installed
                )
            }
        }

        return result.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func relativePath(of file: URL, to root: URL) -> String? {
        let filePath = file.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = "/\(rootPath)/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}

nonisolated protocol GameInstallationManaging: Sendable {
    func install(
        _ game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform,
        providerRegistry: GameStoreProviderRegistry,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws -> URL?

    func update(
        _ game: StoreLibraryGame,
        providerRegistry: GameStoreProviderRegistry,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws

    func verify(
        _ game: StoreLibraryGame,
        providerRegistry: GameStoreProviderRegistry,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws

    func uninstall(
        _ game: StoreLibraryGame,
        providerRegistry: GameStoreProviderRegistry
    ) async throws
}

/// Provider-specific install mechanics stay in the existing adapters. This
/// service owns the provider boundary and returns the canonical installed URL
/// when an adapter can determine it (notably GOG).
nonisolated struct InstallationService: GameInstallationManaging {
    func install(
        _ game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform,
        providerRegistry: GameStoreProviderRegistry,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws -> URL? {
        let provider = try providerRegistry.provider(for: game.provider)
        try await provider.install(game, destinationRoot: destinationRoot, platform: platform, progress: progress)
        return await provider.installationURL(for: game, destinationRoot: destinationRoot, platform: platform)
    }

    func update(
        _ game: StoreLibraryGame,
        providerRegistry: GameStoreProviderRegistry,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        let provider = try providerRegistry.provider(for: game.provider)
        try await provider.update(game, progress: progress)
    }

    func verify(
        _ game: StoreLibraryGame,
        providerRegistry: GameStoreProviderRegistry,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        let provider = try providerRegistry.provider(for: game.provider)
        try await provider.verify(game, progress: progress)
    }

    func uninstall(
        _ game: StoreLibraryGame,
        providerRegistry: GameStoreProviderRegistry
    ) async throws {
        let provider = try providerRegistry.provider(for: game.provider)
        try await provider.uninstall(game)
    }
}

// MARK: - Execution service

/// Compatibility profiles already existed in Boreal under the more explicit
/// `WineCompatibilityProfile` name. Keep one model and expose the architecture
/// vocabulary without creating a second disconnected Codable type.
typealias CompatibilityProfile = WineCompatibilityProfile

nonisolated enum ExecutionState: Hashable, Sendable {
    case idle
    case preparing
    case launching
    case running
    case terminated(exitCode: Int32?)
    case failed(String)
}

/// Immutable description of one launch. The low-level runner still receives
/// `WindowsLaunchPlan` for compatibility with existing adapters, but the
/// application creates this value before any process is started.
nonisolated struct LaunchPlan: Codable, Hashable, Sendable {
    let applicationID: UUID
    let installationID: UUID?
    let environmentID: UUID
    let runtimeID: String
    let provider: GameLibraryProvider?
    let externalID: String?
    let executable: URL
    let workingDirectory: URL
    let arguments: [String]
    let environmentVariables: [String: String]
    let graphicsBackend: GraphicsBackend
    let graphicsStack: GraphicsStack?
    let compatibilityProfile: WineCompatibilityProfile?
    let overlayCompatibleFullscreen: Bool
    let overlayDisplayID: UInt32?

    init(
        applicationID: UUID,
        installationID: UUID?,
        environmentID: UUID,
        runtimeID: String,
        provider: GameLibraryProvider?,
        externalID: String?,
        windowsPlan: WindowsLaunchPlan,
        graphicsBackend: GraphicsBackend,
        compatibilityProfile: WineCompatibilityProfile?,
        graphicsStack: GraphicsStack? = nil
    ) {
        self.applicationID = applicationID
        self.installationID = installationID
        self.environmentID = environmentID
        self.runtimeID = runtimeID
        self.provider = provider
        self.externalID = externalID
        executable = windowsPlan.executable
        workingDirectory = windowsPlan.workingDirectory
        arguments = windowsPlan.arguments
        environmentVariables = windowsPlan.environment
        self.graphicsBackend = graphicsBackend
        self.graphicsStack = graphicsStack
        self.compatibilityProfile = compatibilityProfile
        overlayCompatibleFullscreen = windowsPlan.overlayCompatibleFullscreen
        overlayDisplayID = windowsPlan.overlayDisplayID
    }

    var windowsPlan: WindowsLaunchPlan {
        WindowsLaunchPlan(
            executable: executable,
            arguments: arguments,
            environment: environmentVariables,
            workingDirectory: workingDirectory,
            overlayCompatibleFullscreen: overlayCompatibleFullscreen,
            overlayDisplayID: overlayDisplayID
        )
    }
}

nonisolated struct LaunchSession: Identifiable, Hashable, Sendable {
    let id: UUID
    let applicationID: UUID
    let installationID: UUID?
    let environmentID: UUID
    let runtimeID: String
    let plan: LaunchPlan
    let processSession: WindowsProcessSession
    let startedAt: Date
}

nonisolated protocol LaunchCoordinating: Sendable {
    func makeStoreLaunchPlan(
        for game: StoreLibraryGame,
        runtime: InstalledRuntime,
        environment: ManagedBorealEnvironment,
        providerRegistry: GameStoreProviderRegistry
    ) async throws -> WindowsLaunchPlan

    func start(
        plan: LaunchPlan,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) async throws -> LaunchSession
}

actor LaunchCoordinator: LaunchCoordinating {
    private let processRunner: any WindowsProcessRunning

    init(processRunner: any WindowsProcessRunning) {
        self.processRunner = processRunner
    }

    func makeStoreLaunchPlan(
        for game: StoreLibraryGame,
        runtime: InstalledRuntime,
        environment: ManagedBorealEnvironment,
        providerRegistry: GameStoreProviderRegistry
    ) async throws -> WindowsLaunchPlan {
        let provider = try providerRegistry.provider(for: game.provider)
        return try await provider.launchPlan(for: game, runtime: runtime, environment: environment)
    }

    func start(
        plan: LaunchPlan,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) async throws -> LaunchSession {
        let processSession = try await processRunner.run(
            plan: plan.windowsPlan,
            environment: environment,
            runtime: runtime
        )
        return LaunchSession(
            id: UUID(),
            applicationID: plan.applicationID,
            installationID: plan.installationID,
            environmentID: plan.environmentID,
            runtimeID: plan.runtimeID,
            plan: plan,
            processSession: processSession,
            startedAt: processSession.startedAt
        )
    }
}

// MARK: - Activity service

/// Keeps playtime mutations independent from launch/process state. The store
/// remains the owner of UI-facing arrays and checkpoint task scheduling.
nonisolated struct ActivityService: Sendable {
    func begin(
        application: WindowsApplication,
        games: inout [StoreLibraryGame],
        at date: Date
    ) -> GamePlaySession? {
        guard let provider = application.storeProvider,
              let externalID = application.storeExternalID,
              let index = games.firstIndex(where: { $0.provider == provider && $0.externalID == externalID }) else { return nil }
        if let unfinished = games[index].activePlaySession { return unfinished }
        let session = GamePlaySession(startedAt: date, endedAt: nil, measuredDurationSeconds: 0, lastCheckpointAt: date)
        games[index].appendPlaySession(session)
        return session
    }

    func checkpoint(
        sessionID: UUID,
        application: WindowsApplication,
        games: inout [StoreLibraryGame],
        elapsed: TimeInterval,
        at date: Date
    ) {
        guard let provider = application.storeProvider,
              let externalID = application.storeExternalID,
              let gameIndex = games.firstIndex(where: { $0.provider == provider && $0.externalID == externalID }),
              var session = games[gameIndex].playSessions?.first(where: { $0.id == sessionID }) else { return }
        session.checkpoint(elapsed: elapsed, at: date)
        games[gameIndex].updatePlaySession(session)
    }

    func finish(
        sessionID: UUID?,
        application: WindowsApplication,
        games: inout [StoreLibraryGame],
        at date: Date
    ) {
        guard let provider = application.storeProvider,
              let externalID = application.storeExternalID,
              let gameIndex = games.firstIndex(where: { $0.provider == provider && $0.externalID == externalID }),
              var session = sessionID.flatMap({ id in games[gameIndex].playSessions?.first(where: { $0.id == id }) }) ?? games[gameIndex].activePlaySession else { return }
        session.finish(at: date)
        games[gameIndex].updatePlaySession(session)
    }
}
