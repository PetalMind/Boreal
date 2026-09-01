import Foundation

nonisolated struct GameStoreProviderCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let library = Self(rawValue: 1 << 0)
    static let details = Self(rawValue: 1 << 1)
    static let sizeEstimate = Self(rawValue: 1 << 2)
    static let directInstall = Self(rawValue: 1 << 3)
    static let update = Self(rawValue: 1 << 4)
    static let verify = Self(rawValue: 1 << 5)
    static let uninstall = Self(rawValue: 1 << 6)
    static let launchPlan = Self(rawValue: 1 << 7)
    static let clientManagedInstall = Self(rawValue: 1 << 8)
}

nonisolated enum GameStoreProviderError: LocalizedError, Sendable {
    case unavailable(GameLibraryProvider)
    case unsupported(GameLibraryProvider, String)
    case installationMissing(GameLibraryProvider)

    var errorDescription: String? {
        switch self {
        case .unavailable(let provider):
            "The \(provider.rawValue) provider is not available."
        case .unsupported(let provider, let operation):
            "\(provider.rawValue) does not support \(operation) through Boreal."
        case .installationMissing(let provider):
            "Boreal could not find the installed \(provider.rawValue) game files."
        }
    }
}

/// Provider-neutral boundary for store library and game lifecycle operations.
/// Authentication stays in the account-specific services because each provider
/// has a different connection state and authorization flow.
nonisolated protocol GameStoreProvider: Sendable {
    var provider: GameLibraryProvider { get }
    var capabilities: GameStoreProviderCapabilities { get }

    func library() async throws -> [StoreLibraryGame]
    func details(for game: StoreLibraryGame) async -> StoreLibraryGame
    func sizeEstimate(for game: StoreLibraryGame, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate?
    func install(
        _ game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws
    func installationURL(
        for game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform
    ) async -> URL?
    func update(
        _ game: StoreLibraryGame,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws
    func verify(
        _ game: StoreLibraryGame,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws
    func uninstall(_ game: StoreLibraryGame) async throws
    func launchPlan(
        for game: StoreLibraryGame,
        runtime: InstalledRuntime,
        environment: ManagedBorealEnvironment
    ) async throws -> WindowsLaunchPlan
}

extension GameStoreProvider {
    func details(for game: StoreLibraryGame) async -> StoreLibraryGame { game }

    func sizeEstimate(for game: StoreLibraryGame, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate? {
        _ = game
        _ = platform
        return nil
    }

    func install(
        _ game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        _ = destinationRoot
        _ = platform
        _ = progress
        throw GameStoreProviderError.unsupported(provider, "direct installation")
    }

    func installationURL(
        for game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform
    ) async -> URL? {
        _ = game
        _ = destinationRoot
        _ = platform
        return nil
    }

    func update(
        _ game: StoreLibraryGame,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        _ = game
        _ = progress
        throw GameStoreProviderError.unsupported(provider, "updates")
    }

    func verify(
        _ game: StoreLibraryGame,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        _ = game
        _ = progress
        throw GameStoreProviderError.unsupported(provider, "file verification")
    }

    func uninstall(_ game: StoreLibraryGame) async throws {
        _ = game
        throw GameStoreProviderError.unsupported(provider, "uninstallation")
    }

    func launchPlan(
        for game: StoreLibraryGame,
        runtime: InstalledRuntime,
        environment: ManagedBorealEnvironment
    ) async throws -> WindowsLaunchPlan {
        _ = game
        _ = runtime
        _ = environment
        throw GameStoreProviderError.unsupported(provider, "direct launch plans")
    }
}

nonisolated struct GameStoreProviderRegistry: Sendable {
    private let providers: [GameLibraryProvider: any GameStoreProvider]

    init(_ providers: [any GameStoreProvider]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.provider, $0) })
    }

    func provider(for id: GameLibraryProvider) throws -> any GameStoreProvider {
        guard let provider = providers[id] else { throw GameStoreProviderError.unavailable(id) }
        return provider
    }

    func capabilities(for id: GameLibraryProvider) -> GameStoreProviderCapabilities {
        providers[id]?.capabilities ?? []
    }
}

nonisolated struct SteamGameStoreProvider: GameStoreProvider {
    let provider = GameLibraryProvider.steam
    let capabilities: GameStoreProviderCapabilities = [.library, .details, .sizeEstimate, .clientManagedInstall]
    private let libraryService: any SteamLibraryLoading

    init(libraryService: any SteamLibraryLoading) {
        self.libraryService = libraryService
    }

    func library() async throws -> [StoreLibraryGame] {
        try await libraryService.loadLibrary()
    }

    func details(for game: StoreLibraryGame) async -> StoreLibraryGame {
        await libraryService.loadDetails(for: game)
    }

    func sizeEstimate(for game: StoreLibraryGame, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate? {
        _ = platform
        return await libraryService.loadDetails(for: game).sizeEstimate
    }
}

nonisolated struct EpicGameStoreProvider: GameStoreProvider {
    let provider = GameLibraryProvider.epic
    let capabilities: GameStoreProviderCapabilities = [
        .library, .sizeEstimate, .directInstall, .update, .verify, .uninstall, .launchPlan,
    ]
    private let service: any EpicLibraryProviding

    init(service: any EpicLibraryProviding) {
        self.service = service
    }

    func library() async throws -> [StoreLibraryGame] { try await service.loadLibrary() }

    func sizeEstimate(for game: StoreLibraryGame, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate? {
        try await service.loadSizeEstimate(appID: game.externalID, platform: platform)
    }

    func install(
        _ game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        try await service.install(appID: game.externalID, destinationRoot: destinationRoot, platform: platform, progress: progress)
    }

    func update(_ game: StoreLibraryGame, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        try await service.update(appID: game.externalID, progress: progress)
    }

    func verify(_ game: StoreLibraryGame, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        try await service.verify(appID: game.externalID, progress: progress)
    }

    func uninstall(_ game: StoreLibraryGame) async throws {
        try await service.uninstall(appID: game.externalID)
    }

    func launchPlan(for game: StoreLibraryGame, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan {
        try await service.launchPlan(appID: game.externalID, runtime: runtime, environment: environment)
    }
}

nonisolated struct GOGGameStoreProvider: GameStoreProvider {
    let provider = GameLibraryProvider.gog
    let capabilities: GameStoreProviderCapabilities = [
        .library, .sizeEstimate, .directInstall, .update, .verify, .uninstall, .launchPlan,
    ]
    private let service: any GOGLibraryProviding

    init(service: any GOGLibraryProviding) {
        self.service = service
    }

    func library() async throws -> [StoreLibraryGame] { try await service.loadLibrary() }

    func sizeEstimate(for game: StoreLibraryGame, platform: StoreGameInstallationPlatform) async throws -> StoreGameSizeEstimate? {
        try await service.loadSizeEstimate(appID: game.externalID, platform: platform)
    }

    func install(
        _ game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform,
        progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void
    ) async throws {
        try await service.install(appID: game.externalID, destinationRoot: destinationRoot, platform: platform, progress: progress)
    }

    func installationURL(
        for game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform
    ) async -> URL? {
        await service.installationURL(appID: game.externalID, destinationRoot: destinationRoot, platform: platform)
    }

    func update(_ game: StoreLibraryGame, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        guard let path = game.installPath else { throw GameStoreProviderError.installationMissing(.gog) }
        try await service.update(
            appID: game.externalID,
            installationURL: URL(fileURLWithPath: path),
            platform: game.installedPlatform ?? .windows,
            progress: progress
        )
    }

    func verify(_ game: StoreLibraryGame, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws {
        guard let path = game.installPath else { throw GameStoreProviderError.installationMissing(.gog) }
        try await service.verify(
            appID: game.externalID,
            installationURL: URL(fileURLWithPath: path),
            platform: game.installedPlatform ?? .windows,
            progress: progress
        )
    }

    func uninstall(_ game: StoreLibraryGame) async throws {
        guard let path = game.installPath else { throw GameStoreProviderError.installationMissing(.gog) }
        let installationURL = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: installationURL.path) else {
            throw GameStoreProviderError.installationMissing(.gog)
        }
        _ = try FileManager.default.trashItem(at: installationURL, resultingItemURL: nil)
    }

    func launchPlan(for game: StoreLibraryGame, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan {
        guard let path = game.installPath else { throw GameStoreProviderError.installationMissing(.gog) }
        let installationURL = URL(fileURLWithPath: path, isDirectory: true)
        return try await service.launchPlan(
            appID: game.externalID,
            installationURL: installationURL,
            runtime: runtime,
            environment: environment
        )
    }
}
