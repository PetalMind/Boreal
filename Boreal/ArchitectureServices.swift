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
        let location = resolvedLocation(for: installation, layout: layout, fileManager: fileManager)
        let persistedLocation = StoragePathResolver.resolve(installation.location, layout: layout)
        if location.standardizedFileURL.path != persistedLocation.standardizedFileURL.path {
            resolved.location = StoragePathResolver.location(for: location, layout: layout)
            resolved.updatedAt = .now
        }
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
        if let volumeUUID = installation.volumeIdentity?.volumeUUID,
           !mountedVolumeUUIDs(fileManager: fileManager).contains(volumeUUID) {
            return .volumeUnavailable
        }
        let location = resolvedLocation(for: installation, layout: layout, fileManager: fileManager)
        guard fileManager.fileExists(atPath: location.path) else {
            return .missing
        }
        if let executable = installation.selectedExecutableID.flatMap({ id in
            installation.executables.first(where: { $0.id == id })
        }) ?? installation.executables.first(where: { $0.role == .game }) {
            let executableURL = location.appending(path: executable.relativePath)
            guard fileManager.fileExists(atPath: executableURL.path) else { return .missing }
        }
        switch installation.state {
        case .broken, .uninstalled: return installation.state
        case .unknown, .installing, .installed, .missing, .volumeUnavailable: return .installed
        }
    }

    static func resolvedLocation(
        for installation: GameInstallation,
        layout: BorealStorageLayout,
        fileManager: FileManager = .default
    ) -> URL {
        let persisted = StoragePathResolver.resolve(installation.location, layout: layout)
        guard case .external = installation.location,
              let identity = installation.volumeIdentity else { return persisted }

        if let volumeUUID = identity.volumeUUID,
           let volumeURL = mountedVolumeURL(withUUID: volumeUUID, fileManager: fileManager),
           let relativePath = identity.relativePath {
            let relative = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty
                ? volumeURL.standardizedFileURL
                : volumeURL.appendingPathComponent(relative, isDirectory: true).standardizedFileURL
        }

        if let bookmark = identity.securityScopedBookmark {
            var isStale = false
            if let bookmarked = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale {
                return bookmarked.standardizedFileURL
            }
        }
        return persisted
    }

    private static func mountedVolumeUUIDs(fileManager: FileManager) -> Set<String> {
        Set(mountedVolumes(fileManager: fileManager).compactMap { url in
            (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? nil
        })
    }

    private static func mountedVolumeURL(withUUID uuid: String, fileManager: FileManager) -> URL? {
        mountedVolumes(fileManager: fileManager).first { url in
            (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) == uuid
        }
    }

    private static func mountedVolumes(fileManager: FileManager) -> [URL] {
        fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey],
            options: []
        ) ?? []
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
                state: .installed,
                volumeIdentity: InstallationVolumeIdentity.capture(
                    at: URL(fileURLWithPath: path, isDirectory: true),
                    location: StoragePathResolver.location(
                        for: URL(fileURLWithPath: path, isDirectory: true),
                        layout: layout
                    )
                ),
                preparationState: game.installedPlatform == .nativeMacOS || game.provider == .steam ? .ready : .notPrepared,
                installedAt: .now,
                lastSeenAt: .now
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
                installation.preparationState = .ready
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
                    state: .installed,
                    volumeIdentity: InstallationVolumeIdentity.capture(at: rootURL, location: StoragePathResolver.location(for: rootURL, layout: layout)),
                    preparationState: .ready,
                    installedAt: .now,
                    lastSeenAt: .now
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
    let traceID: OperationTraceID
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
    let prefixMode: WinePrefixMode
    let windowsVersion: WineWindowsVersion
    let directXAPI: GraphicsAPI
    let dependencies: [RuntimeDependency]
    let environmentPurpose: EnvironmentPurpose
    let executableArchitecture: WindowsExecutableArchitecture
    let overlayCompatibleFullscreen: Bool
    let overlayDisplayID: UInt32?
    let sessionScope: SessionScope
    let processExecutableName: String?
    let processExecutablePath: String?
    let temporalUpscalingPlan: TemporalUpscalingPlan?
    let configurationFingerprint: String?

    init(
        traceID: OperationTraceID? = nil,
        applicationID: UUID,
        installationID: UUID?,
        environmentID: UUID,
        runtimeID: String,
        provider: GameLibraryProvider?,
        externalID: String?,
        windowsPlan: WindowsLaunchPlan,
        graphicsBackend: GraphicsBackend,
        compatibilityProfile: WineCompatibilityProfile?,
        graphicsStack: GraphicsStack? = nil,
        prefixMode: WinePrefixMode = .wow64,
        windowsVersion: WineWindowsVersion = .windows11,
        directXAPI: GraphicsAPI = .automatic,
        dependencies: [RuntimeDependency] = [],
        environmentPurpose: EnvironmentPurpose = .game,
        executableArchitecture: WindowsExecutableArchitecture = .unknown,
        sessionScope: SessionScope? = nil,
        processExecutableName: String? = nil,
        processExecutablePath: String? = nil,
        temporalUpscalingPlan: TemporalUpscalingPlan? = nil,
        configurationFingerprint: String? = nil
    ) {
        // Keep the façade deterministic for callers that only describe a
        // plan, while the orchestration path passes a fresh operation trace
        // explicitly for every real launch.
        self.traceID = traceID ?? windowsPlan.traceID ?? OperationTraceID(applicationID)
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
        self.prefixMode = prefixMode
        self.windowsVersion = windowsVersion
        self.directXAPI = directXAPI
        self.dependencies = dependencies
        self.environmentPurpose = environmentPurpose
        self.executableArchitecture = executableArchitecture
        overlayCompatibleFullscreen = windowsPlan.overlayCompatibleFullscreen
        overlayDisplayID = windowsPlan.overlayDisplayID
        self.sessionScope = sessionScope ?? windowsPlan.sessionScope
        self.processExecutableName = processExecutableName ?? windowsPlan.processExecutableName
        self.processExecutablePath = processExecutablePath ?? windowsPlan.processExecutablePath
        self.temporalUpscalingPlan = temporalUpscalingPlan ?? windowsPlan.temporalUpscalingPlan
        self.configurationFingerprint = configurationFingerprint ?? windowsPlan.configurationFingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case traceID, applicationID, installationID, environmentID, runtimeID, provider, externalID
        case executable, workingDirectory, arguments, environmentVariables, graphicsBackend, graphicsStack
        case compatibilityProfile, prefixMode, windowsVersion, directXAPI, dependencies, environmentPurpose
        case executableArchitecture, overlayCompatibleFullscreen, overlayDisplayID, sessionScope
        case processExecutableName, processExecutablePath, temporalUpscalingPlan, configurationFingerprint
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        applicationID = try values.decode(UUID.self, forKey: .applicationID)
        traceID = try values.decodeIfPresent(OperationTraceID.self, forKey: .traceID) ?? OperationTraceID(applicationID)
        installationID = try values.decodeIfPresent(UUID.self, forKey: .installationID)
        environmentID = try values.decode(UUID.self, forKey: .environmentID)
        runtimeID = try values.decode(String.self, forKey: .runtimeID)
        provider = try values.decodeIfPresent(GameLibraryProvider.self, forKey: .provider)
        externalID = try values.decodeIfPresent(String.self, forKey: .externalID)
        executable = try values.decode(URL.self, forKey: .executable)
        workingDirectory = try values.decode(URL.self, forKey: .workingDirectory)
        arguments = try values.decode([String].self, forKey: .arguments)
        environmentVariables = try values.decode([String: String].self, forKey: .environmentVariables)
        graphicsBackend = try values.decode(GraphicsBackend.self, forKey: .graphicsBackend)
        graphicsStack = try values.decodeIfPresent(GraphicsStack.self, forKey: .graphicsStack)
        compatibilityProfile = try values.decodeIfPresent(WineCompatibilityProfile.self, forKey: .compatibilityProfile)
        prefixMode = try values.decodeIfPresent(WinePrefixMode.self, forKey: .prefixMode) ?? .wow64
        windowsVersion = try values.decodeIfPresent(WineWindowsVersion.self, forKey: .windowsVersion) ?? .windows11
        directXAPI = try values.decodeIfPresent(GraphicsAPI.self, forKey: .directXAPI) ?? .automatic
        dependencies = try values.decodeIfPresent([RuntimeDependency].self, forKey: .dependencies) ?? []
        environmentPurpose = try values.decodeIfPresent(EnvironmentPurpose.self, forKey: .environmentPurpose) ?? .game
        executableArchitecture = try values.decodeIfPresent(WindowsExecutableArchitecture.self, forKey: .executableArchitecture) ?? .unknown
        overlayCompatibleFullscreen = try values.decodeIfPresent(Bool.self, forKey: .overlayCompatibleFullscreen) ?? false
        overlayDisplayID = try values.decodeIfPresent(UInt32.self, forKey: .overlayDisplayID)
        sessionScope = try values.decodeIfPresent(SessionScope.self, forKey: .sessionScope) ?? .exclusiveEnvironment
        processExecutableName = try values.decodeIfPresent(String.self, forKey: .processExecutableName)
        processExecutablePath = try values.decodeIfPresent(String.self, forKey: .processExecutablePath)
        temporalUpscalingPlan = try values.decodeIfPresent(TemporalUpscalingPlan.self, forKey: .temporalUpscalingPlan)
        configurationFingerprint = try values.decodeIfPresent(String.self, forKey: .configurationFingerprint)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(traceID, forKey: .traceID)
        try values.encode(applicationID, forKey: .applicationID)
        try values.encodeIfPresent(installationID, forKey: .installationID)
        try values.encode(environmentID, forKey: .environmentID)
        try values.encode(runtimeID, forKey: .runtimeID)
        try values.encodeIfPresent(provider, forKey: .provider)
        try values.encodeIfPresent(externalID, forKey: .externalID)
        try values.encode(executable, forKey: .executable)
        try values.encode(workingDirectory, forKey: .workingDirectory)
        try values.encode(arguments, forKey: .arguments)
        try values.encode(environmentVariables, forKey: .environmentVariables)
        try values.encode(graphicsBackend, forKey: .graphicsBackend)
        try values.encodeIfPresent(graphicsStack, forKey: .graphicsStack)
        try values.encodeIfPresent(compatibilityProfile, forKey: .compatibilityProfile)
        try values.encode(prefixMode, forKey: .prefixMode)
        try values.encode(windowsVersion, forKey: .windowsVersion)
        try values.encode(directXAPI, forKey: .directXAPI)
        try values.encode(dependencies, forKey: .dependencies)
        try values.encode(environmentPurpose, forKey: .environmentPurpose)
        try values.encode(executableArchitecture, forKey: .executableArchitecture)
        try values.encode(overlayCompatibleFullscreen, forKey: .overlayCompatibleFullscreen)
        try values.encodeIfPresent(overlayDisplayID, forKey: .overlayDisplayID)
        try values.encode(sessionScope, forKey: .sessionScope)
        try values.encodeIfPresent(processExecutableName, forKey: .processExecutableName)
        try values.encodeIfPresent(processExecutablePath, forKey: .processExecutablePath)
        try values.encodeIfPresent(temporalUpscalingPlan, forKey: .temporalUpscalingPlan)
        try values.encodeIfPresent(configurationFingerprint, forKey: .configurationFingerprint)
    }

    var windowsPlan: WindowsLaunchPlan {
        WindowsLaunchPlan(
            traceID: traceID,
            executable: executable,
            arguments: arguments,
            environment: environmentVariables,
            workingDirectory: workingDirectory,
            overlayCompatibleFullscreen: overlayCompatibleFullscreen,
            overlayDisplayID: overlayDisplayID,
            sessionScope: sessionScope,
            processExecutableName: processExecutableName,
            processExecutablePath: processExecutablePath,
            temporalUpscalingPlan: temporalUpscalingPlan,
            configurationFingerprint: configurationFingerprint
        )
    }
}

nonisolated protocol GameSessionCoordinating: Sendable {
    func waitForEnd(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
}

actor GameSessionCoordinator: GameSessionCoordinating {
    private let processRunner: any WindowsProcessRunning

    init(processRunner: any WindowsProcessRunning) {
        self.processRunner = processRunner
    }

    func waitForEnd(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        switch session.sessionScope {
        case .exclusiveEnvironment:
            try await processRunner.waitForEnvironmentSessionEnd(environment: environment, runtime: runtime)
        case .processGroup:
            try await processRunner.waitForProcessGroupEnd(session: session, environment: environment, runtime: runtime)
        }
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
        let recipe = try await provider.launchRecipe(for: game, runtime: runtime, environment: environment)
        var plan = recipe.windowsPlan
        plan.sessionScope = recipe.sessionPolicy
        return plan
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
