import Foundation

nonisolated protocol GameModManaging: Sendable {
    var adapter: ModGameAdapter { get }

    func inspect(archive: URL, gameID: UUID) throws -> ModInstallPreview
    func inspect(archive: URL, gameID: UUID, gameRoot: URL?, pluginsFile: URL?) throws -> ModInstallPreview
    func discardPreview(_ preview: ModInstallPreview)
    func load(gameID: UUID, gameRoot: URL?, pluginsFile: URL?, profileID: String?, auxiliaryRoot: URL?) throws -> ModGameState
    func install(preview: ModInstallPreview, gameRoot: URL?, pluginsFile: URL?, profileID: String, auxiliaryRoot: URL?) throws -> ModGameState
    func saveProfile(gameID: UUID, profileID: String, profileName: String, mods: [InstalledMod], plugins: [BethesdaPlugin]) throws
    func deploy(state: ModGameState, gameRoot: URL?, pluginsFile: URL?) throws -> ModGameState
    func profiles(for gameID: UUID) -> [ModProfileDescriptor]
    func createProfile(name: String, from state: ModGameState) throws -> ModGameState
    func removeMod(_ modID: UUID, from state: ModGameState) throws -> ModGameState
    func stagedModURL(gameID: UUID, modID: UUID) -> URL?
    func activateProfile(_ profileID: String, for gameID: UUID) throws
    func deploymentHealth(for state: ModGameState, gameRoot: URL?, pluginsFile: URL?, auxiliaryRoot: URL?) -> ModDeploymentHealth
    func repairRuntime(gameRoot: URL?) throws -> ModRuntimeState?
    func launchArguments(for gameRoot: URL?) -> [String]
}

nonisolated extension GameModManaging {
    func inspect(archive: URL, gameID: UUID, gameRoot: URL?, pluginsFile: URL?) throws -> ModInstallPreview {
        try inspect(archive: archive, gameID: gameID)
    }
}

extension ModManager: GameModManaging {
    var adapter: ModGameAdapter { .skyrimSpecialEdition }

    func repairRuntime(gameRoot: URL?) throws -> ModRuntimeState? { nil }

    func launchArguments(for gameRoot: URL?) -> [String] { [] }
}
