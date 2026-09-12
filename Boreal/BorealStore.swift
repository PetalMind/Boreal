import Foundation
import Observation

private actor StoreSizeEstimateGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
@Observable
final class BorealStore {
    private struct ActivePlaySession {
        var sessionID: UUID
        var checkpointInstant: ContinuousClock.Instant
    }
    private struct PersistedState: Codable {
        var applications: [WindowsApplication]
        var environments: [WindowsEnvironment]
        var storeGames: [StoreLibraryGame]?
        var storeDownloads: [String: StoreDownloadRecord]?
        var favoriteKeys: [String]?
        var lastAutomaticLibraryRefreshAt: Date?
    }

    var applications: [WindowsApplication] = []
    var environments: [WindowsEnvironment] = []
    var storeGames: [StoreLibraryGame] = []
    /// Canonical installation records. `StoreLibraryGame` installation fields
    /// remain only as a compatibility bridge for provider payloads and old
    /// persisted files.
    private(set) var installations: [GameInstallation] = []
    /// Runtime/process state is separate from installation state. It is
    /// derived from the launch coordinator and environment monitor rather
    /// than persisted as part of catalog metadata.
    private(set) var executionStates: [UUID: ExecutionState] = [:]
    private(set) var favoriteKeys: Set<String> = []
    var librarySyncState: LibrarySyncState = .idle
    /// Each provider owns its own synchronization lifecycle. The legacy
    /// `librarySyncState` remains as an aggregate for existing UI callers.
    private(set) var librarySyncStates: [GameLibraryProvider: LibrarySyncState] = [:]
    var epicConnectionState: EpicConnectionState = .checking
    var gogConnectionState: GOGConnectionState = .checking
    var storeGameOperations: [String: StoreGameOperationState] = [:]
    var installation = InstallationProgress()
    var presentedIssue: BorealIssue?
    var runtimeStatuses: [RuntimeStatus] = []
    var localRuntimeCandidates: [LocalRuntimeCandidate] = []
    var runtimeDiscoveryState: RuntimeDiscoveryState = .loading
    var runtimeOperationDetail: String?
    var runtimeComponentUpdates: [RuntimeComponentUpdate] = []
    var runtimeComponentUpdateError: String?
    var discoverySearchMessage: String?
    private var discoverySearchResults: [AppleGamingWikiGame] = []
    private var discoverySearchQuery = ""
    var discoveryProducerResults: [AppleGamingWikiGame] = []
    var discoveryProducerSearchState: AppleGamingWikiDiscoveryState = .idle
    private var discoveryProducerQuery = ""
    var savedDiscoveryGames: [AppleGamingWikiGame] = []
    private let discoveryMetadataGate = StoreSizeEstimateGate(limit: 4)
    private let discoveryPriceGate = StoreSizeEstimateGate(limit: 4)
    var discoveryCatalog: AppleGamingWikiCatalog?
    var discoveryState: AppleGamingWikiDiscoveryState = .idle
    var discoveryPaginationState: AppleGamingWikiDiscoveryState = .idle
    var discoveryMetadata: [String: DiscoveryGameMetadata] = [:]
    var discoveryPriceSummaries: [String: DiscoveryPriceSummary] = [:]
    var discoveryGOGRevivedAvailability: [String: GOGRevivedAvailability] = [:]
    var environmentDependencyStatuses: [UUID: [RuntimeDependencyStatus]] = [:]
    var gameDiskReports: [UUID: GameDiskStorageReport] = [:]
    var diskStorageOperationIDs: Set<UUID> = []
    var gameRelocationProgress: String?
    private let storageURL: URL
    private let storageLayout: BorealStorageLayout
    private let libraryRepository: LibraryRepository
    private let usesLayeredStorage: Bool
    private let services: BorealServices
    private let graphicsCompatibilityManager = GraphicsCompatibilityManager()
    private var activeSessions: [UUID: WindowsProcessSession] = [:]
    /// Developer-mode diagnostics: the last immutable plan prepared for each
    /// application. It is not used as a mutable process command afterward.
    private(set) var lastLaunchPlans: [UUID: LaunchPlan] = [:]
    private var performanceLogURLs: [UUID: URL] = [:]
    private var performanceProcessIDs: [UUID: [Int32]] = [:]
    private var performanceProcessTasks: [UUID: Task<Void, Never>] = [:]
    private var activeEnvironments: [UUID: ManagedBorealEnvironment] = [:]
    private var activeRuntimes: [UUID: InstalledRuntime] = [:]
    private var requestedStops: Set<UUID> = []
    private var unexpectedLauncherFailures: Set<UUID> = []
    private var automaticRendererFallbacksPending: Set<UUID> = []
    private var automaticRendererFallbackLogURLs: Set<URL> = []
    private var environmentSessionStates: [UUID: EnvironmentSessionState] = [:]
    private var environmentMonitorIDs: [UUID: UUID] = [:]
    private var activePlaySessions: [UUID: ActivePlaySession] = [:]
    private var advancedConfigurations: [UUID: GameAdvancedConfiguration] = [:]
    /// Long-running reliability operations are keyed by their trace instead
    /// of sharing the older global loading flags used by store downloads.
    private(set) var operationStates: [OperationTraceID: BorealOperationState] = [:]
    private(set) var lastCompatibilityResolutions: [UUID: CompatibilityResolution] = [:]
    private(set) var lastLaunchDiagnoses: [UUID: LaunchFailureDiagnosis] = [:]
    private var playSessionCheckpointTasks: [UUID: Task<Void, Never>] = [:]
    private var storeOperationTasks: [String: Task<Void, Never>] = [:]
    private var storeOperationTokens: [String: UUID] = [:]
    private var storeDownloadRecords: [String: StoreDownloadRecord] = [:]
    private var lastDownloadRecordSave: [String: Date] = [:]
    private var steamMetadataRefreshes: Set<String> = []
    private var steamPresentationFallbacks: Set<String> = []
    private var storeSizeEstimateLoads: Set<String> = []
    private let storeSizeEstimateGate = StoreSizeEstimateGate(limit: 3)
    private var installationTask: Task<UUID?, Never>?
    private var installationToken: UUID?
    private var lastAutomaticLibraryRefreshAt: Date?
    private var isRunningAutomaticLibraryRefresh = false
    private var activeLibrarySyncs: Set<GameLibraryProvider> = []
    private var isEnrichingInstalledApplicationMetadata = false
    private var discoveryLoadTask: Task<Void, Never>?
    private var discoveryPaginationTask: Task<Void, Never>?
    private var discoveryEnrichmentTask: Task<Void, Never>?
    private var discoverySourceCatalog: AppleGamingWikiCatalog?
    private var discoveryMetadataLoads: Set<String> = []
    private var discoveryMetadataAccessOrder: [String] = []
    private var unavailableDiscoveryMetadata: Set<String> = []
    private var discoveryPriceLoads: Set<String> = []
    private var discoveryPriceAccessOrder: [String] = []
    private var discoveryOffersLoads: Set<String> = []
    private var loadedDiscoveryOffers: Set<String> = []
    private var discoveryGOGRevivedLoads: Set<String> = []

    private static let discoveryMetadataMemoryLimit = 128
    private static let discoveryPriceMemoryLimit = 128

    nonisolated static let automaticLibraryRefreshInterval: TimeInterval = 8 * 60 * 60
    nonisolated static let gameInstallationRootDefaultsKey = "gameInstallationRootPath"

    init(storageURL: URL? = nil, services: BorealServices? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let supportRoot = storageURL?.deletingLastPathComponent() ?? base.appending(path: "Boreal", directoryHint: .isDirectory)
        let layout = BorealStorageLayout(applicationSupportURL: supportRoot)
        self.storageLayout = layout
        self.storageURL = storageURL ?? layout.libraryURL
        self.libraryRepository = LibraryRepository(layout: layout)
        self.usesLayeredStorage = storageURL == nil
        self.services = services ?? .live(applicationSupportURL: (storageURL?.deletingLastPathComponent() ?? base.appending(path: "Boreal")))
        load()
        let savedDiscoveryURL = supportRoot.appending(path: "Discovery/saved-games.json")
        if FileManager.default.fileExists(atPath: savedDiscoveryURL.path) {
            do {
                savedDiscoveryGames = try JSONDecoder().decode([AppleGamingWikiGame].self, from: Data(contentsOf: savedDiscoveryURL))
            } catch {
                present(error, title: "Couldn’t read saved Discovery games", stage: "Reading your library")
            }
        }
        var didNormalizeApplicationState = false
        for index in applications.indices {
            var application = applications[index]
            if let gogIdentity = GOGInstalledGameDetector.detect(
                executable: URL(fileURLWithPath: application.executablePath)
            ), application.storeProvider != .gog || application.storeExternalID != gogIdentity.externalID {
                adoptGOGInstallationIdentity(gogIdentity, forApplicationAt: index)
                application = applications[index]
                didNormalizeApplicationState = true
            }
            if application.isSteamRuntimeHost, application.storeProvider == .steam {
                // Older builds used the host record as a fake game record. Keep
                // the installed bottle, but detach the host from any AppID so it
                // cannot make a game look installed or become its launch target.
                applications[index].name = "Steam for Windows"
                applications[index].publisher = "Valve"
                applications[index].storeProvider = nil
                applications[index].storeExternalID = nil
                applications[index].lastResult = "Steam for Windows manages downloads and launch"
                didNormalizeApplicationState = true
            }
            if application.storeProvider == .steam,
               application.installerPath == "steamcmd-windows-game",
               let environmentRecord = environments.first(where: { $0.id == application.environmentID }),
               let managed = managedEnvironment(from: environmentRecord),
               let steamExecutable = SteamWindowsService.steamExecutable(
                   in: managed,
                   discovered: URL(fileURLWithPath: application.executablePath)
               ) {
                applications[index].executablePath = steamExecutable.path
                applications[index].installerPath = "steam-windows-game"
                applications[index].lastResult = "Ready to launch through Windows Steam"
                didNormalizeApplicationState = true
            }
            let hasExecutable = FileManager.default.fileExists(atPath: application.executablePath)
            let hasRefreshableStoreInstallation: Bool = {
                guard let provider = application.storeProvider,
                      [.epic, .gog].contains(provider),
                      let externalID = application.storeExternalID else { return false }
                return storeGames.contains {
                    $0.provider == provider
                        && $0.externalID == externalID
                        && hasInstallation($0)
                }
            }()
            guard !hasExecutable && !hasRefreshableStoreInstallation else { continue }
            didNormalizeApplicationState = true
            applications[index].status = .unavailable
            applications[index].lastResult = "Executable unavailable"
            applications[index].lastFailureStage = "Checking application files"
            applications[index].lastErrorDetail = "The configured executable no longer exists at \(applications[index].executablePath)."
        }
        if didNormalizeApplicationState { save() }
        let recoveryAppIDs = applications.filter { $0.status == .running }.map(\.id)
        for index in applications.indices where [.running, .starting, .preparing].contains(applications[index].status) {
            applications[index].status = applications[index].status == .running ? .needsAttention : .ready
            if applications[index].status == .needsAttention {
                environmentSessionStates[applications[index].environmentID] = .unknown
            }
        }
        if !recoveryAppIDs.isEmpty { Task { [weak self] in await self?.recoverPersistedSessions(appIDs: recoveryAppIDs) } }
        Task {
            await normalizeLauncherRedirectors()
            await refreshRuntimeStatuses()
            await refreshMissingAuxiliaryExecutables()
            await enrichInstalledApplicationMetadata()
        }
    }

    func application(id: UUID) -> WindowsApplication? { applications.first { $0.id == id } }
    func storeGame(id: UUID) -> StoreLibraryGame? { storeGames.first { $0.id == id } }

    func launchPlanDiagnostics(for applicationID: UUID) -> String? {
        guard let plan = lastLaunchPlans[applicationID] else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? String(data: encoder.encode(plan), encoding: .utf8)
    }

    /// Resolves the actual executable and installed runtime at the orchestration
    /// boundary. The resolver owns heuristics; BorealStore only projects the
    /// result into observable state for SwiftUI.
    func resolveCompatibility(for applicationID: UUID) async -> CompatibilityResolution? {
        guard let application = application(id: applicationID) else { return nil }
        let executableURL = URL(fileURLWithPath: application.executablePath).standardizedFileURL
        let root = executableURL.deletingLastPathComponent()
        let inventory = await Task.detached(priority: .utility) {
            let analysis = ExecutableCompatibilityAnalyzer.analyze(
                root: root,
                applicationName: application.name,
                knownPrimary: executableURL
            )
            let architecture: ExecutableArchitecture? = switch WindowsExecutableArchitecture.inspect(executableURL) {
            case .x86: .x86
            case .x86_64: .x86_64
            case .unknown: nil
            }
            let relatedFiles = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ))?.filter {
                $0.pathExtension.caseInsensitiveCompare("dll") == .orderedSame
                    && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.prefix(64).map { $0 } ?? []
            return (analysis, architecture, relatedFiles)
        }.value
        let executable = GameExecutable(
            relativePath: executableURL.lastPathComponent,
            role: .game,
            architecture: inventory.1
        )
        let runtimes = (try? await services.runtimeManager.installedRuntimes()) ?? []
        let environmentRecord = environment(id: application.environmentID)
        let request = CompatibilityResolutionRequest(
            applicationID: applicationID,
            installation: storeGames.first(where: { $0.storeReference == application.storeReference }).flatMap { installation(for: $0) },
            executable: executable,
            executableAnalysis: inventory.0,
            storeReference: application.storeReference,
            gameProfile: application.storeProvider.flatMap { provider in
                application.storeExternalID.flatMap { GameGraphicsProfiles.profile(provider: provider, externalID: $0) }
            },
            userProfile: compatibilityProfile(for: application),
            installedRuntimes: runtimes,
            executableURL: executableURL,
            relatedFiles: inventory.2,
            prefixURL: environmentRecord?.prefixPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
        let trace = OperationTraceID()
        operationStates[trace] = BorealOperationState(id: trace, kind: .analyzingCompatibility, progress: nil, phase: "Analyzing executable and runtime capabilities", canCancel: false)
        let resolution = await services.compatibilityResolver.resolve(request)
        operationStates[trace] = BorealOperationState(id: trace, kind: .analyzingCompatibility, progress: 1, phase: "Compatibility analysis complete", canCancel: false)
        lastCompatibilityResolutions[applicationID] = resolution
        return resolution
    }

    func analyzeDependencies(for applicationID: UUID) async -> [DependencyRequirement] {
        guard let application = application(id: applicationID) else { return [] }
        let executable = URL(fileURLWithPath: application.executablePath).standardizedFileURL
        let root = executable.deletingLastPathComponent()
        let relatedFiles = await Task.detached(priority: .utility) {
            (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ))?.filter {
                $0.pathExtension.caseInsensitiveCompare("dll") == .orderedSame
            } ?? []
        }.value
        let prefix = environment(id: application.environmentID)?.prefixPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return await services.dependencyAnalyzer.analyze(
            executable: executable,
            relatedFiles: relatedFiles,
            prefixURL: prefix,
            userDependencies: compatibilityProfile(for: application).requiredDependencies
        )
    }

    func diagnoseLaunchFailure(
        for applicationID: UUID,
        stdout: String = "",
        stderr: String = "",
        wineLogs: [String] = [],
        rendererLogs: [String] = []
    ) async -> LaunchFailureDiagnosis? {
        guard let application = application(id: applicationID) else { return nil }
        let environmentRecord = environment(id: application.environmentID)
        let plan = lastLaunchPlans[applicationID]
        let managed = environmentRecord.flatMap(managedEnvironment(from:))
        let recentLogs = await recentLaunchLogs(in: managed?.logsURL)
        let runtime: InstalledRuntime?
        if let managed {
            runtime = try? await awaitRuntime(id: managed.runtimeID)
        } else {
            runtime = nil
        }
        let combinedStdout = [stdout, recentLogs.stdout].filter { !$0.isEmpty }.joined(separator: "\n")
        let combinedStderr = [stderr, recentLogs.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let input = LaunchFailureInput(
            exitCode: application.lastExitCode,
            stdout: combinedStdout,
            stderr: combinedStderr.isEmpty ? (application.lastErrorDetail ?? "") : combinedStderr,
            wineLogs: wineLogs + [recentLogs.stdout, recentLogs.stderr].filter { !$0.isEmpty },
            rendererLogs: rendererLogs + [recentLogs.stderr].filter { !$0.isEmpty },
            launchPlan: plan,
            runtime: runtime,
            environment: managed,
            dependencyStatuses: application.environmentID == environmentRecord?.id ? dependencyStatuses(for: application.environmentID, application: application) : []
        )
        let diagnosis = await services.launchFailureAnalyzer.analyze(input)
        lastLaunchDiagnoses[applicationID] = diagnosis
        return diagnosis
    }

    /// Runs only the confirmed, prefix-mutating repair currently supported by
    /// the diagnostic model. The caller owns the confirmation step; this
    /// method always snapshots the environment before installing anything.
    func repairLastLaunchFailure(for applicationID: UUID) async throws {
        let diagnosis: LaunchFailureDiagnosis?
        if let cachedDiagnosis = lastLaunchDiagnoses[applicationID] {
            diagnosis = cachedDiagnosis
        } else {
            diagnosis = await diagnoseLaunchFailure(for: applicationID)
        }
        guard let diagnosis else { throw LaunchRepairError.unsupported(.unknown) }
        guard diagnosis.category == .missingDependency else {
            throw LaunchRepairError.unsupported(diagnosis.category)
        }
        guard let application = application(id: applicationID),
              let record = environment(id: application.environmentID),
              let managed = managedEnvironment(from: record),
              let runtime = try await awaitRuntime(id: managed.runtimeID) else {
            throw InstallerServiceError.noRuntimeAvailable
        }

        let analyzed = await analyzeDependencies(for: applicationID)
        let analyzedMissing = analyzed.filter { !$0.isInstalled && $0.confidence == .high }.map(\.dependency)
        let statuses = dependencyStatuses(for: application.environmentID, application: application)
        let statusRequired = statuses
            .filter { ($0.state == .missing || $0.state == .failed) && $0.recommendation == .required }
            .map(\.dependency)
        let installed = Set(statuses.filter { $0.state == .installed }.map(\.dependency))
        let profileRequired = compatibilityProfile(for: application).requiredDependencies.filter { !installed.contains($0) }
        let dependencies = Set(analyzedMissing + statusRequired + profileRequired).sorted { $0.rawValue < $1.rawValue }
        guard !dependencies.isEmpty else { throw LaunchRepairError.noActionableDependency }

        let trace = OperationTraceID()
        operationStates[trace] = BorealOperationState(id: trace, kind: .repairingEnvironment, progress: 0, phase: "Preparing dependency repair")
        do {
            if FileManager.default.fileExists(atPath: managed.rootURL.appending(path: "environment.json").path) {
                _ = try await createEnvironmentSnapshot(for: application.environmentID, reason: .environmentRepair, traceID: trace)
            }
            for (index, dependency) in dependencies.enumerated() {
                operationStates[trace] = BorealOperationState(
                    id: trace,
                    kind: .repairingEnvironment,
                    progress: Double(index) / Double(max(dependencies.count, 1)),
                    phase: "Installing \(dependency.displayName)",
                    canCancel: false
                )
                try await services.environmentManager.install(dependency, in: managed, runtime: runtime)
            }
            refreshDependencies(for: application.environmentID, application: application)
            operationStates[trace] = BorealOperationState(id: trace, kind: .repairingEnvironment, progress: 1, phase: "Dependency repair complete", canCancel: false)
        } catch {
            operationStates[trace] = BorealOperationState(id: trace, kind: .repairingEnvironment, progress: nil, phase: error.localizedDescription, canCancel: false)
            throw error
        }
    }

    func createEnvironmentSnapshot(
        for environmentID: UUID,
        reason: SnapshotReason,
        traceID: OperationTraceID = OperationTraceID()
    ) async throws -> EnvironmentSnapshot {
        guard let record = environment(id: environmentID), let managed = managedEnvironment(from: record) else { throw SnapshotError.sourceMissing }
        operationStates[traceID] = BorealOperationState(id: traceID, kind: .creatingSnapshot, progress: 0, phase: "Creating environment snapshot")
        do {
            let snapshot = try await services.environmentSnapshotManager.createSnapshot(for: managed, reason: reason, traceID: traceID)
            operationStates[traceID] = BorealOperationState(id: traceID, kind: .creatingSnapshot, progress: 1, phase: "Snapshot published")
            return snapshot
        } catch {
            operationStates[traceID] = BorealOperationState(id: traceID, kind: .creatingSnapshot, progress: nil, phase: error.localizedDescription, canCancel: false)
            throw error
        }
    }

    func restoreEnvironmentSnapshot(
        _ snapshot: EnvironmentSnapshot,
        environmentID: UUID,
        preserveCurrent: Bool = true,
        traceID: OperationTraceID = OperationTraceID()
    ) async throws {
        guard let record = environment(id: environmentID), let managed = managedEnvironment(from: record) else { throw SnapshotError.sourceMissing }
        let active = activeEnvironments.values.contains { $0.id == environmentID } || activeSessions.values.contains { $0.environmentID == environmentID }
        operationStates[traceID] = BorealOperationState(id: traceID, kind: .restoringSnapshot, progress: 0, phase: "Checking active game sessions")
        guard !active else {
            operationStates[traceID] = BorealOperationState(id: traceID, kind: .restoringSnapshot, progress: nil, phase: SnapshotError.activeSession.localizedDescription, canCancel: false)
            throw SnapshotError.activeSession
        }
        do {
            for application in applications where application.environmentID == environmentID && !application.isInstallerOnly {
                _ = try? await createSaveBackup(for: application.id, trigger: .beforeSnapshotRestore)
            }
            let restored = try await services.environmentSnapshotManager.restore(snapshot, to: managed, activeSession: active, preserveCurrent: preserveCurrent, traceID: traceID)
            if let index = environments.firstIndex(where: { $0.id == environmentID }) {
                environments[index].windowsVersion = restored.configuration.windowsVersion
                environments[index].architecture = restored.configuration.architecture == "win32" ? "32-bit" : "64-bit"
                environments[index].graphics = restored.configuration.graphicsBackend.displayName
                environments[index].components = restored.configuration.requiredDependencies.map(\.displayName).sorted()
            }
            operationStates[traceID] = BorealOperationState(id: traceID, kind: .restoringSnapshot, progress: 1, phase: "Snapshot restored and environment validated", canCancel: false)
            save()
        } catch {
            operationStates[traceID] = BorealOperationState(id: traceID, kind: .restoringSnapshot, progress: nil, phase: error.localizedDescription, canCancel: false)
            throw error
        }
    }

    func environmentSnapshots(for environmentID: UUID) async -> [EnvironmentSnapshot] {
        await services.environmentSnapshotManager.snapshots(for: environmentID)
    }

    func deleteEnvironmentSnapshot(_ snapshot: EnvironmentSnapshot) async throws {
        try await services.environmentSnapshotManager.delete(snapshot)
    }

    func storageReport() async -> BorealStorageReport {
        let trace = OperationTraceID()
        operationStates[trace] = BorealOperationState(id: trace, kind: .calculatingStorage, progress: 0, phase: "Calculating Boreal storage usage")
        let report = await services.storageAnalyzer.scan(
            layout: storageLayout,
            applications: applications,
            storeGames: storeGames,
            environments: environments,
            installations: installations
        )
        operationStates[trace] = BorealOperationState(id: trace, kind: .calculatingStorage, progress: 1, phase: "Storage calculation complete", canCancel: false)
        return report
    }

    func clearShaderCache(for applicationID: UUID) async throws -> Int {
        guard let application = application(id: applicationID) else { return 0 }
        let gameURL = URL(fileURLWithPath: application.executablePath).deletingLastPathComponent()
        let prefixURL = environment(id: application.environmentID)?.prefixPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let backend = compatibilityProfile(for: application).graphicsBackend
        let manager = services.shaderCacheManager
        return try await Task.detached(priority: .utility) {
            let locations = manager.locations(gameURL: gameURL, prefixURL: prefixURL, backend: backend)
            try manager.clear(locations)
            return locations.filter(\.safeToDelete).count
        }.value
    }

    func advancedConfiguration(for applicationID: UUID) async -> GameAdvancedConfiguration {
        await services.advancedConfigurationStore.configuration(for: applicationID)
    }

    func updateAdvancedConfiguration(_ configuration: GameAdvancedConfiguration) async throws {
        try await services.advancedConfigurationStore.save(configuration)
        advancedConfigurations[configuration.applicationID] = configuration
    }

    func detectedSaveLocations(for applicationID: UUID) async -> [GameSaveLocation] {
        guard let application = application(id: applicationID) else { return [] }
        let executableURL = URL(fileURLWithPath: application.executablePath).standardizedFileURL
        let installationURL = storeGames.first(where: { $0.storeReference == application.storeReference })
            .flatMap { installedLocation(for: $0) }
            ?? executableURL.deletingLastPathComponent()
        let environmentURL = environment(id: application.environmentID)?.prefixPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let advanced = await services.advancedConfigurationStore.configuration(for: applicationID)
        let trace = OperationTraceID()
        operationStates[trace] = BorealOperationState(id: trace, kind: .scanningSaves, progress: 0, phase: "Scanning known save locations")
        let locations = await services.gameSaveManager.detect(
            applicationID: applicationID,
            installationURL: installationURL,
            prefixURL: environmentURL,
            manualRelativePaths: advanced.manualSavePaths
        )
        operationStates[trace] = BorealOperationState(id: trace, kind: .scanningSaves, progress: 1, phase: "Save location scan complete", canCancel: false)
        return locations
    }

    func saveBackups(for applicationID: UUID) async -> [GameSaveBackup] {
        await services.gameSaveManager.backups(for: applicationID)
    }

    func pruneSaveBackups(for applicationID: UUID, policy: SaveBackupRetentionPolicy = .default) async throws {
        _ = try await services.gameSaveManager.prune(applicationID: applicationID, policy: policy)
    }

    func createSaveBackup(for applicationID: UUID, trigger: SaveBackupTrigger = .manual) async throws -> GameSaveBackup {
        guard let application = application(id: applicationID) else { throw SaveManagerError.noSaveData }
        let executableURL = URL(fileURLWithPath: application.executablePath).standardizedFileURL
        let installationURL = storeGames.first(where: { $0.storeReference == application.storeReference })
            .flatMap { installedLocation(for: $0) }
            ?? executableURL.deletingLastPathComponent()
        let environmentURL = environment(id: application.environmentID)?.prefixPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let locations = await detectedSaveLocations(for: applicationID)
        let absoluteLocations = locations.compactMap { location -> URL? in
            if let environmentURL, location.relativePath.lowercased().hasPrefix("drive_c/") {
                return environmentURL.appending(path: location.relativePath, directoryHint: .isDirectory)
            }
            return installationURL.appending(path: location.relativePath, directoryHint: .isDirectory)
        }
        let trace = OperationTraceID()
        operationStates[trace] = BorealOperationState(id: trace, kind: .creatingSaveBackup, progress: 0, phase: "Backing up detected save locations")
        do {
            let backup = try await services.gameSaveManager.backup(applicationID: applicationID, locations: absoluteLocations, trigger: trigger, traceID: trace)
            operationStates[trace] = BorealOperationState(id: trace, kind: .creatingSaveBackup, progress: 1, phase: "Save backup created", canCancel: false)
            return backup
        } catch {
            operationStates[trace] = BorealOperationState(id: trace, kind: .creatingSaveBackup, progress: nil, phase: error.localizedDescription, canCancel: false)
            throw error
        }
    }

    func restoreSaveBackup(_ backup: GameSaveBackup) async throws {
        guard let application = application(id: backup.applicationID) else { throw SaveManagerError.invalidBackup }
        let executableURL = URL(fileURLWithPath: application.executablePath).standardizedFileURL
        let installationURL = storeGames.first(where: { $0.storeReference == application.storeReference })
            .flatMap { installedLocation(for: $0) }
            ?? executableURL.deletingLastPathComponent()
        let prefixURL = environment(id: application.environmentID)?.prefixPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let trace = backup.traceID
        operationStates[trace] = BorealOperationState(id: trace, kind: .creatingSaveBackup, progress: 0, phase: "Restoring save backup")
        do {
            try await services.gameSaveManager.restore(backup, allowedRoots: [installationURL] + (prefixURL.map { [$0] } ?? []))
            operationStates[trace] = BorealOperationState(id: trace, kind: .creatingSaveBackup, progress: 1, phase: "Save backup restored", canCancel: false)
        } catch {
            operationStates[trace] = BorealOperationState(id: trace, kind: .creatingSaveBackup, progress: nil, phase: error.localizedDescription, canCancel: false)
            throw error
        }
    }

    func copyDiagnostics(for applicationID: UUID) async -> String? {
        guard let application = application(id: applicationID) else { return nil }
        let plan = lastLaunchPlans[applicationID]
        let diagnosis = lastLaunchDiagnoses[applicationID]
        let configuration = await services.advancedConfigurationStore.configuration(for: applicationID)
        let temporalInspector = await temporalUpscalingInspector(for: applicationID)
        let optiScalerConfiguration: Any
        if let temporalInspector {
            let value = temporalInspector.temporalPlan.requested.optiScaler
            optiScalerConfiguration = [
                "enabled": value.enabled,
                "inputAPI": value.inputAPI?.rawValue ?? NSNull(),
                "outputUpscaler": value.outputUpscaler?.rawValue ?? NSNull(),
                "frameGeneration": value.frameGeneration.mode.rawValue,
                "proxyStrategy": value.proxyStrategy.displayName
            ] as [String: Any]
        } else {
            optiScalerConfiguration = NSNull()
        }
        let dlsstweaksConfiguration: Any
        if let temporalInspector {
            let value = temporalInspector.temporalPlan.requested.dlsstweaks
            dlsstweaksConfiguration = [
                "enabled": value.enabled,
                "forceDLAA": value.forceDLAA,
                "scalingRatio": value.scalingRatio ?? NSNull(),
                "presetOverride": value.presetOverride ?? NSNull(),
                "sharpening": value.sharpening ?? NSNull(),
                "autoExposureOverride": value.autoExposureOverride,
                "debugIndicatorEnabled": value.debugIndicatorEnabled
            ] as [String: Any]
        } else {
            dlsstweaksConfiguration = NSNull()
        }
        let temporalInterfaces: [[String: Any]] = temporalInspector?.game.detectedTemporalInterfaces.map { interface -> [String: Any] in
            [
                "kind": interface.kind.rawValue,
                "detected": interface.detected,
                "version": interface.version ?? NSNull(),
                "confidence": interface.confidence.rawValue,
                "sources": interface.sources.map(\.rawValue),
                "files": interface.fileURLs.map { redactedPath($0.path) }
            ]
        } ?? []
        func inspectorDictionary(_ make: (TemporalUpscalingInspectorSnapshot) -> [String: Any]) -> Any {
            guard let temporalInspector else { return NSNull() }
            return make(temporalInspector)
        }
        let managedDLSSRuntime = inspectorDictionary { inspector in
            [
                "installed": inspector.managedDLSSRuntime.installed,
                "version": inspector.managedDLSSRuntime.version ?? NSNull(),
                "sha256": inspector.managedDLSSRuntime.sha256 ?? NSNull()
            ]
        }
        let dlsstweaks = inspectorDictionary { inspector in
            [
                "installed": inspector.dlsstweaks.installed,
                "version": inspector.dlsstweaks.version ?? NSNull(),
                "sha256": inspector.dlsstweaks.sha256 ?? NSNull(),
                "supportedControls": inspector.dlsstweaksCapabilities?.supportedControls.map(\.rawValue).sorted() ?? []
            ]
        }
        let optiScaler = inspectorDictionary { inspector in
            [
                "installed": inspector.optiScaler.installed,
                "version": inspector.optiScaler.version ?? NSNull(),
                "sha256": inspector.optiScaler.sha256 ?? NSNull()
            ]
        }
        let metalFXCapability = inspectorDictionary { inspector in
            [
                "available": inspector.metalFX.available,
                "installed": inspector.metalFX.installed,
                "source": inspector.metalFX.source.rawValue,
                "supportsSpatial": inspector.metalFX.supportsSpatial,
                "supportsTemporal": inspector.metalFX.supportsTemporal,
                "requiredEnvironmentVariables": inspector.metalFX.requiredEnvironmentVariables,
                "requiredDLLs": inspector.metalFX.requiredDLLs
            ]
        }
        let ngxDebugIndicator = inspectorDictionary { inspector in
            [
                "available": inspector.ngxDebugIndicator.available,
                "enabled": inspector.ngxDebugIndicator.enabled ?? NSNull(),
                "detail": inspector.ngxDebugIndicator.detail
            ]
        }
        let launchPlan: Any
        if let plan {
            launchPlan = [
                "executable": redactedPath(plan.executable.path),
                "workingDirectory": redactedPath(plan.workingDirectory.path),
                "argumentCount": plan.arguments.count,
                "graphicsBackend": plan.graphicsBackend.rawValue,
                "prefixMode": plan.prefixMode.rawValue,
                "directXAPI": plan.directXAPI.rawValue,
                "environmentKeys": plan.environmentVariables.keys.sorted()
            ] as [String: Any]
        } else {
            launchPlan = NSNull()
        }
        var payload: [String: Any] = [
            "borealVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "game": application.name,
            "storeProvider": application.storeProvider?.rawValue ?? NSNull(),
            "storeExternalID": application.storeExternalID ?? NSNull(),
            "runtime": environment(id: application.environmentID)?.runtime ?? NSNull(),
            "environment": environment(id: application.environmentID)?.id.uuidString ?? NSNull(),
            "graphics": application.graphics,
            "lastExitCode": application.lastExitCode ?? NSNull(),
            "lastDiagnosticCategory": diagnosis?.category.rawValue ?? NSNull(),
            "lastDiagnosticSummary": diagnosis?.summary ?? NSNull()
        ]
        payload["detectedTemporalAPIs"] = temporalInspector?.game.detectedTemporalInterfaces.map { $0.kind.rawValue } ?? []
        payload["temporalInterfaces"] = temporalInterfaces
        payload["dlssDLLVersions"] = temporalInspector?.game.dlss?.version ?? NSNull()
        payload["dlssActiveFile"] = temporalInspector?.dlssRuntime.map { redactedPath($0.activeFileURL.path) } ?? NSNull()
        payload["dlssDLLFingerprints"] = temporalInspector?.dlssRuntime?.activeSHA256 ?? NSNull()
        payload["dlssRuntimeSource"] = temporalInspector?.dlssRuntime?.source.rawValue ?? NSNull()
        payload["managedDLSSRuntime"] = managedDLSSRuntime
        payload["dlsstweaks"] = dlsstweaks
        payload["dlsstweaksConfiguration"] = dlsstweaksConfiguration
        payload["optiScaler"] = optiScaler
        payload["optiScalerConfiguration"] = optiScalerConfiguration
        payload["temporalComponentVersions"] = temporalInspector?.temporalPlan.componentVersions ?? [:]
        payload["metalFXCapability"] = metalFXCapability
        payload["effectiveTemporalPath"] = temporalInspector?.temporalPlan.effective.rawValue ?? NSNull()
        payload["temporalCompatibility"] = temporalInspector?.temporalPlan.compatibility.label ?? NSNull()
        payload["temporalCompatibilityReason"] = temporalInspector?.temporalPlan.reason ?? NSNull()
        payload["temporalInjectionSafety"] = temporalInspector?.temporalPlan.injectionSafety.rawValue ?? NSNull()
        payload["temporalProxyStrategy"] = temporalInspector?.temporalPlan.proxyStrategy.displayName ?? NSNull()
        payload["frameGeneration"] = temporalInspector?.game.frameGeneration.support.rawValue ?? NSNull()
        payload["ngxDebugIndicator"] = ngxDebugIndicator
        payload["temporalConfigurationFingerprint"] = plan?.configurationFingerprint ?? NSNull()
        payload["traceID"] = plan?.traceID.description ?? NSNull()
        payload["launchPlan"] = launchPlan
        payload["dllOverrides"] = configuration.dllOverrides.map { ["library": $0.library, "mode": $0.mode.rawValue] }
        payload["environmentVariables"] = configuration.environmentVariables.filter(\.enabled).map(\.key)
        guard JSONSerialization.isValidJSONObject(payload), let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveCompatibilityReport(for applicationID: UUID) async throws -> LocalCompatibilityReport {
        guard let application = application(id: applicationID) else { throw CompatibilityReportError.noInstalledRuntime }
        let resolution: CompatibilityResolution?
        if let cachedResolution = lastCompatibilityResolutions[applicationID] {
            resolution = cachedResolution
        } else {
            resolution = await resolveCompatibility(for: applicationID)
        }
        guard let resolution,
              let runtimeID = resolution.runtimeRecommendation.runtimeID,
              let runtime = try await services.runtimeManager.installedRuntimes().first(where: { $0.id == runtimeID }) else {
            throw CompatibilityReportError.noInstalledRuntime
        }
        guard let graphicsStack = GraphicsStackCatalog.stack(for: resolution.recommendedGraphicsStack.backend) else {
            throw CompatibilityReportError.noGraphicsStack
        }
        let profile = compatibilityProfile(for: application)
        let configuration = await services.advancedConfigurationStore.configuration(for: applicationID)
        let notes = resolution.warnings.map(\.detail).joined(separator: " ")
        let runtimeFingerprint = [runtime.id, runtime.wineVersion, runtime.resolvedEngine.rawValue]
            .joined(separator: "|")
        var temporalConfigurationFingerprint = profile.upscalingBridge.rawValue
        if let temporalPlan = lastLaunchPlans[applicationID]?.temporalUpscalingPlan {
            temporalConfigurationFingerprint = temporalPlan.fingerprintSegment
        } else {
            var temporalConfiguration = profile.temporalUpscaling
            if temporalConfiguration.mode == .automatic, profile.upscalingBridge == .ngxToMetalFX {
                temporalConfiguration.mode = .metalFXBridge
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(temporalConfiguration),
               let value = String(data: data, encoding: .utf8) {
                temporalConfigurationFingerprint = value
            }
        }
        let fingerprint = ConfigurationFingerprint.make(
            runtimeFingerprint: runtimeFingerprint,
            graphicsStack: graphicsStack,
            componentVersions: runtime.features.map { ["runtime-features": String(describing: $0)] } ?? [:],
            prefixMode: resolution.recommendedPrefixMode,
            windowsVersion: resolution.recommendedWindowsVersion,
            dependencies: profile.requiredDependencies.sorted { $0.rawValue < $1.rawValue },
            dllOverrides: configuration.dllOverrides,
            environmentVariables: configuration.environmentVariables,
            upscalingConfiguration: temporalConfigurationFingerprint
        )
        let report = LocalCompatibilityReport(
            id: UUID(),
            applicationID: applicationID,
            gameVersion: nil,
            runtimeID: runtime.id,
            runtimeFingerprint: runtimeFingerprint,
            configurationFingerprint: fingerprint,
            graphicsStack: graphicsStack,
            windowsVersion: resolution.recommendedWindowsVersion,
            result: application.compatibility,
            notes: notes.isEmpty ? nil : notes,
            createdAt: .now,
            traceID: OperationTraceID()
        )
        try await services.compatibilityReports.save(report)
        return report
    }

    private func awaitRuntime(id: String) async throws -> InstalledRuntime? {
        try await services.runtimeManager.installedRuntimes().first { $0.id == id }
    }

    private func recentLaunchLogs(in directory: URL?) async -> (stdout: String, stderr: String) {
        guard let directory else { return ("", "") }
        return await Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let launchLogs = files.filter {
                guard (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
                let name = $0.lastPathComponent.lowercased()
                return name.hasPrefix("launch-") && (name.hasSuffix(".stdout.log") || name.hasSuffix(".stderr.log"))
            }.sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }

            func read(_ url: URL) -> String {
                guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
                defer { try? handle.close() }
                return String(decoding: (try? handle.read(upToCount: 512 * 1_024)) ?? Data(), as: UTF8.self)
            }

            let stdoutURL = launchLogs.first { $0.lastPathComponent.lowercased().hasSuffix(".stdout.log") }
            let stderrURL = launchLogs.first { $0.lastPathComponent.lowercased().hasSuffix(".stderr.log") }
            return (stdoutURL.map(read) ?? "", stderrURL.map(read) ?? "")
        }.value
    }

    private func redactedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return "<user-path>" }
        return "<user>" + String(path.dropFirst(home.count))
    }

    func renameCustomApplication(_ applicationID: UUID, to requestedName: String) {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = applications.firstIndex(where: { $0.id == applicationID }),
              !applications[index].isSteamRuntimeHost,
              (applications[index].storeProvider == nil || applications[index].usesStoreMetadataOnly) else { return }

        if applications[index].isInstallerOnly {
            applications[index].name = name
            applications[index].publisher = "Game installer"
            applications[index].lastResult = "Installer renamed"
            if let environmentIndex = environments.firstIndex(where: { $0.id == applications[index].environmentID }) {
                environments[environmentIndex].name = name
            }
            save()
            return
        }

        applications[index].name = name
        applications[index].publisher = "Windows application"
        applications[index].storeProvider = nil
        applications[index].storeExternalID = nil
        applications[index].storeMetadataOnly = true
        applications[index].lastResult = "Searching Steam, Epic Games and GOG for game metadata…"
        if let environmentIndex = environments.firstIndex(where: { $0.id == applications[index].environmentID }) {
            environments[environmentIndex].name = name
        }
        save()

        Task { [weak self] in
            guard let self else { return }
            let metadata = await matchStoreMetadata(for: [name])
            applyRenamedApplicationMetadata(metadata, to: applicationID, requestedName: name)
        }
    }

    func loadDiscoveryCatalog() {
        guard discoveryState != .loading else { return }
        discoveryPaginationTask?.cancel()
        discoveryPaginationState = .idle
        discoveryState = .loading
        discoveryLoadTask?.cancel()
        discoveryLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let catalog = try await services.discoveryCatalog.loadCatalog(forceRefresh: false)
                guard !Task.isCancelled else { return }
                applyDiscoveryCatalog(catalog)
                discoveryState = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                discoveryState = .failed(SecretRedactor.redact(error.localizedDescription))
            }
        }
    }

    func refreshDiscoveryCatalog() {
        guard discoveryState != .loading else { return }
        unavailableDiscoveryMetadata.removeAll()
        discoveryPaginationTask?.cancel()
        discoveryPaginationState = .idle
        discoveryState = .loading
        discoveryLoadTask?.cancel()
        discoveryLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let catalog = try await services.discoveryCatalog.loadCatalog(forceRefresh: true)
                guard !Task.isCancelled else { return }
                applyDiscoveryCatalog(catalog)
                discoveryState = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                discoveryState = .failed(SecretRedactor.redact(error.localizedDescription))
            }
        }
    }

    func gogRevivedAvailability(for game: AppleGamingWikiGame) -> GOGRevivedAvailability {
        discoveryGOGRevivedAvailability[game.id] ?? .unknown
    }

    func ensureGOGRevivedAvailability(for game: AppleGamingWikiGame) async {
        guard discoveryGOGRevivedAvailability[game.id] == nil,
              discoveryGOGRevivedLoads.insert(game.id).inserted else { return }
        discoveryGOGRevivedAvailability[game.id] = .checking
        defer {
            discoveryGOGRevivedLoads.remove(game.id)
            if Task.isCancelled, discoveryGOGRevivedAvailability[game.id] == .checking {
                discoveryGOGRevivedAvailability.removeValue(forKey: game.id)
            }
        }

        do {
            let entry = try await services.gogRevivedCatalog.lookup(named: game.title)
            guard !Task.isCancelled else { return }
            discoveryGOGRevivedAvailability[game.id] = entry.map(GOGRevivedAvailability.available) ?? .notFound
        } catch {
            guard !Task.isCancelled else { return }
            discoveryGOGRevivedAvailability[game.id] = .unavailable
        }
    }

    func loadDiscoveryMetadata(for game: AppleGamingWikiGame) {
        Task { await ensureDiscoveryMetadata(for: game) }
    }

    func ensureDiscoveryMetadata(for game: AppleGamingWikiGame) async {
        guard discoveryMetadata[game.id] == nil else { return }
        guard discoveryMetadataLoads.insert(game.id).inserted else {
            await waitForDiscoveryMetadataLoadToFinish(for: game.id)
            guard !Task.isCancelled else { return }
            await ensureDiscoveryMetadata(for: game)
            return
        }
        await discoveryMetadataGate.acquire()
        guard !Task.isCancelled else {
            discoveryMetadataLoads.remove(game.id)
            await discoveryMetadataGate.release()
            return
        }
        let metadata = await services.discoveryCatalog.metadata(for: game, forceRefresh: false)
        guard !Task.isCancelled else {
            discoveryMetadataLoads.remove(game.id)
            await discoveryMetadataGate.release()
            return
        }
        if let metadata {
            unavailableDiscoveryMetadata.remove(game.id)
            cacheDiscoveryMetadata(metadata, for: game.id)
            scheduleDiscoveryCatalogEnrichment()
        } else {
            unavailableDiscoveryMetadata.insert(game.id)
        }
        discoveryMetadataLoads.remove(game.id)
        await discoveryMetadataGate.release()
    }

    func loadMoreDiscoveryGames() {
        guard discoveryState != .loading,
              discoveryPaginationState != .loading,
              let catalog = discoverySourceCatalog ?? discoveryCatalog,
              (catalog.steamOffset ?? 0) < (catalog.steamTotal ?? .max) else { return }
        discoveryPaginationState = .loading
        discoveryPaginationTask?.cancel()
        discoveryPaginationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await services.discoveryCatalog.loadMoreSteam(in: catalog)
                guard !Task.isCancelled else { return }
                applyDiscoveryCatalog(loaded)
                discoveryPaginationState = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                discoveryPaginationState = .failed("Steam catalog could not be loaded: \(error.localizedDescription). Try again.")
            }
        }
    }

    func searchDiscoveryGames(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearDiscoverySearch()
            return
        }
        discoverySearchQuery = query
        discoverySearchMessage = "Searching the live Steam macOS catalog…"
        do {
            let games = try await services.discoveryCatalog.searchMacGames(named: query)
            guard !Task.isCancelled, discoverySearchQuery == query else { return }
            discoverySearchResults = games
            rebuildDiscoveryCatalog()
            discoverySearchMessage = "\(games.count) macOS results from Steam; combined with local compatibility records."
        } catch {
            guard !Task.isCancelled, discoverySearchQuery == query else { return }
            discoverySearchResults = []
            rebuildDiscoveryCatalog()
            discoverySearchMessage = "Live Steam search is unavailable. Showing matches in the saved catalog."
        }
    }

    func clearDiscoverySearch() {
        discoverySearchQuery = ""
        discoverySearchResults = []
        discoverySearchMessage = nil
        rebuildDiscoveryCatalog()
    }

    func searchDiscoveryGames(developer: String) async {
        let developer = developer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !developer.isEmpty else {
            discoveryProducerQuery = ""
            discoveryProducerResults = []
            discoveryProducerSearchState = .idle
            return
        }
        discoveryProducerQuery = developer
        discoveryProducerSearchState = .loading
        do {
            let games = try await services.discoveryCatalog.searchMacGames(developer: developer)
            guard !Task.isCancelled, discoveryProducerQuery == developer else { return }
            discoveryProducerResults = games
            discoveryProducerSearchState = .loaded
        } catch {
            guard !Task.isCancelled, discoveryProducerQuery == developer else { return }
            discoveryProducerResults = []
            discoveryProducerSearchState = .failed("Discovery games by this developer could not be loaded.")
        }
    }

    func discoveryGames(developer: String) -> [AppleGamingWikiGame] {
        discoveryProducerQuery == developer.trimmingCharacters(in: .whitespacesAndNewlines)
            ? discoveryProducerResults
            : []
    }

    private func applyDiscoveryCatalog(_ catalog: AppleGamingWikiCatalog) {
        discoverySourceCatalog = catalog
        rebuildDiscoveryCatalog()
    }

    private func rebuildDiscoveryCatalog() {
        guard var value = discoverySourceCatalog else { return }
        value.games = AppleGamingWikiDiscoveryService.merge(value.games, discoverySearchResults).map { game in
            guard let metadata = discoveryMetadata[game.id] else { return game }
            var enriched = game
            enriched.steamAppID = metadata.steamAppID ?? game.steamAppID
            enriched.coverURL = metadata.coverImageURL ?? game.coverURL
            enriched.genres = game.genres?.isEmpty == false ? game.genres : metadata.genres
            return enriched
        }
        discoveryCatalog = value
    }

    private func scheduleDiscoveryCatalogEnrichment() {
        discoveryEnrichmentTask?.cancel()
        discoveryEnrichmentTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.rebuildDiscoveryCatalog()
        }
    }

    func isDiscoveryGameSaved(_ game: AppleGamingWikiGame) -> Bool {
        savedDiscoveryGames.contains { $0.id == game.id || (game.steamAppID != nil && $0.steamAppID == game.steamAppID) }
    }

    func toggleDiscoveryGame(_ game: AppleGamingWikiGame) {
        var saved = savedDiscoveryGames
        if isDiscoveryGameSaved(game) {
            saved.removeAll { $0.id == game.id || (game.steamAppID != nil && $0.steamAppID == game.steamAppID) }
        } else {
            var value = game
            if let metadata = discoveryMetadata[game.id] {
                value.steamAppID = metadata.steamAppID ?? value.steamAppID
                value.coverURL = metadata.coverImageURL ?? value.coverURL
                value.genres = metadata.genres ?? value.genres
            }
            saved.append(value)
        }
        do {
            let url = storageLayout.rootURL.appending(path: "Discovery/saved-games.json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: url, options: .atomic)
            savedDiscoveryGames = saved
        } catch {
            present(error, title: "Couldn’t save Discovery games", stage: "Saving your library")
        }
    }

    func isDiscoveryMetadataLoading(for game: AppleGamingWikiGame) -> Bool {
        discoveryMetadataLoads.contains(game.id)
    }

    func discoveryMetadata(for game: AppleGamingWikiGame) -> DiscoveryGameMetadata? {
        discoveryMetadata[game.id]
    }

    func isDiscoveryMetadataUnavailable(for game: AppleGamingWikiGame) -> Bool {
        unavailableDiscoveryMetadata.contains(game.id)
    }

    func discoveryPriceSummary(for game: AppleGamingWikiGame) -> DiscoveryPriceSummary? {
        discoveryPriceSummaries[game.id]
    }

    func isDiscoveryPriceLoading(for game: AppleGamingWikiGame) -> Bool {
        discoveryPriceLoads.contains(game.id) || discoveryOffersLoads.contains(game.id)
    }

    func invalidateDiscoveryPrices() {
        discoveryPriceSummaries.removeAll()
        discoveryPriceAccessOrder.removeAll()
        discoveryPriceLoads.removeAll()
        discoveryOffersLoads.removeAll()
        loadedDiscoveryOffers.removeAll()
    }

    func ensureDiscoveryPrice(for game: AppleGamingWikiGame) async {
        guard discoveryPriceSummaries[game.id] == nil else { return }
        guard discoveryPriceLoads.insert(game.id).inserted else {
            await waitForDiscoveryPriceLoadToFinish(for: game.id)
            guard !Task.isCancelled else { return }
            await ensureDiscoveryPrice(for: game)
            return
        }
        await discoveryPriceGate.acquire()
        guard !Task.isCancelled else {
            discoveryPriceLoads.remove(game.id)
            await discoveryPriceGate.release()
            return
        }
        var resolvedGame = game
        if let metadata = discoveryMetadata[game.id] {
            resolvedGame.steamAppID = metadata.steamAppID ?? game.steamAppID
        }
        let summary = await services.discoveryPricing.loadOverview(for: resolvedGame)
        discoveryPriceLoads.remove(game.id)
        if !Task.isCancelled, let summary {
            cacheDiscoveryPriceSummary(summary, for: game.id)
        }
        await discoveryPriceGate.release()
    }

    func ensureDiscoveryOffers(for game: AppleGamingWikiGame) async {
        await ensureDiscoveryPrice(for: game)
        guard !Task.isCancelled else { return }
        guard var summary = discoveryPriceSummaries[game.id],
              !loadedDiscoveryOffers.contains(game.id),
              discoveryOffersLoads.insert(game.id).inserted else { return }
        guard !Task.isCancelled else {
            discoveryOffersLoads.remove(game.id)
            return
        }
        let offers = await services.discoveryPricing.loadOffers(for: summary.itadGameID)
        discoveryOffersLoads.remove(game.id)
        guard !Task.isCancelled, let offers else { return }
        summary.offers = offers
        cacheDiscoveryPriceSummary(summary, for: game.id)
        loadedDiscoveryOffers.insert(game.id)
    }

    func loadDiscoveryPriceHistory(for game: AppleGamingWikiGame, since: Date?) async -> [ITADPriceHistoryPoint]? {
        await ensureDiscoveryPrice(for: game)
        guard !Task.isCancelled,
              let itadGameID = discoveryPriceSummaries[game.id]?.itadGameID else { return nil }
        return await services.discoveryPricing.loadHistory(for: itadGameID, since: since)
    }

    func discoveryStoreDetails(for game: AppleGamingWikiGame) async -> StoreLibraryGame? {
        guard !Task.isCancelled else { return nil }
        let details: StoreLibraryGame?
        if let appID = game.steamAppID ?? discoveryMetadata[game.id]?.steamAppID {
            details = await services.steamLibrary.loadDetails(
                for: StoreLibraryGame(provider: .steam, externalID: appID, name: game.title)
            )
        } else {
            details = await services.steamLibrary.searchStoreGame(named: game.title)
        }
        guard var details else { return nil }
        guard !Task.isCancelled else { return nil }
        details.currentPlayerCount = await services.steamLibrary.loadCurrentPlayerCount(appID: details.externalID)
        guard !Task.isCancelled else { return nil }
        return details
    }

    private func cacheDiscoveryMetadata(_ metadata: DiscoveryGameMetadata, for id: String) {
        discoveryMetadata[id] = metadata
        discoveryMetadataAccessOrder.removeAll { $0 == id }
        discoveryMetadataAccessOrder.append(id)
        while discoveryMetadataAccessOrder.count > Self.discoveryMetadataMemoryLimit {
            let evictedID = discoveryMetadataAccessOrder.removeFirst()
            discoveryMetadata.removeValue(forKey: evictedID)
        }
    }

    private func waitForDiscoveryMetadataLoadToFinish(for id: String) async {
        while discoveryMetadataLoads.contains(id) {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
    }

    private func waitForDiscoveryPriceLoadToFinish(for id: String) async {
        while discoveryPriceLoads.contains(id) {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
    }

    private func cacheDiscoveryPriceSummary(_ summary: DiscoveryPriceSummary, for id: String) {
        discoveryPriceSummaries[id] = summary
        discoveryPriceAccessOrder.removeAll { $0 == id }
        discoveryPriceAccessOrder.append(id)
        while discoveryPriceAccessOrder.count > Self.discoveryPriceMemoryLimit {
            let evictedID = discoveryPriceAccessOrder.removeFirst()
            discoveryPriceSummaries.removeValue(forKey: evictedID)
            loadedDiscoveryOffers.remove(evictedID)
        }
    }

    func addDiscoveryGameToLibrary(_ game: AppleGamingWikiGame, details: StoreLibraryGame) {
        guard !storeGames.contains(where: {
            $0.provider == details.provider && $0.externalID == details.externalID
        }) else { return }
        storeGames.append(details)
        storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !isDiscoveryGameSaved(game) { toggleDiscoveryGame(game) }
        save()
        SoundService.shared.play(.confirmation)
    }
    func activePlaySessionStart(for game: StoreLibraryGame) -> Date? {
        guard let application = linkedApplication(for: game), activePlaySessions[application.id] != nil else { return nil }
        return storeGames.first(where: {
            $0.provider == game.provider && $0.externalID == game.externalID
        })?.activePlaySession?.startedAt
    }
    func activePlaySessionElapsed(for game: StoreLibraryGame) -> TimeInterval? {
        guard let application = linkedApplication(for: game),
              let active = activePlaySessions[application.id],
              let session = storeGames.first(where: {
                  $0.provider == game.provider && $0.externalID == game.externalID
              })?.playSessions?.first(where: { $0.id == active.sessionID }) else { return nil }
        let components = active.checkpointInstant.duration(to: ContinuousClock().now).components
        return session.duration
            + max(0, Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
    func isFavorite(key: String) -> Bool { favoriteKeys.contains(key) }

    func auxiliaryExecutables(for application: WindowsApplication) -> [AuxiliaryExecutable] {
        application.resolvedAuxiliaryExecutables.filter {
            FileManager.default.fileExists(atPath: $0.executablePath)
        }
    }

    func runAuxiliaryExecutable(_ action: AuxiliaryExecutable, for applicationID: UUID) {
        Task { await runAuxiliaryExecutableAsync(action, for: applicationID) }
    }

    func runWindowsInstaller(_ installer: URL, for applicationID: UUID) {
        Task { await runWindowsInstallerAsync(installer, for: applicationID) }
    }

    func dlssUnlockerInstalled(for application: WindowsApplication) -> Bool {
        guard GameLaunchCompatibility.supportsDLSSUnlocker(for: application),
              let environmentRecord = environment(id: application.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let executable = dlssUnlockerExecutable(for: application, in: managed) else { return false }
        return GameLaunchCompatibility.isDLSSUnlockerInstalled(nextTo: executable)
    }

    func installDLSSUnlocker(_ archive: URL, for applicationID: UUID) {
        Task { await installDLSSUnlockerAsync(archive, for: applicationID) }
    }

    func uninstallDLSSUnlocker(for applicationID: UUID) {
        Task { await uninstallDLSSUnlockerAsync(for: applicationID) }
    }

    func toggleFavorite(key: String) {
        if favoriteKeys.contains(key) { favoriteKeys.remove(key) }
        else { favoriteKeys.insert(key) }
        save()
    }

    func setCustomArtwork(from sourceURL: URL, for applicationID: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        do {
            let path = try importCustomArtwork(from: sourceURL)
            applications[index].customArtworkPath = path
            if let reference = applications[index].storeReference,
               let gameIndex = storeGames.firstIndex(where: { $0.storeReference == reference }) {
                storeGames[gameIndex].customArtworkPath = path
            }
            save()
        } catch {
            present(error, title: "Boreal couldn’t set the custom cover", stage: "Importing custom artwork")
        }
    }

    func setCustomArtwork(from sourceURL: URL, forStoreGameID gameID: UUID) {
        guard let index = storeGames.firstIndex(where: { $0.id == gameID }) else { return }
        do {
            storeGames[index].customArtworkPath = try importCustomArtwork(from: sourceURL)
            save()
        } catch {
            present(error, title: "Boreal couldn’t set the custom cover", stage: "Importing custom artwork")
        }
    }

    func resetCustomArtwork(for applicationID: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        applications[index].customArtworkPath = nil
        if let reference = applications[index].storeReference,
           let gameIndex = storeGames.firstIndex(where: { $0.storeReference == reference }) {
            storeGames[gameIndex].customArtworkPath = nil
        }
        save()
    }

    func resetCustomArtwork(forStoreGameID gameID: UUID) {
        guard let index = storeGames.firstIndex(where: { $0.id == gameID }) else { return }
        storeGames[index].customArtworkPath = nil
        save()
    }

    private func importCustomArtwork(from sourceURL: URL) throws -> String {
        let directory = storageLayout.rootURL.appending(path: "Artwork/Custom", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = sourceURL.pathExtension.isEmpty ? "image" : sourceURL.pathExtension.lowercased()
        let destination = directory.appending(path: "\(UUID().uuidString).\(fileExtension)", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination.path
    }

    func performanceLogURL(for applicationID: UUID) -> URL? {
        if let url = performanceLogURLs[applicationID] ?? activeSessions[applicationID]?.stderrLog { return url }
        guard let app = application(id: applicationID),
              let logsPath = environment(id: app.environmentID)?.logsPath else { return nil }
        let logsURL = URL(fileURLWithPath: logsPath, isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(
            at: logsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?
        .filter { $0.lastPathComponent.hasPrefix("launch-") && $0.lastPathComponent.hasSuffix(".stderr.log") }
        .max { lhs, rhs in
            let left = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let right = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
    }

    func performanceProcessIDs(for applicationID: UUID) -> [Int32] {
        performanceProcessIDs[applicationID] ?? []
    }

    func overlayGraphics(for applicationID: UUID) -> OverlayGraphicsDescriptor {
        guard let application = application(id: applicationID) else { return .unavailable }
        let plan = lastLaunchPlans[applicationID]
        let environmentName = environment(id: application.environmentID)?.runtime
        let gameAPI = plan?.directXAPI.displayName ?? "—"
        let translator = plan?.graphicsStack?.backend.displayName
            ?? plan?.graphicsBackend.displayName
            ?? application.graphics
        let hostAPI = plan?.graphicsStack?.hostAPI.displayName ?? "—"
        let runtime = environmentName ?? plan?.runtimeID ?? "—"
        return OverlayGraphicsDescriptor(gameAPI: gameAPI, translator: translator, hostAPI: hostAPI, runtime: runtime)
    }

    /// Process discovery is intentionally independent of overlay rendering.
    /// Wine/Steam can take several seconds to hand the launch request to the
    /// actual game, so refresh the exact executable match while it is running.
    private func startPerformanceProcessTracking(
        session: WindowsProcessSession,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime,
        appID: UUID
    ) {
        performanceProcessTasks[appID]?.cancel()
        performanceProcessIDs[appID] = []
        performanceProcessTasks[appID] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let ids = await self.services.processRunner.gameProcessIDs(
                    session: session, environment: environment, runtime: runtime
                )
                guard !Task.isCancelled else { return }
                self.performanceProcessIDs[appID] = ids
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stopPerformanceProcessTracking(for appID: UUID) {
        performanceProcessTasks[appID]?.cancel()
        performanceProcessTasks[appID] = nil
        performanceProcessIDs[appID] = nil
    }

    func refreshSteamMetadataIfNeeded(for game: StoreLibraryGame) {
        guard game.provider == .steam,
              (game.screenshotURLs?.isEmpty != false || game.videos?.isEmpty != false),
              steamMetadataRefreshes.insert(game.externalID).inserted else { return }
        Task {
            let refreshed = await services.steamLibrary.loadDetails(for: game)
            guard let index = storeGames.firstIndex(where: {
                $0.provider == .steam && $0.externalID == game.externalID
            }) else { return }
            var value = refreshed
            value.id = storeGames[index].id
            value.preserveMeasuredActivity(from: storeGames[index])
            value.customArtworkPath = storeGames[index].customArtworkPath
            storeGames[index] = value
            save()
        }
    }

    /// GOG and Epic catalog responses can omit the presentation fields used by
    /// the product card. Steam is used only as a field-level fallback; the
    /// game's provider and identity remain GOG/Epic.
    func refreshSteamPresentationFallbackIfNeeded(for game: StoreLibraryGame) {
        let reference = game.storeReference
        guard [.epic, .gog].contains(reference.provider),
              let currentGame = storeGames.first(where: { $0.storeReference == reference }),
              Self.needsSteamPresentationFallback(currentGame),
              steamPresentationFallbacks.insert(storePresentationKey(for: currentGame)).inserted else { return }
        let linkedTitle = linkedApplication(for: currentGame)?.name
        let searchTitles = [currentGame.name, linkedTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, title in
                if !result.contains(title) { result.append(title) }
            }

        Task { [weak self] in
            guard let self else { return }
            var fallback: StoreLibraryGame?
            for title in searchTitles {
                if let match = await self.services.steamLibrary.searchStoreGame(named: title) {
                    fallback = match
                    break
                }
            }
            guard let fallback,
                  let index = self.storeGames.firstIndex(where: { $0.storeReference == reference }) else { return }
            var value = self.storeGames[index]
            guard Self.mergeSteamPresentationFallback(from: fallback, into: &value) else { return }
            self.storeGames[index] = value
            self.save()
        }
    }

    private func storePresentationKey(for game: StoreLibraryGame) -> String {
        "\(game.provider.rawValue)::\(game.externalID)"
    }

    private static func needsSteamPresentationFallback(_ game: StoreLibraryGame) -> Bool {
        guard [.epic, .gog].contains(game.provider) else { return false }
        return isMissingPresentationText(game.summary)
            || isMissingPresentationURL(game.portraitImageURL)
            || isMissingPresentationURL(game.headerImageURL)
            || isMissingPresentationURL(game.backgroundImageURL)
            || !hasUsableMedia(game.screenshotURLs)
            || !hasUsableVideos(game.videos)
    }

    private static func mergeSteamPresentationFallback(
        from fallback: StoreLibraryGame,
        into game: inout StoreLibraryGame
    ) -> Bool {
        let original = game
        if isMissingPresentationText(game.developer) { game.developer = fallback.developer }
        if isMissingPresentationText(game.summary) { game.summary = fallback.summary }
        if isMissingPresentationText(game.artworkPath) { game.artworkPath = fallback.artworkPath }
        if isMissingPresentationURL(game.portraitImageURL) { game.portraitImageURL = fallback.portraitImageURL }
        if isMissingPresentationURL(game.headerImageURL) { game.headerImageURL = fallback.headerImageURL }
        if isMissingPresentationURL(game.backgroundImageURL) { game.backgroundImageURL = fallback.backgroundImageURL }
        if !hasUsableMedia(game.screenshotURLs) { game.screenshotURLs = fallback.screenshotURLs }
        if !hasUsableVideos(game.videos) { game.videos = fallback.videos }
        return game != original
    }

    private static func isMissingPresentationText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private static func isMissingPresentationURL(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value) else { return true }
        return url.scheme == nil
    }

    private static func hasUsableMedia(_ values: [String]?) -> Bool {
        values?.contains { !isMissingPresentationURL($0) } == true
    }

    private static func hasUsableVideos(_ values: [StoreVideo]?) -> Bool {
        values?.contains {
            !isMissingPresentationURL($0.videoURL) || !isMissingPresentationURL($0.thumbnailURL)
        } == true
    }

    func loadSteamCurrentPlayerCountIfNeeded(for gameID: UUID) async {
        guard let game = storeGame(id: gameID),
              game.provider == .steam else { return }
        let count = await services.steamLibrary.loadCurrentPlayerCount(appID: game.externalID)
        guard let index = storeGames.firstIndex(where: { $0.id == gameID }) else { return }
        storeGames[index].currentPlayerCount = count
        save()
    }

    func loadStoreGameSizeIfNeeded(for gameID: UUID) async {
        guard let game = storeGame(id: gameID) else { return }
        let platform = preferredStoreInstallationPlatform(for: game)
        if let cached = game.sizeEstimate,
           cached.platform == platform,
           Date.now.timeIntervalSince(cached.fetchedAt) < 86_400 {
            return
        }
        let key = "\(storeOperationKey(for: game))::\(platform.rawValue)"
        guard storeSizeEstimateLoads.insert(key).inserted else { return }
        defer { storeSizeEstimateLoads.remove(key) }
        await storeSizeEstimateGate.acquire()

        let estimate: StoreGameSizeEstimate?
        do {
            let provider = try services.storeProviders.provider(for: game.provider)
            estimate = try await provider.sizeEstimate(for: game, platform: platform)
        } catch {
            await storeSizeEstimateGate.release()
            return
        }
        await storeSizeEstimateGate.release()
        guard let estimate,
              let index = storeGames.firstIndex(where: { $0.id == gameID }) else { return }
        storeGames[index].sizeEstimate = estimate
        save()
    }
    func linkedApplication(for game: StoreLibraryGame) -> WindowsApplication? {
        applications.first {
            $0.status != .unavailable
                && $0.installerPath != "steam-windows-client"
                && $0.storeProvider == game.provider
                && $0.storeExternalID == game.externalID
        }
    }
    func environment(id: UUID) -> WindowsEnvironment? { environments.first { $0.id == id } }

    func installation(for game: StoreLibraryGame) -> GameInstallation? {
        installations.first {
            $0.gameID == game.id || $0.storeReference == game.storeReference
        }
    }

    func installedLocation(for game: StoreLibraryGame) -> URL? {
        guard let installation = installation(for: game), installation.state.representsAnInstallation else { return nil }
        return InstallationStateResolver.resolvedLocation(for: installation, layout: storageLayout)
    }

    func installedPlatform(for game: StoreLibraryGame) -> StoreGameInstallationPlatform? {
        installation(for: game)?.platform
    }

    func installedSize(for game: StoreLibraryGame) -> Int64? {
        installation(for: game)?.installedSize
    }

    func isInstalled(_ game: StoreLibraryGame) -> Bool {
        installation(for: game)?.state == .installed
    }

    /// Builds the provider payload from the canonical installation record.
    /// Provider adapters still accept `StoreLibraryGame` for API compatibility,
    /// but they never need to read a stale legacy install path.
    private func canonicalStoreGame(_ game: StoreLibraryGame) -> StoreLibraryGame {
        guard let installation = installation(for: game) else { return game }
        var value = game
        value.isInstalled = installation.state.representsAnInstallation
        value.installPath = StoragePathResolver.resolve(installation.location, layout: storageLayout).path
        value.installedPlatform = installation.platform
        value.storageBytes = installation.installedSize
        return value
    }

    private func hasInstallation(_ game: StoreLibraryGame) -> Bool {
        installation(for: game)?.state.representsAnInstallation == true
    }

    var managedStorageLayout: BorealStorageLayout { storageLayout }

    func refreshGameDiskStorage(for game: StoreLibraryGame) {
        let gameID = game.id
        let gamePath = installations.first(where: {
            $0.gameID == game.id || $0.storeReference == game.storeReference
        }).map { InstallationStateResolver.resolvedLocation(for: $0, layout: storageLayout) }
        let prefixPath = linkedApplication(for: game).flatMap { environment(id: $0.environmentID)?.prefixPath }.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let supportPath = storageURL.deletingLastPathComponent()
        Task.detached(priority: .utility) { [weak self] in
            let report = GameDiskStorage.report(gameURL: gamePath, prefixURL: prefixPath, applicationSupportURL: supportPath)
            await MainActor.run { self?.gameDiskReports[gameID] = report }
        }
    }

    func gameDiskReport(for game: StoreLibraryGame) -> GameDiskStorageReport? { gameDiskReports[game.id] }

    func clearGameDiskStorage(_ category: GameDiskStorageCategory, for game: StoreLibraryGame) {
        guard category != .gameFiles, category != .prefix,
              let report = gameDiskReports[game.id], diskStorageOperationIDs.insert(game.id).inserted else { return }
        Task { [weak self] in
            defer { self?.diskStorageOperationIDs.remove(game.id) }
            do {
                try GameDiskStorage.remove(category, from: report)
                refreshGameDiskStorage(for: game)
            } catch {
                present(error, title: category.title + " couldn’t be cleared", stage: "Removing selected game storage")
            }
        }
    }

    func rebuildShaderCache(for game: StoreLibraryGame) { clearGameDiskStorage(.shaders, for: game) }

    func dependencyStatuses(for environmentID: UUID, application: WindowsApplication? = nil) -> [RuntimeDependencyStatus] {
        let resolvedApplication = application ?? applications.first {
            $0.environmentID == environmentID && !$0.usesStoreMetadataOnly
        }
        let recommendations = RuntimeDependencyResolver.resolve(
            executableURL: resolvedApplication.map { URL(fileURLWithPath: $0.executablePath) }
        )
        return environmentDependencyStatuses[environmentID] ?? RuntimeDependency.allCases.map {
            let resolution = recommendations[$0] ?? (.optional, "Install only when needed")
            return RuntimeDependencyStatus(dependency: $0, state: .missing, detail: resolution.1, recommendation: resolution.0)
        }
    }

    func refreshDependencies(for environmentID: UUID, application: WindowsApplication? = nil) {
        guard let record = environment(id: environmentID), let managed = managedEnvironment(from: record) else { return }
        let resolvedApplication = application ?? applications.first {
            $0.environmentID == environmentID && !$0.usesStoreMetadataOnly
        }
        let recommendations = RuntimeDependencyResolver.resolve(
            executableURL: resolvedApplication.map { URL(fileURLWithPath: $0.executablePath) }
        )
        Task { [weak self] in
            guard let self, let runtime = try? await services.runtimeManager.installedRuntimes().first(where: { $0.id == managed.runtimeID }) else { return }
            let statuses = await services.environmentManager.dependencyStatuses(managed, runtime: runtime).map { status in
                var resolved = status
                let resolution = recommendations[status.dependency] ?? (.optional, "Install only when needed")
                resolved.recommendation = resolution.0
                resolved.detail = resolution.1
                return resolved
            }
            environmentDependencyStatuses[environmentID] = statuses
        }
    }

    func installDependency(_ dependency: RuntimeDependency, for environmentID: UUID) {
        guard let record = environment(id: environmentID), let managed = managedEnvironment(from: record) else { return }
        guard let current = environmentDependencyStatuses[environmentID],
              let index = current.firstIndex(where: { $0.dependency == dependency }),
              current[index].state != .installed else { return }
        environmentDependencyStatuses[environmentID]?[index].state = .installing
        Task { [weak self] in
            guard let self else { return }
            var recoverySnapshot: EnvironmentSnapshot?
            do {
                guard let runtime = try await services.runtimeManager.installedRuntimes().first(where: { $0.id == managed.runtimeID }) else { throw InstallerServiceError.noRuntimeAvailable }
                // Dependency installation mutates the prefix. Keep a restore
                // point before invoking the existing installer so a failed
                // winetricks/configuration operation does not leave the user
                // with an untracked partial environment.
                if FileManager.default.fileExists(atPath: managed.rootURL.appending(path: "environment.json").path) {
                    recoverySnapshot = try await createEnvironmentSnapshot(for: environmentID, reason: .dependencyInstallation)
                }
                try await services.environmentManager.install(dependency, in: managed, runtime: runtime)
                refreshDependencies(for: environmentID)
            } catch {
                if let recoverySnapshot {
                    _ = try? await services.environmentSnapshotManager.restore(
                        recoverySnapshot,
                        to: managed,
                        activeSession: false,
                        preserveCurrent: false,
                        traceID: recoverySnapshot.traceID
                    )
                }
                if let index = environmentDependencyStatuses[environmentID]?.firstIndex(where: { $0.dependency == dependency }) {
                    environmentDependencyStatuses[environmentID]?[index].state = .failed
                    environmentDependencyStatuses[environmentID]?[index].detail = error.localizedDescription
                }
                present(error, title: "\(dependency.displayName) couldn’t be installed", stage: "Installing the dependency into the selected Windows environment")
            }
        }
    }

    func installRequiredDependencies(for environmentID: UUID) {
        guard let record = environment(id: environmentID), let managed = managedEnvironment(from: record) else { return }
        let dependencies = dependencyStatuses(for: environmentID)
            .filter { ($0.state == .missing || $0.state == .failed) && $0.recommendation == .required }
            .map(\.dependency)
        guard !dependencies.isEmpty else { return }
        for dependency in dependencies {
            if let index = environmentDependencyStatuses[environmentID]?.firstIndex(where: { $0.dependency == dependency }) {
                environmentDependencyStatuses[environmentID]?[index].state = .installing
            }
        }
        Task { [weak self] in
            guard let self else { return }
            var recoverySnapshot: EnvironmentSnapshot?
            do {
                guard let runtime = try await services.runtimeManager.installedRuntimes().first(where: { $0.id == managed.runtimeID }) else { throw InstallerServiceError.noRuntimeAvailable }
                // The actor executes each command serially so winetricks never
                // changes the same prefix concurrently.
                if FileManager.default.fileExists(atPath: managed.rootURL.appending(path: "environment.json").path) {
                    recoverySnapshot = try await createEnvironmentSnapshot(for: environmentID, reason: .dependencyInstallation)
                }
                for dependency in dependencies {
                    try await services.environmentManager.install(dependency, in: managed, runtime: runtime)
                }
                refreshDependencies(for: environmentID)
            } catch {
                if let recoverySnapshot {
                    _ = try? await services.environmentSnapshotManager.restore(
                        recoverySnapshot,
                        to: managed,
                        activeSession: false,
                        preserveCurrent: false,
                        traceID: recoverySnapshot.traceID
                    )
                }
                refreshDependencies(for: environmentID)
                present(error, title: "Dependencies couldn’t be installed", stage: "Installing Windows libraries into the selected environment")
            }
        }
    }
    func applications(in environmentID: UUID) -> [WindowsApplication] { applications.filter { $0.environmentID == environmentID } }

    func recommendedRuntimeEngine(for game: StoreLibraryGame) -> RuntimeEngine {
        if let required = GameRuntimeProfiles.requiredEngine(for: game) {
            return required
        }
        return game.provider == .gog && game.externalID == "2022341186" ? .gamePortingToolkit : .wine
    }

    func hasInstalledRuntime(engine: RuntimeEngine) -> Bool {
        runtimeStatuses.contains { $0.source == .installed && $0.state == .installed && $0.engine == engine }
    }

    func runtimeCompatibilityIssue(for application: WindowsApplication, engine: RuntimeEngine) -> String? {
        if let required = GameRuntimeProfiles.requiredEngine(for: application), engine != required {
            return "This game requires GPTK with D3DMetal for Direct3D 11. Boreal prepares its Unity IL2CPP compatibility files automatically."
        }
        guard engine == .gamePortingToolkit,
              WindowsExecutableArchitecture.inspect(URL(fileURLWithPath: application.executablePath)) == .x86 else { return nil }
        let supportsWoW64 = runtimeStatuses.contains {
            $0.source == .installed
                && $0.state == .installed
                && $0.engine == engine
                && $0.features?.supportsWoW64 == true
        }
        return supportsWoW64 ? nil : "This game is 32-bit. The installed GPTK runtime does not support WoW64, so use Wine instead."
    }

    func compatibilityProfile(for application: WindowsApplication) -> WineCompatibilityProfile {
        var profile = GameGraphicsProfiles.effectiveCompatibilityProfile(
            application.compatibilityProfile ?? application.resolvedCompatibilityProfile,
            for: application
        )
        if let builtIn = GameGraphicsProfiles.profile(for: application) {
            if application.compatibilityProfile == nil {
                profile.graphicsAPI = builtIn.defaultAPI
                if builtIn.enforcedBackend == nil, let preferredBackend = builtIn.preferredBackend {
                    profile.graphicsBackend = preferredBackend
                }
                if let overlayCompatibleFullscreen = builtIn.overlayCompatibleFullscreen {
                    profile.overlayCompatibleFullscreen = overlayCompatibleFullscreen
                }
            }
        }
        if environment(id: application.environmentID)?.architecture == "32-bit" {
            profile.architecture = .win32
        }
        if let record = environment(id: application.environmentID),
           let managed = managedEnvironment(from: record),
           let runtime = runtimeStatuses.first(where: {
               $0.id == managed.runtimeID && $0.source == .installed && $0.state == .installed
           }) {
            profile.prefixMode = managed.configuration.resolvedPrefixMode(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true)
        }
        return profile
    }

    func runtimeEngine(for application: WindowsApplication) -> RuntimeEngine? {
        guard let runtimeID = environment(id: application.environmentID)?.runtimeID else { return nil }
        return runtimeStatuses.first(where: {
            $0.id == runtimeID && $0.source == .installed
        })?.engine
    }

    /// Shared Windows Steam has one prefix, so prefix-level settings come from
    /// the host environment. Per-game launch arguments, overlay preferences,
    /// controller keyboard mapping, and process-scoped diagnostics remain on
    /// the game profile.
    private func sharedSteamEnvironmentProfile(
        from gameProfile: WineCompatibilityProfile,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) -> WineCompatibilityProfile {
        var profile = gameProfile
        let configuration = environment.configuration
        profile.windowsVersion = WineWindowsVersion(rawValue: configuration.windowsVersion) ?? gameProfile.windowsVersion
        profile.architecture = WinePrefixArchitecture(rawValue: configuration.architecture) ?? .win64
        profile.prefixMode = configuration.prefixMode
        profile.graphicsBackend = configuration.graphicsBackend
        profile.graphicsAPI = configuration.graphicsAPI == .automatic ? nil : configuration.graphicsAPI
        profile.graphicsFallback = configuration.graphicsFallback
        profile.retinaModeEnabled = configuration.retinaModeEnabled
        profile.forceXInput = configuration.forceXInput
        profile.requiredDependencies = configuration.requiredDependencies

        // Materialize automatic host selection once. This prevents the next
        // Steam game from changing the shared prefix's renderer because its
        // own DirectX API differs.
        let architecture = configuration.resolvedPrefixArchitecture(
            runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true
        )
        let hostResolution = GraphicsBackendResolver.resolve(
            api: configuration.graphicsAPI,
            requestedBackend: configuration.graphicsBackend,
            runtime: runtime,
            architecture: architecture,
            fallback: configuration.graphicsFallback
        )
        if hostResolution.isAvailable {
            profile.graphicsBackend = hostResolution.stack.backend
        }
        return profile
    }

    func graphicsBackendIssue(_ backend: WineGraphicsBackend, for application: WindowsApplication) -> String? {
        guard backend != .automatic, backend != .wineD3D else { return nil }
        if (backend == .dxmt || backend == .d3dMetal), compatibilityProfile(for: application).architecture == .win32 {
            return "\(backend.displayName) currently supports only 64-bit Windows games. Choose Win64 or another renderer."
        }
        let requiredEngine = backend.requiredEngine ?? .wine
        let compatibleRuntimes = runtimeStatuses.filter {
            $0.source == .installed && $0.state == .installed && $0.engine == requiredEngine
        }
        guard !compatibleRuntimes.isEmpty else {
            return backend == .d3dMetal
                ? "Install or import a Game Porting Toolkit runtime to use D3DMetal."
                : "Install or import a Wine runtime that supplies \(backend.displayName)."
        }
        switch backend {
        case .d3dMetal:
            return compatibleRuntimes.contains { $0.features?.d3dmetal == true } ? nil : "The installed GPTK runtime does not contain D3DMetal."
        case .dxmt:
            return compatibleRuntimes.contains { $0.features?.dxmt == true } ? nil : "No installed Wine runtime contains the DXMT component package."
        case .dxvk:
            return compatibleRuntimes.contains { $0.features?.dxvk == true } ? nil : "No installed Wine runtime contains the DXVK component package."
        case .vkd3d:
            return compatibleRuntimes.contains { $0.features?.vkd3d == true } ? nil : "No installed Wine runtime contains the VKD3D-Proton component package."
        case .automatic, .wineD3D:
            return nil
        }
    }

    func prefixModeIssue(_ mode: WinePrefixMode, for application: WindowsApplication) -> String? {
        guard let environment = environment(id: application.environmentID),
              let runtime = runtimeStatuses.first(where: {
                  $0.id == environment.runtimeID && $0.source == .installed && $0.state == .installed
              }) else { return nil }
        let capabilities = runtime.features?.resolvedArchitectureCapabilities ?? .unknown
        switch mode {
        case .wow64 where !capabilities.usesNewWoW64:
            return "The selected runtime does not provide modern WoW64 prefixes."
        case .legacyWin32 where !capabilities.supportsLegacyWin32Prefix:
            return "The selected runtime does not provide a legacy Win32 prefix."
        case .legacyWin64 where !capabilities.canRunX86_64 || capabilities.usesNewWoW64:
            return "The selected runtime does not provide a legacy Win64 prefix."
        default:
            break
        }
        return nil
    }

    func compatibilityRuntimeFeatures(
        for application: WindowsApplication,
        backend: WineGraphicsBackend
    ) -> RuntimeFeatures? {
        let currentRuntimeID = environment(id: application.environmentID)?.runtimeID
        let requiredEngine = backend.requiredEngine
        let installed = runtimeStatuses.filter { status in
            status.source == .installed && status.state == .installed
                && (requiredEngine == nil || status.engine == requiredEngine)
        }
        let supportsBackend: (RuntimeStatus) -> Bool = { status in
            switch backend {
            case .d3dMetal: status.features?.d3dmetal == true
            case .dxmt: status.features?.dxmt == true
            case .dxvk: status.features?.dxvk == true
            case .vkd3d: status.features?.vkd3d == true
            case .automatic, .wineD3D: true
            }
        }
        if let current = installed.first(where: { $0.id == currentRuntimeID && supportsBackend($0) }) {
            return current.features
        }
        return installed.first(where: supportsBackend)?.features
    }

    func updateCompatibilityProfile(for applicationID: UUID, profile requestedProfile: WineCompatibilityProfile) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }),
              applications[index].status != .running,
              !applications[index].status.isBusy else { return }
        var profile = GameGraphicsProfiles.effectiveCompatibilityProfile(
            requestedProfile,
            for: applications[index]
        )
        if let features = compatibilityRuntimeFeatures(for: applications[index], backend: profile.graphicsBackend) {
            if !features.esync { profile.esyncEnabled = false }
            if !features.msync { profile.msyncEnabled = false }
            if !features.wineBusControllerMapping { profile.forceXInput = false }
            if !features.dgVoodoo2 { profile.legacyWrapper = .none }
        }
        if profile.temporalUpscaling.mode == .metalFXBridge {
            profile.upscalingBridge = .ngxToMetalFX
        } else if profile.temporalUpscaling.mode != .automatic {
            profile.upscalingBridge = .none
        }
        let previousProfile = applications[index].resolvedCompatibilityProfile
        let previousWindowsVersion = applications[index].windowsVersion
        let previousGraphics = applications[index].graphics
        let currentRuntimeID = environment(id: applications[index].environmentID)?.runtimeID
        let currentEngine = runtimeStatuses.first(where: {
            $0.id == currentRuntimeID && $0.source == .installed
        })?.engine ?? .wine
        let currentRuntimeFeatures = runtimeStatuses.first { $0.id == currentRuntimeID }?.features
        applications[index].compatibilityProfile = profile
        applications[index].windowsVersion = profile.windowsVersion.displayName
        let requestedEngine = profile.graphicsBackend.requiredEngine ?? currentEngine
        let currentRuntimeSupportsBackend: Bool
        switch profile.graphicsBackend {
        case .d3dMetal: currentRuntimeSupportsBackend = currentRuntimeFeatures?.d3dmetal == true
        case .dxmt: currentRuntimeSupportsBackend = currentRuntimeFeatures?.dxmt == true
        case .dxvk: currentRuntimeSupportsBackend = currentRuntimeFeatures?.dxvk == true
        case .vkd3d: currentRuntimeSupportsBackend = currentRuntimeFeatures?.vkd3d == true
        case .automatic, .wineD3D: currentRuntimeSupportsBackend = true
        }
        let requiresRecreation = previousProfile.architecture != profile.architecture
            || previousProfile.prefixMode != profile.prefixMode
            || requestedEngine != currentEngine
            || !currentRuntimeSupportsBackend
        let usesSharedSteamEnvironment = applications[index].usesSharedSteamEnvironment
        applications[index].lastResult = requiresRecreation
            ? "Rebuilding environment for compatibility changes"
            : (usesSharedSteamEnvironment ? "Compatibility profile saved for the next launch" : "Applying compatibility profile")
        save()
        guard requiresRecreation else {
            guard !usesSharedSteamEnvironment else { return }
            applyCompatibilityProfileToExistingEnvironment(
                applicationID,
                profile: profile,
                previousProfile: previousProfile,
                previousWindowsVersion: previousWindowsVersion,
                previousGraphics: previousGraphics
            )
            return
        }
        if let provider = applications[index].storeProvider, [.epic, .gog].contains(provider) {
            recreateEnvironment(applicationID, with: requestedEngine, rollbackProfile: previousProfile)
        } else if usesSharedSteamEnvironment {
            applications[index].compatibilityProfile?.architecture = previousProfile.architecture
            applications[index].compatibilityProfile?.prefixMode = previousProfile.prefixMode
            applications[index].compatibilityProfile?.graphicsBackend = previousProfile.graphicsBackend
            applications[index].lastResult = "Steam keeps architecture and renderer in its shared environment"
            save()
        } else {
            recreateStandaloneEnvironment(applicationID, profile: profile, previousProfile: previousProfile, engine: requestedEngine)
        }
    }

    private func applyCompatibilityProfileToExistingEnvironment(
        _ applicationID: UUID,
        profile: WineCompatibilityProfile,
        previousProfile: WineCompatibilityProfile,
        previousWindowsVersion: String,
        previousGraphics: String
    ) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        applications[index].status = .preparing
        save()
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let currentIndex = applications.firstIndex(where: { $0.id == applicationID }),
                      let environmentRecord = environment(id: applications[currentIndex].environmentID),
                      var managed = managedEnvironment(from: environmentRecord),
                      let runtime = try await services.runtimeManager.installedRuntimes().first(where: { $0.id == environmentRecord.runtimeID }) else {
                    throw InstallerServiceError.noRuntimeAvailable
                }
                _ = try? await createSaveBackup(for: applicationID, trigger: .beforeEnvironmentRebuild)
                if FileManager.default.fileExists(atPath: managed.rootURL.appending(path: "environment.json").path) {
                    _ = try await createEnvironmentSnapshot(for: managed.id, reason: .manualCompatibilityChange)
                }
                let existingComponentReferences = managed.configuration.graphicsComponentReferences
                managed.configuration = EnvironmentConfiguration(name: environmentRecord.name, profile: profile)
                managed.configuration.graphicsComponentReferences = existingComponentReferences
                managed = try await services.environmentManager.configure(managed, runtime: runtime)
                guard let updatedIndex = applications.firstIndex(where: { $0.id == applicationID }) else { return }
                if let environmentIndex = environments.firstIndex(where: { $0.id == managed.id }) {
                    environments[environmentIndex].windowsVersion = profile.windowsVersion.displayName
                }
                applications[updatedIndex].status = .ready
                applications[updatedIndex].lastResult = "Compatibility profile applied"
                applications[updatedIndex].lastErrorDetail = nil
                save()
            } catch {
                if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                    applications[currentIndex].compatibilityProfile = previousProfile
                    applications[currentIndex].windowsVersion = previousWindowsVersion
                    applications[currentIndex].graphics = previousGraphics
                    applications[currentIndex].status = .ready
                    applications[currentIndex].lastResult = "Compatibility profile couldn’t be applied"
                    applications[currentIndex].lastFailureStage = "Configuring the Wine environment"
                    applications[currentIndex].lastErrorDetail = SecretRedactor.redact(error.localizedDescription)
                    save()
                    present(error, title: "\(applications[currentIndex].name) couldn’t be configured", stage: "Applying the Wine compatibility profile")
                }
            }
        }
    }

    private func recreateStandaloneEnvironment(
        _ applicationID: UUID,
        profile: WineCompatibilityProfile,
        previousProfile: WineCompatibilityProfile,
        engine: RuntimeEngine,
        launchWhenReady: Bool = false
    ) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        let oldEnvironmentID = applications[index].environmentID
        let executable = URL(fileURLWithPath: applications[index].executablePath)
        let applicationName = applications[index].name
        applications[index].status = .preparing
        save()
        Task { [weak self] in
            guard let self else { return }
            var replacement: ManagedBorealEnvironment?
            do {
                _ = try? await createSaveBackup(for: applicationID, trigger: .beforeEnvironmentRebuild)
                if let oldRecord = environment(id: oldEnvironmentID),
                   let oldManaged = managedEnvironment(from: oldRecord),
                   FileManager.default.fileExists(atPath: oldManaged.rootURL.appending(path: "environment.json").path) {
                    _ = try await createEnvironmentSnapshot(for: oldEnvironmentID, reason: .manualCompatibilityChange)
                }
                let executableArchitecture = WindowsExecutableArchitecture.inspect(executable)
                let runtime = try await prepareRuntime(
                    supporting: profile.graphicsBackend,
                    preferredEngine: engine,
                    executableArchitecture: executableArchitecture,
                    prefixMode: profile.prefixMode,
                    runtimeIDOverride: profile.runtimeIDOverride
                )
                try validatePrefixSelection(profile, executableArchitecture: executableArchitecture, runtime: runtime)
                var managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: applicationName, profile: profile),
                    runtime: runtime
                )
                replacement = managed
                try await services.environmentManager.initialize(managed, runtime: runtime)
                managed.state = .ready
                guard let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) else { throw CancellationError() }
                environments.append(WindowsEnvironment(
                    id: managed.id,
                    name: applications[currentIndex].name,
                    windowsVersion: profile.windowsVersion.displayName,
                    architecture: managed.configuration.architecture == WinePrefixArchitecture.win64.rawValue ? "64-bit" : "32-bit",
                    runtime: runtime.runtimeDescription,
                    graphics: profile.graphicsBackend == .automatic ? runtime.graphicsName : profile.graphicsBackend.displayName,
                    runtimeID: runtime.id,
                    rootPath: managed.rootURL.path,
                    prefixPath: managed.prefixURL.path,
                    logsPath: managed.logsURL.path
                ))
                applications[currentIndex].environmentID = managed.id
                applications[currentIndex].compatibilityProfile?.architecture = managed.configuration.architecture == WinePrefixArchitecture.win64.rawValue ? .win64 : .win32
                applications[currentIndex].graphics = profile.graphicsBackend == .automatic ? runtime.graphicsName : profile.graphicsBackend.displayName
                applications[currentIndex].status = .ready
                applications[currentIndex].lastResult = "Compatibility environment rebuilt"
                applications[currentIndex].lastErrorDetail = nil
                save()
                if applications.allSatisfy({ $0.environmentID != oldEnvironmentID }),
                   let oldRecord = environment(id: oldEnvironmentID),
                   let oldManaged = managedEnvironment(from: oldRecord) {
                    try? await services.environmentManager.remove(oldManaged)
                    environments.removeAll { $0.id == oldEnvironmentID }
                    save()
                }
                if launchWhenReady {
                    await toggleRunningAsync(applicationID)
                }
            } catch {
                let diagnostics = await preserveDiagnosticsAndRemoveFailedEnvironment(replacement)
                if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                    applications[currentIndex].compatibilityProfile = previousProfile
                    applications[currentIndex].windowsVersion = previousProfile.windowsVersion.displayName
                    applications[currentIndex].graphics = previousProfile.graphicsBackend.displayName
                    applications[currentIndex].status = .ready
                    applications[currentIndex].lastResult = "Environment rebuild failed"
                    applications[currentIndex].lastErrorDetail = SecretRedactor.redact(error.localizedDescription)
                    save()
                }
                present(
                    error,
                    title: "The compatibility environment couldn’t be rebuilt",
                    stage: "Applying architecture and renderer settings",
                    diagnostics: diagnostics
                )
            }
        }
    }

    func install(_ candidate: InstallCandidate, runtimeEngine: RuntimeEngine? = nil) async -> UUID? {
        SoundService.shared.play(.installationStarted)
        installation = InstallationProgress(state: .installing, stage: .preparingRuntime)
        do {
            let commit = try await services.installer.install(candidate.url, name: candidate.name, preferredEngine: runtimeEngine) { [weak self] stage in
                await self?.updateInstallation(stage)
            }
            let communityProfile: CommunityCompatibility? = nil
            let managed = commit.environment
            let environment = WindowsEnvironment(
                id: managed.id,
                name: managed.configuration.name,
                windowsVersion: (WineWindowsVersion(rawValue: managed.configuration.windowsVersion) ?? .windows11).displayName,
                architecture: managed.configuration.architecture == "win64" ? "64-bit" : "32-bit",
                runtime: commit.runtime.runtimeDescription,
                graphics: managed.configuration.graphicsBackend.displayName,
                runtimeID: commit.runtime.id,
                rootPath: managed.rootURL.path,
                prefixPath: managed.prefixURL.path,
                logsPath: managed.logsURL.path
            )
            let metadata = await matchStoreMetadata(for: [
                candidate.name,
                commit.executable.deletingPathExtension().lastPathComponent,
                commit.executable.deletingLastPathComponent().lastPathComponent,
            ])
            let gogIdentity = GOGInstalledGameDetector.detect(executable: commit.executable)
            let app = WindowsApplication(
                name: metadata?.name ?? candidate.name,
                publisher: metadata?.developer ?? "Windows application",
                executablePath: commit.executable.path,
                installerPath: candidate.url.path,
                environmentID: environment.id,
                status: commit.firstLaunch == nil ? .ready : .running,
                compatibility: communityProfile?.tier.rating ?? .unknown,
                graphics: managed.configuration.graphicsBackend.displayName,
                lastOpened: .now,
                iconSymbol: symbol(for: candidate.name),
                lastResult: commit.firstLaunch == nil ? "Compatibility prepared; ready to play" : "First launch verified",
                storeProvider: gogIdentity == nil ? metadata?.provider : .gog,
                storeExternalID: gogIdentity?.externalID ?? metadata?.externalID,
                storeMetadataOnly: metadata == nil && gogIdentity == nil ? nil : true,
                communityCompatibility: communityProfile
            )
            environments.append(environment)
            applications.append(app)
            if var metadata {
                metadata.isInstalled = false
                metadata.installPath = nil
                metadata.installedPlatform = nil
                if !storeGames.contains(where: { $0.provider == metadata.provider && $0.externalID == metadata.externalID }) {
                    storeGames.append(metadata)
                }
            }
            if let gogIdentity, let appIndex = applications.indices.last {
                adoptGOGInstallationIdentity(gogIdentity, forApplicationAt: appIndex)
            }
            await refreshAuxiliaryExecutables(for: app.id)
            if let firstLaunch = commit.firstLaunch {
                activeSessions[app.id] = firstLaunch
                beginPlaySession(appID: app.id)
                performanceLogURLs[app.id] = firstLaunch.stderrLog
                activeEnvironments[app.id] = managed
                activeRuntimes[app.id] = commit.runtime
            }
            save()
            installation.completedStages = Set(InstallationStage.allCases)
            installation.state = .succeeded(app.id)
            SoundService.shared.play(.installationCompleted)
            if let firstLaunch = commit.firstLaunch {
                startPerformanceProcessTracking(session: firstLaunch, environment: managed, runtime: commit.runtime, appID: app.id)
                monitorLauncher(session: firstLaunch, appID: app.id)
                monitorEnvironmentSession(environment: managed, runtime: commit.runtime, appID: app.id)
            }
            await refreshRuntimeStatuses()
            return app.id
        } catch is CancellationError {
            installation = InstallationProgress(state: .cancelled)
            return nil
        } catch {
            installation.state = .failed
            installation.failureMessage = error.localizedDescription
            installation.rollbackCompleted = installation.stage != .preparingRuntime
            SoundService.shared.play(.error)
            return nil
        }
    }

    /// Registers a selected installer as an installer-only Library entry and
    /// launches it directly. No game executable discovery or first-launch
    /// verification is performed in this path.
    func runInstallerOnly(_ candidate: InstallCandidate, runtimeEngine: RuntimeEngine) async -> UUID? {
        SoundService.shared.play(.installationStarted)
        installation = InstallationProgress(state: .installing, stage: .preparingRuntime)
        do {
            let commit = try await services.installer.launchInstaller(
                candidate.url,
                name: candidate.name,
                preferredEngine: runtimeEngine
            ) { [weak self] stage in
                await self?.updateInstallation(stage)
            }
            let managed = commit.environment
            let environment = WindowsEnvironment(
                id: managed.id,
                name: managed.configuration.name,
                windowsVersion: WineWindowsVersion(rawValue: managed.configuration.windowsVersion)?.displayName ?? "Windows 11",
                architecture: managed.configuration.architecture == "win64" ? "64-bit" : "32-bit",
                runtime: commit.runtime.runtimeDescription,
                graphics: commit.runtime.graphicsName,
                runtimeID: commit.runtime.id,
                rootPath: managed.rootURL.path,
                prefixPath: managed.prefixURL.path,
                logsPath: managed.logsURL.path
            )
            let app = WindowsApplication(
                name: candidate.name,
                publisher: "Game installer",
                executablePath: candidate.url.path,
                installerPath: candidate.url.path,
                environmentID: environment.id,
                status: .running,
                graphics: commit.runtime.graphicsName,
                lastOpened: .now,
                iconSymbol: "shippingbox.fill",
                lastResult: "Installer launched with \(commit.runtime.resolvedEngine.displayName)",
                applicationRole: .installer
            )
            environments.append(environment)
            applications.append(app)
            activeSessions[app.id] = commit.installerSession
            performanceLogURLs[app.id] = commit.installerSession.stderrLog
            activeEnvironments[app.id] = managed
            activeRuntimes[app.id] = commit.runtime
            installation.completedStages = [.preparingRuntime, .creatingEnvironment, .startingInstaller]
            installation.stage = .startingInstaller
            installation.state = .succeeded(app.id)
            save()
            SoundService.shared.play(.installationCompleted)
            monitorLauncher(session: commit.installerSession, appID: app.id)
            monitorEnvironmentSession(environment: managed, runtime: commit.runtime, appID: app.id)
            await refreshRuntimeStatuses()
            return app.id
        } catch is CancellationError {
            installation = InstallationProgress(state: .cancelled)
            return nil
        } catch {
            installation.state = .failed
            installation.failureMessage = error.localizedDescription
            installation.rollbackCompleted = installation.stage != .preparingRuntime
            SoundService.shared.play(.error)
            return nil
        }
    }

    private func matchStoreMetadata(for rawNames: [String]) async -> StoreLibraryGame? {
        let names = rawNames.map(Self.storeSearchTitle).filter { !$0.isEmpty }
        for name in names {
            let normalized = SteamLibraryService.normalizedStoreTitle(name)
            let localMatches = storeGames.filter {
                SteamLibraryService.normalizedStoreTitle($0.name) == normalized
                    && hasCatalogPresentationMetadata($0)
            }
            if localMatches.count == 1 { return localMatches[0] }
            if localMatches.count > 1 { continue }
            if let match = await services.steamLibrary.searchStoreGame(named: name) { return match }
        }

        // Epic and GOG expose the signed-in library, not a public title search.
        // That library is still the real provider source for matching custom installs.
        async let epicGames = try? await services.epicLibrary.loadLibrary()
        async let gogGames = try? await services.gogLibrary.loadLibrary()
        let (epic, gog) = await (epicGames ?? [], gogGames ?? [])
        for name in names {
            if let match = matchingStoreGame(named: name, in: epic) { return match }
            if let match = matchingStoreGame(named: name, in: gog) { return match }
        }
        return nil
    }

    private func hasCatalogPresentationMetadata(_ game: StoreLibraryGame) -> Bool {
        game.summary != nil
            || game.artworkPath != nil
            || game.portraitImageURL != nil
            || game.headerImageURL != nil
            || game.backgroundImageURL != nil
            || game.screenshotURLs?.isEmpty == false
            || game.videos?.isEmpty == false
            || game.storeRating != nil
    }

    private func matchingStoreGame(named name: String, in games: [StoreLibraryGame]) -> StoreLibraryGame? {
        let normalized = SteamLibraryService.normalizedStoreTitle(name)
        let exact = games.filter { SteamLibraryService.normalizedStoreTitle($0.name) == normalized }
        if exact.count == 1 { return exact[0] }
        let queryTokens = Set(normalized.split(separator: " "))
        let candidates = games.filter { game in
            let tokens = Set(SteamLibraryService.normalizedStoreTitle(game.name).split(separator: " "))
            return !queryTokens.isEmpty && queryTokens.isSubset(of: tokens)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func importedGameMetadata(
        executable: URL,
        name: String,
        gogIdentity: GOGInstalledGameIdentity?
    ) async -> StoreLibraryGame? {
        if let gogIdentity,
           let games = try? await services.gogLibrary.loadLibrary(),
           let game = games.first(where: { $0.externalID == gogIdentity.externalID }),
           hasCatalogPresentationMetadata(game) {
            return game
        }
        guard var metadata = await matchStoreMetadata(for: [
            gogIdentity?.name,
            name,
            executable.deletingPathExtension().lastPathComponent,
            executable.deletingLastPathComponent().lastPathComponent,
        ].compactMap { $0 }) else { return nil }
        if let gogIdentity {
            metadata.id = UUID()
            metadata.provider = .gog
            metadata.externalID = gogIdentity.externalID
            metadata.name = gogIdentity.name ?? metadata.name
        }
        return metadata
    }

    private func upsertImportedPresentationMetadata(_ metadata: StoreLibraryGame) {
        if let index = storeGames.firstIndex(where: { $0.storeReference == metadata.storeReference }) {
            var value = metadata
            value.id = storeGames[index].id
            value.preserveMeasuredActivity(from: storeGames[index])
            value.customArtworkPath = storeGames[index].customArtworkPath
            if let installation = installation(for: storeGames[index]) {
                value.isInstalled = installation.state.representsAnInstallation
                value.installPath = StoragePathResolver.resolve(installation.location, layout: storageLayout).path
                value.installedPlatform = installation.platform
                value.storageBytes = installation.installedSize
            } else {
                value.isInstalled = false
                value.installPath = nil
                value.installedPlatform = nil
                value.storageBytes = nil
            }
            storeGames[index] = value
        } else {
            storeGames.append(metadata)
        }
    }

    private func applyRenamedApplicationMetadata(_ metadata: StoreLibraryGame?, to applicationID: UUID, requestedName: String) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        guard applications[applicationIndex].name == requestedName else { return }
        guard let metadata else {
            applications[applicationIndex].lastResult = "Renamed; no matching metadata found in Steam, Epic Games or GOG."
            save()
            return
        }

        // Keep the user's library name; the store record supplies artwork and
        // description, while the linked application remains the display-name source.
        applications[applicationIndex].name = requestedName
        applications[applicationIndex].publisher = metadata.developer ?? applications[applicationIndex].publisher
        applications[applicationIndex].storeProvider = metadata.provider
        applications[applicationIndex].storeExternalID = metadata.externalID
        applications[applicationIndex].storeMetadataOnly = true
        applications[applicationIndex].lastResult = "Matched metadata from \(metadata.provider.rawValue)"
        if let environmentIndex = environments.firstIndex(where: { $0.id == applications[applicationIndex].environmentID }) {
            environments[environmentIndex].name = requestedName
        }

        if let existingIndex = storeGames.firstIndex(where: {
            $0.provider == metadata.provider && $0.externalID == metadata.externalID
        }) {
            var value = metadata
            value.id = storeGames[existingIndex].id
            value.preserveMeasuredActivity(from: storeGames[existingIndex])
            value.customArtworkPath = storeGames[existingIndex].customArtworkPath
            // The rename resolved a new presentation identity. Do not merge
            // the old artwork back into the fresh metadata: artworkPath is
            // preferred by GameArtworkView and could otherwise keep showing
            // the provider cover belonging to the previous title. The user's
            // explicitly selected custom cover is independent and preserved.
            if let installation = installation(for: storeGames[existingIndex]) {
                value.isInstalled = installation.state.representsAnInstallation
                value.installPath = StoragePathResolver.resolve(installation.location, layout: storageLayout).path
                value.installedPlatform = installation.platform
                value.storageBytes = installation.installedSize
            } else {
                value.isInstalled = false
                value.installPath = nil
                value.installedPlatform = nil
                value.storageBytes = nil
            }
            storeGames[existingIndex] = value
        } else {
            storeGames.append(metadata)
        }
        save()
    }

    private func enrichInstalledApplicationMetadata() async {
        guard !isEnrichingInstalledApplicationMetadata else { return }
        isEnrichingInstalledApplicationMetadata = true
        defer { isEnrichingInstalledApplicationMetadata = false }
        let candidates = applications.filter {
            guard !$0.isSteamRuntimeHost else { return false }
            guard !$0.isInstallerOnly else { return false }
            if $0.storeProvider == nil && $0.storeExternalID == nil { return true }
            guard $0.usesStoreMetadataOnly,
                  let reference = $0.storeReference else { return false }
            guard let game = storeGames.first(where: { $0.storeReference == reference }) else { return true }
            return game.artworkPath == nil
                && game.portraitImageURL == nil
                && game.headerImageURL == nil
                && game.backgroundImageURL == nil
                && game.screenshotURLs?.isEmpty != false
        }
        var changed = false
        for candidate in candidates {
            let executable = URL(fileURLWithPath: candidate.executablePath)
            var metadata: StoreLibraryGame?
            if candidate.usesStoreMetadataOnly,
               let provider = candidate.storeProvider,
               let externalID = candidate.storeExternalID {
                switch provider {
                case .steam:
                    let seed = StoreLibraryGame(provider: .steam, externalID: externalID, name: candidate.name)
                    let refreshed = await services.steamLibrary.loadDetails(for: seed)
                    metadata = refreshed.hasPresentationMetadata ? refreshed : nil
                case .epic:
                    metadata = try? await services.epicLibrary.loadLibrary().first { $0.externalID == externalID }
                case .gog:
                    metadata = try? await services.gogLibrary.loadLibrary().first { $0.externalID == externalID }
                    if metadata.map(hasCatalogPresentationMetadata) != true {
                        metadata = await matchStoreMetadata(for: [
                            candidate.name,
                            executable.deletingPathExtension().lastPathComponent,
                            executable.deletingLastPathComponent().lastPathComponent,
                        ])
                        metadata?.id = UUID()
                        metadata?.provider = .gog
                        metadata?.externalID = externalID
                        metadata?.name = candidate.name
                    }
                }
            } else if candidate.storeProvider == nil && candidate.storeExternalID == nil {
                metadata = await matchStoreMetadata(for: [
                    candidate.name,
                    executable.deletingPathExtension().lastPathComponent,
                    executable.deletingLastPathComponent().lastPathComponent,
                ])
            } else {
                metadata = nil
            }
            guard let metadata,
            let index = applications.firstIndex(where: { $0.id == candidate.id }) else { continue }
            applications[index].publisher = metadata.developer ?? applications[index].publisher
            applications[index].storeProvider = metadata.provider
            applications[index].storeExternalID = metadata.externalID
            applications[index].storeMetadataOnly = true
            upsertImportedPresentationMetadata(metadata)
            changed = true
        }
        if changed { save() }
    }

    private func adoptGOGInstallationIdentity(
        _ identity: GOGInstalledGameIdentity,
        forApplicationAt applicationIndex: Int
    ) {
        guard applications.indices.contains(applicationIndex) else { return }
        let previousReference = applications[applicationIndex].storeReference
        applications[applicationIndex].storeProvider = .gog
        applications[applicationIndex].storeExternalID = identity.externalID
        applications[applicationIndex].storeMetadataOnly = true
        applications[applicationIndex].lastResult = "Recognized installed GOG game"

        if let existingIndex = storeGames.firstIndex(where: {
            $0.provider == .gog && $0.externalID == identity.externalID
        }) {
            let game = storeGames[existingIndex]
            recordInstallation(
                for: game,
                location: identity.installationURL,
                platform: .windows,
                environmentID: applications[applicationIndex].environmentID,
                executable: URL(fileURLWithPath: applications[applicationIndex].executablePath)
            )
            return
        }

        let presentation = previousReference.flatMap { reference in
            storeGames.first { $0.storeReference == reference }
        }
        let game = StoreLibraryGame(
            provider: .gog,
            externalID: identity.externalID,
            name: identity.name ?? applications[applicationIndex].name,
            developer: presentation?.developer ?? applications[applicationIndex].publisher,
            summary: presentation?.summary,
            artworkPath: presentation?.artworkPath,
            customArtworkPath: applications[applicationIndex].customArtworkPath,
            portraitImageURL: presentation?.portraitImageURL,
            headerImageURL: presentation?.headerImageURL,
            backgroundImageURL: presentation?.backgroundImageURL,
            screenshotURLs: presentation?.screenshotURLs,
            videos: presentation?.videos,
            storeRating: presentation?.storeRating,
            supportsWindows: true,
            supportsNativeMacOS: false,
            isInstalled: true,
            installPath: identity.installationURL.path,
            installedPlatform: .windows,
            storageBytes: applications[applicationIndex].storageBytes,
            compatibility: presentation?.compatibility
        )
        storeGames.append(game)
        recordInstallation(
            for: game,
            location: identity.installationURL,
            platform: .windows,
            environmentID: applications[applicationIndex].environmentID,
            executable: URL(fileURLWithPath: applications[applicationIndex].executablePath)
        )
    }

    nonisolated static func storeSearchTitle(from installerName: String) -> String {
        var value = installerName.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
        if value.lowercased().hasPrefix("setup ") { value.removeFirst("setup ".count) }
        for suffix in [" setup", " installer", " install"] where value.lowercased().hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func beginInstallation(_ candidate: InstallCandidate, runtimeEngine: RuntimeEngine? = nil) {
        guard installationTask == nil else { return }
        let token = UUID()
        installationToken = token
        installationTask = Task { [weak self] in
            guard let self else { return nil }
            let result = await self.install(candidate, runtimeEngine: runtimeEngine)
            if self.installationToken == token {
                self.installationTask = nil
                self.installationToken = nil
            }
            return result
        }
    }

    func beginInstallerLaunch(_ candidate: InstallCandidate, runtimeEngine: RuntimeEngine) {
        guard installationTask == nil else { return }
        let token = UUID()
        installationToken = token
        installationTask = Task { [weak self] in
            guard let self else { return nil }
            let result = await self.runInstallerOnly(candidate, runtimeEngine: runtimeEngine)
            if self.installationToken == token {
                self.installationTask = nil
                self.installationToken = nil
            }
            return result
        }
    }

    func cancelInstallation() {
        installationTask?.cancel()
        installationTask = nil
        installationToken = nil
        installation = InstallationProgress(state: .cancelled)
    }

    func resetInstallation() {
        installationTask?.cancel()
        installationTask = nil
        installationToken = nil
        installation = InstallationProgress()
    }

    private func beginLibrarySync(_ provider: GameLibraryProvider) {
        activeLibrarySyncs.insert(provider)
        librarySyncStates[provider] = .syncing(provider)
        librarySyncState = .syncing(provider)
    }

    private func finishLibrarySync(_ provider: GameLibraryProvider) {
        activeLibrarySyncs.remove(provider)
        if let next = GameLibraryProvider.allCases.first(where: { activeLibrarySyncs.contains($0) }) {
            librarySyncState = .syncing(next)
        } else {
            librarySyncState = librarySyncStates[provider] ?? .idle
        }
    }

    func isLibrarySyncing(_ provider: GameLibraryProvider) -> Bool {
        activeLibrarySyncs.contains(provider)
    }

    func syncSteamLibrary() {
        guard !activeLibrarySyncs.contains(.steam) else { return }
        beginLibrarySync(.steam)
        Task {
                do {
                    let imported = try await services.steamLibrary.loadLibrary()
                    let existingGames = Dictionary(
                        uniqueKeysWithValues: storeGames
                            .filter { $0.provider == .steam }
                            .map { ($0.externalID, $0) }
                    )
                    let normalized = imported.map { game in
                        var value = game
                        value.entitlementState = .available
                        if let existing = existingGames[game.externalID] {
                            value.id = existing.id
                            value.preserveMeasuredActivity(from: existing)
                            value.preservePresentationMetadata(from: existing)
                        }
                        return value
                    }
                    adoptProviderInstallations(normalized)
                    storeGames.removeAll { $0.provider == .steam }
                    storeGames.append(contentsOf: normalized)
                    preserveCustomInstalledMetadata(for: .steam, excluding: Set(normalized.map(\.externalID)), from: existingGames)
                    storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    librarySyncStates[.steam] = .succeeded(.steam, count: normalized.count)
                    save()
                } catch {
                    librarySyncStates[.steam] = .failed(.steam, message: SecretRedactor.redact(error.localizedDescription))
                    present(error, title: "Steam Library couldn’t be imported", stage: "Reading the signed-in Steam library")
                }
                finishLibrarySync(.steam)
            }
    }

    func installSteamWindowsGame(_ game: StoreLibraryGame) {
        let key = storeOperationKey(for: game)
        guard game.provider == .steam,
              game.supportsWindows != false,
              game.resolvedEntitlementState.isUsable,
              linkedApplication(for: game) == nil,
              storeGameOperations[key] == nil else { return }
        let poolKey = steamPoolKey(for: game)
        let token = UUID()
        storeOperationTokens[key] = token
        storeGameOperations[key] = .installing(StoreGameOperationProgress(
            message: "Preparing Steam for Windows…",
            fractionCompleted: nil
        ))
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                if let host = steamRuntimeHost(poolKey: poolKey) {
                    try await launchSteamInstall(game, using: host)
                } else {
                    let prepared = try await services.steamWindows.prepareClient(poolKey: poolKey) { [weak self] stage in
                        await self?.updateSteamPreparation(stage, key: key, token: token)
                    }
                    try await registerSteamRuntimeHost(prepared)
                    try await launchSteamInstall(game, applicationID: game.id, steamExecutable: prepared.steamExecutable, environment: prepared.installation.environment, runtime: prepared.installation.runtime)
                }
                try Task.checkCancellation()
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .awaitingProvider("Steam for Windows is open. Sign in and install the game there, then refresh this status.")
                storeOperationTasks[key] = nil
                save()
            } catch is CancellationError {
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(SecretRedactor.redact(error.localizedDescription))
                storeOperationTasks[key] = nil
                present(error, title: "\(game.name) couldn’t be prepared", stage: "Installing Valve’s Windows Steam client in Boreal")
            }
        }
        storeOperationTasks[key] = task
    }

    func refreshSteamWindowsGame(_ game: StoreLibraryGame) {
        let key = storeOperationKey(for: game)
        guard game.provider == .steam,
              let host = steamRuntimeHost(poolKey: steamPoolKey(for: game)),
              let environmentRecord = environment(id: host.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let appIndex = applications.firstIndex(where: {
                  $0.storeProvider == .steam && $0.storeExternalID == game.externalID && !$0.isSteamRuntimeHost
              }) else {
            refreshSteamWindowsGameWithoutApplication(game, key: key)
            return
        }
        guard let installation = SteamWindowsService.installedGameDirectory(appID: game.externalID, in: managed) else {
            storeGameOperations[key] = .awaitingProvider("Steam has not finished installing this game in the Windows Steam bottle yet.")
            return
        }
        applications[appIndex].executablePath = host.executablePath
        applications[appIndex].installerPath = "steam-windows-game"
        applications[appIndex].status = .ready
        applications[appIndex].storageBytes = GameStorage.allocatedSize(of: installation) ?? 0
        markSteamGameInstalled(game, installationPath: installation.path, environmentID: host.environmentID)
        storeGameOperations[key] = nil
        storeOperationTasks[key] = nil
        storeOperationTokens[key] = nil
        save()
    }

    private func refreshSteamWindowsGameWithoutApplication(_ game: StoreLibraryGame, key: String) {
        guard game.provider == .steam, let host = steamRuntimeHost(poolKey: steamPoolKey(for: game)),
              let environmentRecord = environment(id: host.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let installation = SteamWindowsService.installedGameDirectory(appID: game.externalID, in: managed) else {
            storeGameOperations[key] = .awaitingProvider("Steam has not finished installing this game in the Windows Steam bottle yet.")
            return
        }
        let app = steamWindowsApplication(
            game: game,
            executable: URL(fileURLWithPath: host.executablePath),
            environmentID: host.environmentID,
            status: .ready,
            graphics: environmentRecord.graphics,
            poolKey: steamPoolKey(for: game)
        )
        applications.append(app)
        Task {
            await refreshAuxiliaryExecutables(for: app.id, searchRoot: installation)
            save()
        }
        if let index = applications.firstIndex(where: { $0.id == app.id }) {
            applications[index].storageBytes = GameStorage.allocatedSize(of: installation) ?? 0
        }
        markSteamGameInstalled(game, installationPath: installation.path, environmentID: host.environmentID)
        storeGameOperations[key] = nil
        storeOperationTasks[key] = nil
        storeOperationTokens[key] = nil
        save()
    }

    private func markSteamGameInstalled(_ game: StoreLibraryGame, installationPath: String, environmentID: UUID? = nil) {
        guard let index = storeGames.firstIndex(where: { $0.id == game.id }) else { return }
        storeGames[index].isInstalled = true
        storeGames[index].installPath = installationPath
        storeGames[index].installedPlatform = .windows
        storeGames[index].storageBytes = GameStorage.allocatedSize(of: URL(fileURLWithPath: installationPath))
        recordInstallation(
            for: game,
            location: URL(fileURLWithPath: installationPath, isDirectory: true),
            platform: .windows,
            environmentID: environmentID
        )
        SoundService.shared.play(.downloadCompleted)
    }

    private func steamRuntimeHost(poolKey: String = "shared") -> WindowsApplication? {
        applications.first {
            $0.isSteamRuntimeHost
                && ($0.steamPoolKey ?? "shared") == poolKey
                && FileManager.default.fileExists(atPath: $0.executablePath)
        }
    }

    private func steamPoolKey(for game: StoreLibraryGame) -> String {
        if let application = applications.first(where: {
            !$0.isSteamRuntimeHost
                && $0.storeProvider == game.provider
                && $0.storeExternalID == game.externalID
        }), let persistedPoolKey = application.steamPoolKey {
            return persistedPoolKey
        }
        let hasDedicatedCompatibility = GameGraphicsProfiles.profile(
            provider: game.provider,
            externalID: game.externalID
        )?.enforcedBackend != nil
            || GameRuntimeProfiles.requiredEngine(
                provider: game.provider,
                externalID: game.externalID
            ) != nil
        return hasDedicatedCompatibility ? "dedicated:\(game.externalID)" : "shared"
    }

    private func registerSteamRuntimeHost(_ prepared: SteamWindowsClientCommit) async throws {
        let managed = prepared.installation.environment
        guard let firstLaunch = prepared.installation.firstLaunch else {
            throw SteamWindowsError.clientExecutableMissing
        }
        let environment = WindowsEnvironment(
            id: managed.id,
            name: prepared.poolKey == "shared" ? "Steam for Windows" : "Steam for Windows · \(prepared.poolKey)",
            runtime: prepared.installation.runtime.runtimeDescription,
            graphics: prepared.installation.runtime.graphicsName,
            runtimeID: prepared.installation.runtime.id,
            rootPath: managed.rootURL.path,
            prefixPath: managed.prefixURL.path,
            logsPath: managed.logsURL.path
        )
        let host = WindowsApplication(
            name: "Steam for Windows",
            publisher: "Valve",
            executablePath: prepared.steamExecutable.path,
            installerPath: "steam-windows-client",
            environmentID: managed.id,
            status: .running,
            graphics: prepared.installation.runtime.graphicsName,
            lastOpened: .now,
            iconSymbol: "gamecontroller.fill",
            lastResult: "Steam for Windows manages downloads and launch",
            steamPoolKey: prepared.poolKey
        )
        environments.append(environment)
        applications.append(host)
        activeSessions[host.id] = firstLaunch
        activeEnvironments[host.id] = managed
        activeRuntimes[host.id] = prepared.installation.runtime
        save()
        monitorLauncher(session: firstLaunch, appID: host.id)
        monitorEnvironmentSession(environment: managed, runtime: prepared.installation.runtime, appID: host.id)
    }

    private func launchSteamInstall(_ game: StoreLibraryGame, using host: WindowsApplication) async throws {
        guard let environmentRecord = environment(id: host.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let runtime = try await runtime(for: environmentRecord) else {
            throw InstallerServiceError.noRuntimeAvailable
        }
        try await launchSteamInstall(
            game,
            applicationID: host.id,
            steamExecutable: URL(fileURLWithPath: host.executablePath),
            environment: managed,
            runtime: runtime
        )
    }

    private func launchSteamInstall(
        _ game: StoreLibraryGame,
        applicationID: UUID,
        steamExecutable: URL,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) async throws {
        let bootstrapWindowsPlan = SteamWindowsService.bootstrapPlan(steamExecutable: steamExecutable)
        let bootstrap = try await services.launchCoordinator.start(
            plan: await makeLaunchPlan(
                bootstrapWindowsPlan,
                applicationID: applicationID,
                provider: .steam,
                externalID: game.externalID,
                environment: environment,
                runtime: runtime,
                profile: nil
            ),
            environment: environment,
            runtime: runtime
        ).processSession
        Task { _ = try? await services.processRunner.waitForExit(bootstrap) }
        try await Task.sleep(for: .milliseconds(400))
        let windowsPlan = SteamWindowsService.protocolPlan("steam://install/\(game.externalID)", steamExecutable: steamExecutable)
        let session = try await services.launchCoordinator.start(
            plan: await makeLaunchPlan(
                windowsPlan,
                applicationID: applicationID,
                provider: .steam,
                externalID: game.externalID,
                environment: environment,
                runtime: runtime,
                profile: nil
            ),
            environment: environment,
            runtime: runtime
        ).processSession
        Task { _ = try? await services.processRunner.waitForExit(session) }
    }

    private func makeLaunchPlan(
        _ windowsPlan: WindowsLaunchPlan,
        applicationID: UUID,
        provider: GameLibraryProvider?,
        externalID: String?,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime,
        profile: WineCompatibilityProfile?,
        directXAPIOverride: GraphicsAPI? = nil,
        gameRoot: URL? = nil
    ) async -> LaunchPlan {
        let storeReference = provider.flatMap { provider in
            externalID.map { externalID in StoreReference(provider: provider, externalID: externalID) }
        }
        var launchWindowsPlan = windowsPlan
        let advancedConfiguration = advancedConfigurations[applicationID]
        if let advancedConfiguration {
            launchWindowsPlan = applying(advancedConfiguration, to: launchWindowsPlan)
        }
        let installationID = installations.first {
            $0.gameID == applicationID || $0.storeReference == storeReference
        }?.id
        let requestedBackend = profile?.graphicsBackend ?? .automatic
        let selectedAPI = directXAPIOverride ?? profile?.graphicsAPI ?? environment.configuration.graphicsAPI
        let resolverAPI = directXAPIOverride == nil
            ? selectedAPI
            : (profile?.graphicsAPI ?? environment.configuration.graphicsAPI)
        let gameProfile = provider.flatMap { provider in
            externalID.flatMap { externalID in GameGraphicsProfiles.profile(provider: provider, externalID: externalID) }
        }
        let resolvedAPI: GraphicsAPI = {
            guard selectedAPI == .automatic else { return selectedAPI }
            if let defaultAPI = gameProfile?.defaultAPI, defaultAPI != .automatic { return defaultAPI }
            return GraphicsAPIDetector.detect(executable: windowsPlan.executable) ?? .automatic
        }()
        let architecture = environment.configuration.resolvedPrefixArchitecture(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true)
        let graphicsResolution = GraphicsBackendResolver.resolve(
            api: resolverAPI,
            requestedBackend: requestedBackend,
            gameProfile: environment.purpose == .sharedStore ? nil : gameProfile,
            runtime: runtime,
            architecture: architecture,
            fallback: profile?.graphicsFallback ?? .none
        )
        var temporalWindowsPlan = launchWindowsPlan
        var temporalConfiguration = profile?.temporalUpscaling ?? environment.configuration.temporalUpscaling
        if temporalConfiguration.mode == .automatic,
           profile?.upscalingBridge == .ngxToMetalFX || environment.configuration.upscalingBridge == .ngxToMetalFX {
            // Preserve older persisted profiles while exposing the explicit
            // requested/effective temporal path in the new launch plan.
            temporalConfiguration.mode = .metalFXBridge
        }
        let temporalRoot = (gameRoot ?? launchWindowsPlan.executable.deletingLastPathComponent()).standardizedFileURL
        let temporalComponentStore = ManagedTemporalComponentStore(
            rootURL: runtime.rootURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Components", directoryHint: .isDirectory)
        )
        let temporalGame = await services.gameUpscalerAnalyzer.analyze(
            gameRoot: temporalRoot,
            executable: launchWindowsPlan.processExecutablePath.map { URL(fileURLWithPath: $0) } ?? launchWindowsPlan.executable
        )
        let metalFX = await Task.detached(priority: .utility) {
            MetalFXBridgeAnalyzer.inspect(runtime: runtime)
        }.value
        let componentReferences = await Task.detached(priority: .utility) {
            (
                temporalComponentStore.reference(for: .dlsstweaks),
                temporalComponentStore.reference(for: .optiScaler)
            )
        }.value
        let temporalPlan = TemporalUpscalingResolutionEngine.resolve(
            game: temporalGame,
            runtime: runtime,
            graphicsStack: graphicsResolution.stack,
            configuration: temporalConfiguration,
            metalFX: metalFX,
            dlsstweaks: componentReferences.0,
            optiScaler: componentReferences.1,
            applicationID: applicationID
        )
        temporalWindowsPlan.temporalUpscalingPlan = temporalPlan
        temporalWindowsPlan.configurationFingerprint = ConfigurationFingerprint.make(
            runtimeFingerprint: "\(runtime.id):\(runtime.wineVersion)",
            graphicsStack: graphicsResolution.stack,
            componentVersions: temporalPlan.componentVersions,
            prefixMode: environment.configuration.resolvedPrefixMode(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true),
            windowsVersion: WineWindowsVersion(rawValue: environment.configuration.windowsVersion) ?? .windows11,
            dependencies: environment.configuration.requiredDependencies.sorted { $0.rawValue < $1.rawValue },
            dllOverrides: advancedConfiguration?.dllOverrides ?? [],
            environmentVariables: advancedConfiguration?.environmentVariables ?? [],
            upscalingConfiguration: temporalPlan.fingerprintSegment
        )
        return LaunchPlan(
            traceID: OperationTraceID(),
            applicationID: applicationID,
            installationID: installationID,
            environmentID: environment.id,
            runtimeID: runtime.id,
            provider: provider,
            externalID: externalID,
            windowsPlan: temporalWindowsPlan,
            graphicsBackend: graphicsResolution.stack.backend,
            compatibilityProfile: profile,
            graphicsStack: graphicsResolution.stack,
            prefixMode: environment.configuration.resolvedPrefixMode(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true),
            windowsVersion: WineWindowsVersion(rawValue: environment.configuration.windowsVersion) ?? .windows11,
            directXAPI: resolvedAPI,
            dependencies: environment.configuration.requiredDependencies.sorted { $0.rawValue < $1.rawValue },
            environmentPurpose: environment.purpose,
            executableArchitecture: WindowsExecutableArchitecture.inspect(windowsPlan.executable),
            temporalUpscalingPlan: temporalPlan,
            configurationFingerprint: temporalWindowsPlan.configurationFingerprint
        )
    }

    private func applying(
        _ configuration: GameAdvancedConfiguration,
        to windowsPlan: WindowsLaunchPlan
    ) -> WindowsLaunchPlan {
        var result = windowsPlan
        let owned = result.environment.filter { EnvironmentVariableSanitizer.borealOwnedKeys.contains($0.key.uppercased()) }
        let sanitized = EnvironmentVariableSanitizer.merge(
            base: result.environment,
            custom: configuration.environmentVariables,
            borealOwned: owned,
            developerMode: UserDefaults.standard.bool(forKey: "developerMode")
        )
        result.environment = sanitized.values

        let managedOverrides = result.environment["WINEDLLOVERRIDES"].map(parseDLLOverrides) ?? []
        let mergedOverrides = DLLOverrideMerger.merge(managed: managedOverrides, manual: configuration.dllOverrides)
        result.environment.removeValue(forKey: "WINEDLLOVERRIDES")
        if !mergedOverrides.overrides.isEmpty {
            result.environment["WINEDLLOVERRIDES"] = mergedOverrides.overrides.map {
                "\($0.library)=\($0.mode.wineValue)"
            }.joined(separator: ";")
        }
        return result
    }

    private func parseDLLOverrides(_ value: String) -> [DLLOverride] {
        value.split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let mode: DLLOverrideMode
            switch String(parts[1]) {
            case "n": mode = .native
            case "b": mode = .builtin
            case "n,b": mode = .nativeThenBuiltin
            case "b,n": mode = .builtinThenNative
            case "": mode = .disabled
            default: return nil
            }
            return DLLOverride(library: String(parts[0]), mode: mode)
        }
    }

    func refreshEpicConnection() {
        Task { epicConnectionState = await services.epicLibrary.connectionState() }
    }

    func prepareEpicSupport() {
        guard !epicConnectionState.isBusy else { return }
        epicConnectionState = .preparingSupport
        Task {
            do {
                try await services.epicLibrary.prepareSupport()
                epicConnectionState = await services.epicLibrary.connectionState()
            } catch {
                epicConnectionState = .failed(SecretRedactor.redact(error.localizedDescription))
                present(error, title: "Epic support couldn’t be installed", stage: "Downloading and verifying Legendary")
            }
        }
    }

    func connectEpic(authorizationCode: String) {
        guard !epicConnectionState.isBusy else { return }
        epicConnectionState = .authenticating
        Task {
            do {
                let displayName = try await services.epicLibrary.authenticate(authorizationCode: authorizationCode)
                epicConnectionState = .connected(displayName: displayName)
                SoundService.shared.play(.confirmation)
                syncEpicLibrary()
            } catch {
                epicConnectionState = .failed(SecretRedactor.redact(error.localizedDescription))
                present(error, title: "Epic account couldn’t be connected", stage: "Exchanging the one-time authorization code")
            }
        }
    }

    func disconnectEpic() {
        guard !epicConnectionState.isBusy else { return }
        Task {
            do {
                try await services.epicLibrary.disconnect()
                removeStoreGamesExceptCustomInstalledMetadata(for: .epic)
                epicConnectionState = .disconnected
                save()
            } catch {
                epicConnectionState = .failed(SecretRedactor.redact(error.localizedDescription))
                present(error, title: "Epic account couldn’t be disconnected", stage: "Deleting Legendary account credentials")
            }
        }
    }

    func syncEpicLibrary() {
        guard !activeLibrarySyncs.contains(.epic) else { return }
        beginLibrarySync(.epic)
        Task {
                do {
                    let imported = try await services.epicLibrary.loadLibrary()
                    let existingGames = Dictionary(
                        uniqueKeysWithValues: storeGames
                            .filter { $0.provider == .epic }
                            .map { ($0.externalID, $0) }
                    )
                    let normalized = imported.map { game in
                        var value = game
                        value.entitlementState = .available
                        if let existing = existingGames[game.externalID] {
                            value.id = existing.id
                            value.preserveMeasuredActivity(from: existing)
                            value.preservePresentationMetadata(from: existing)
                        }
                        return value
                    }
                    let enriched = await enrichCompatibility(in: normalized)
                    adoptProviderInstallations(enriched)
                    storeGames.removeAll { $0.provider == .epic }
                    storeGames.append(contentsOf: enriched)
                    preserveLocalInstalledEntitlements(for: .epic, excluding: Set(enriched.map(\.externalID)), from: existingGames)
                    preserveCustomInstalledMetadata(for: .epic, excluding: Set(enriched.map(\.externalID)), from: existingGames)
                    storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    librarySyncStates[.epic] = .succeeded(.epic, count: normalized.count)
                    epicConnectionState = await services.epicLibrary.connectionState()
                    save()
                } catch {
                    librarySyncStates[.epic] = .failed(.epic, message: SecretRedactor.redact(error.localizedDescription))
                    epicConnectionState = await services.epicLibrary.connectionState()
                    present(error, title: "Epic Library couldn’t be imported", stage: "Reading the connected Epic account")
                }
                finishLibrarySync(.epic)
            }
    }

    func refreshGOGConnection() {
        Task { gogConnectionState = await services.gogLibrary.connectionState() }
    }

    func prepareGOGSupport() {
        guard !gogConnectionState.isBusy else { return }
        gogConnectionState = .preparingSupport
        Task {
            do {
                try await services.gogLibrary.prepareSupport()
                gogConnectionState = await services.gogLibrary.connectionState()
            } catch {
                gogConnectionState = .failed(SecretRedactor.redact(error.localizedDescription))
                present(error, title: "GOG support couldn’t be installed", stage: "Downloading and verifying heroic-gogdl")
            }
        }
    }

    func connectGOG(authorizationCode: String) {
        guard !gogConnectionState.isBusy else { return }
        gogConnectionState = .authenticating
        Task {
            do {
                let displayName = try await services.gogLibrary.authenticate(authorizationCode: authorizationCode)
                gogConnectionState = .connected(displayName: displayName)
                SoundService.shared.play(.confirmation)
                syncGOGLibrary()
            } catch {
                gogConnectionState = .failed(SecretRedactor.redact(error.localizedDescription))
                present(error, title: "GOG account couldn’t be connected", stage: "Exchanging the one-time authorization code")
            }
        }
    }

    func disconnectGOG() {
        guard !gogConnectionState.isBusy else { return }
        Task {
            do {
                try await services.gogLibrary.disconnect()
                removeStoreGamesExceptCustomInstalledMetadata(for: .gog)
                gogConnectionState = .disconnected
                save()
            } catch {
                gogConnectionState = .failed(SecretRedactor.redact(error.localizedDescription))
                present(error, title: "GOG account couldn’t be disconnected", stage: "Deleting local GOG credentials")
            }
        }
    }

    func syncGOGLibrary() {
        guard !activeLibrarySyncs.contains(.gog) else { return }
        beginLibrarySync(.gog)
        Task {
                do {
                    let imported = try await services.gogLibrary.loadLibrary()
                    let existingGames = Dictionary(
                        uniqueKeysWithValues: storeGames.filter { $0.provider == .gog }.map { ($0.externalID, $0) }
                    )
                    let normalized = imported.map { game in
                        var value = game
                        value.entitlementState = .available
                        if let existing = existingGames[game.externalID] {
                            value.id = existing.id
                            value.preserveMeasuredActivity(from: existing)
                            value.preservePresentationMetadata(from: existing)
                        }
                        return value
                    }
                    let enriched = await enrichCompatibility(in: normalized)
                    adoptProviderInstallations(enriched)
                    storeGames.removeAll { $0.provider == .gog }
                    storeGames.append(contentsOf: enriched)
                    preserveLocalInstalledEntitlements(for: .gog, excluding: Set(enriched.map(\.externalID)), from: existingGames)
                    preserveCustomInstalledMetadata(for: .gog, excluding: Set(enriched.map(\.externalID)), from: existingGames)
                    storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    librarySyncStates[.gog] = .succeeded(.gog, count: normalized.count)
                    gogConnectionState = await services.gogLibrary.connectionState()
                    save()
                } catch {
                    librarySyncStates[.gog] = .failed(.gog, message: SecretRedactor.redact(error.localizedDescription))
                    gogConnectionState = await services.gogLibrary.connectionState()
                    present(error, title: "GOG Library couldn’t be imported", stage: "Reading the connected GOG account")
                }
                finishLibrarySync(.gog)
            }
    }

    func syncLibrary(_ provider: GameLibraryProvider) {
        switch provider {
        case .steam: syncSteamLibrary()
        case .epic: syncEpicLibrary()
        case .gog: syncGOGLibrary()
        }
    }

    private func preserveCustomInstalledMetadata(
        for provider: GameLibraryProvider,
        excluding importedExternalIDs: Set<String>,
        from existingGames: [String: StoreLibraryGame]
    ) {
        let retainedExternalIDs = Set(applications.compactMap { application -> String? in
            guard application.usesStoreMetadataOnly,
                  application.storeProvider == provider,
                  let externalID = application.storeExternalID,
                  !importedExternalIDs.contains(externalID) else { return nil }
            return externalID
        })
        let alreadyRetainedExternalIDs = Set(storeGames
            .filter { $0.provider == provider }
            .map(\.externalID))
        storeGames.append(contentsOf: retainedExternalIDs
            .subtracting(alreadyRetainedExternalIDs)
            .compactMap { existingGames[$0] })
    }

    private func removeStoreGamesExceptCustomInstalledMetadata(for provider: GameLibraryProvider) {
        // Disconnecting credentials must not erase local installations from
        // the library. Their entitlement is unavailable, but the canonical
        // GameInstallation and linked application remain intact and can still
        // be opened or repaired when the account is connected again.
        for index in storeGames.indices where storeGames[index].provider == provider {
            storeGames[index].entitlementState = .accountDisconnected
        }
    }

    private func preserveLocalInstalledEntitlements(
        for provider: GameLibraryProvider,
        excluding importedExternalIDs: Set<String>,
        from existingGames: [String: StoreLibraryGame]
    ) {
        for existing in existingGames.values
        where existing.provider == provider
            && !importedExternalIDs.contains(existing.externalID)
            && isInstalled(existing) {
            var orphan = existing
            orphan.entitlementState = .accountDisconnected
            storeGames.append(orphan)
        }
    }

    /// Provider imports can discover an installation that did not exist in
    /// Boreal's canonical database yet. Ingest that filesystem fact before
    /// replacing the provider projection; thereafter all launch/UI decisions
    /// read `GameInstallation`, not the provider payload's legacy flags.
    private func adoptProviderInstallations(_ games: [StoreLibraryGame]) {
        for game in games where game.isInstalled {
            guard let path = game.installPath else { continue }
            let location = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard FileManager.default.fileExists(atPath: location.path) else { continue }
            recordInstallation(
                for: game,
                location: location,
                platform: game.installedPlatform ?? preferredStoreInstallationPlatform(for: game)
            )
        }
    }

    /// Keeps connected libraries current three times per day while Boreal is running.
    /// The persisted deadline also makes an overdue refresh run after the next launch.
    func runAutomaticLibraryRefreshLoop() async {
        guard !isRunningAutomaticLibraryRefresh else { return }
        isRunningAutomaticLibraryRefresh = true
        defer { isRunningAutomaticLibraryRefresh = false }

        while !Task.isCancelled {
            let now = Date.now
            if Self.automaticLibraryRefreshIsDue(lastRefresh: lastAutomaticLibraryRefreshAt, now: now) {
                lastAutomaticLibraryRefreshAt = now
                save()
                await refreshConnectedLibrariesInBackground()
            }

            let elapsed = Date.now.timeIntervalSince(lastAutomaticLibraryRefreshAt ?? .distantPast)
            let remaining = max(1, Self.automaticLibraryRefreshInterval - elapsed)
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
        }
    }

    nonisolated static func automaticLibraryRefreshIsDue(lastRefresh: Date?, now: Date) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= automaticLibraryRefreshInterval
    }

    private func refreshConnectedLibrariesInBackground() async {
        var providers: [GameLibraryProvider] = []
        if storeGames.contains(where: { $0.provider == .steam }) {
            providers.append(.steam)
        }

        epicConnectionState = await services.epicLibrary.connectionState()
        if case .connected = epicConnectionState { providers.append(.epic) }

        gogConnectionState = await services.gogLibrary.connectionState()
        if case .connected = gogConnectionState { providers.append(.gog) }

        for provider in providers {
            guard UserDefaults.standard.object(forKey: "automaticLibrarySync." + provider.rawValue) as? Bool != false else { continue }
            guard !Task.isCancelled else { return }
            syncLibrary(provider)
        }
        await waitForLibrarySyncToFinish()
    }

    private func waitForLibrarySyncToFinish() async {
        while !activeLibrarySyncs.isEmpty {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func installEpicGame(_ game: StoreLibraryGame) {
        installStoreGame(game)
    }

    func installStoreGame(_ game: StoreLibraryGame, destinationRoot: URL? = nil) {
        guard game.resolvedEntitlementState.isUsable else {
            presentedIssue = BorealIssue(
                title: "Store account is disconnected",
                stage: "The entitlement for (game.name) is not available.",
                recovery: "Reconnect (game.provider.rawValue) before installing this game. Existing local files were kept.",
                technicalDetails: "\(game.provider.rawValue):\(game.externalID)"
            )
            return
        }
        let platform = preferredStoreInstallationPlatform(for: game)
        startStoreGameInstallation(
            game,
            destinationRoot: destinationRoot ?? defaultGameInstallationRoot(for: game.provider),
            platform: platform
        )
    }

    /// Epic's catalog can advertise a macOS build, but Boreal's Epic launch
    /// contract is the managed Windows path returned by Legendary. Keep the
    /// catalog badge independent from the platform used for installation and
    /// launch preparation.
    func preferredStoreInstallationPlatform(for game: StoreLibraryGame) -> StoreGameInstallationPlatform {
        if game.provider == .epic { return .windows }
        return game.supportsNativeMacOS == true ? .nativeMacOS : .windows
    }

    func usesManagedRuntime(for game: StoreLibraryGame) -> Bool {
        preferredStoreInstallationPlatform(for: game) == .windows && game.provider != .steam
    }

    func addExistingWindowsApp(at selectedURL: URL, runtimeEngine: RuntimeEngine? = nil) {
        let selected = selectedURL.standardizedFileURL
        guard installationTask == nil else { return }
        guard selected.pathExtension.caseInsensitiveCompare("exe") == .orderedSame,
              FileManager.default.fileExists(atPath: selected.path),
              ExecutableDiscovery.isEligibleExecutablePath(selected.lastPathComponent) else {
            presentedIssue = BorealIssue(
                title: "This game couldn’t be added",
                stage: "Validating the selected Windows executable.",
                recovery: "Choose the game’s main .exe file, not an installer, updater, helper, or uninstaller.",
                technicalDetails: selected.path
            )
            return
        }

        let name = selected.deletingPathExtension().lastPathComponent
        let gogIdentity = GOGInstalledGameDetector.detect(executable: selected)
        let architecture = WindowsExecutableArchitecture.inspect(selected)
        let engine = runtimeEngine
            ?? (UnityIL2CPPRuntimeCompatibility.requiresModernWine(at: selected) ? .wine : nil)
        let environmentArchitecture = architecture == .x86 ? "win32" : "win64"
        SoundService.shared.play(.installationStarted)
        installation = InstallationProgress(state: .installing, stage: .preparingRuntime)
        let task = Task<UUID?, Never> { [weak self] in
            guard let self else { return nil }
            var createdEnvironment: ManagedBorealEnvironment?
            do {
                let metadata = await importedGameMetadata(
                    executable: selected,
                    name: name,
                    gogIdentity: gogIdentity
                )
                let gameProfile = metadata.flatMap {
                    GameGraphicsProfiles.profile(provider: $0.provider, externalID: $0.externalID)
                }
                var automaticProfile = WineCompatibilityProfile.default
                if let enforcedBackend = gameProfile?.enforcedBackend {
                    automaticProfile.graphicsBackend = enforcedBackend
                }
                let analysis = ExecutableCompatibilityAnalyzer.analyze(
                    root: selected.deletingLastPathComponent(),
                    applicationName: name,
                    knownPrimary: selected
                )
                guard let primary = analysis.gameExecutable else {
                    throw CompatibilityPreparationError.noGameExecutable(selected.deletingLastPathComponent())
                }
                let directXAPI = CompatibilityPreparationResolver.directXAPI(
                    executable: primary.url,
                    userProfile: automaticProfile,
                    gameProfile: gameProfile
                )
                let runtime = try await services.runtimeManager.prepareReadyRuntime(for: RuntimeSelectionRequest(
                    architectures: analysis.requiredArchitectures.isEmpty ? [architecture] : analysis.requiredArchitectures,
                    requestedBackend: automaticProfile.graphicsBackend,
                    directXAPI: directXAPI,
                    gameProfile: gameProfile,
                    requiredEngine: metadata.flatMap {
                        GameRuntimeProfiles.requiredEngine(provider: $0.provider, externalID: $0.externalID)
                    } ?? engine,
                    runtimeIDOverride: automaticProfile.runtimeIDOverride
                ))
                let resolved = try CompatibilityPreparationResolver.resolve(
                    analysis: analysis,
                    userProfile: automaticProfile,
                    gameProfile: gameProfile,
                    runtime: runtime
                )
                automaticProfile.graphicsAPI = resolved.directXAPI
                automaticProfile.graphicsBackend = resolved.graphicsStack.backend
                automaticProfile.prefixMode = resolved.prefixMode
                automaticProfile.architecture = resolved.executableArchitecture == .x86 ? .win32 : .win64
                automaticProfile.requiredDependencies = Set(resolved.dependencies)
                await updateInstallation(.creatingEnvironment)
                let managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: name, profile: automaticProfile),
                    runtime: runtime
                )
                createdEnvironment = managed
                // Adding an already installed game must only prepare the
                // environment. Its executable is registered below and is
                // launched only through the Library Play action.
                try await services.environmentManager.initialize(managed, runtime: runtime)
                try Task.checkCancellation()
                let communityProfile: CommunityCompatibility? = nil
                let environment = WindowsEnvironment(
                    id: managed.id,
                    name: name,
                    architecture: environmentArchitecture == "win64" ? "64-bit" : "32-bit",
                    runtime: runtime.runtimeDescription,
                    graphics: resolved.graphicsStack.backend.displayName,
                    runtimeID: runtime.id,
                    rootPath: managed.rootURL.path,
                    prefixPath: managed.prefixURL.path,
                    logsPath: managed.logsURL.path
                )
                let app = WindowsApplication(
                    name: metadata?.name ?? gogIdentity?.name ?? name,
                    publisher: metadata?.developer ?? "Windows application",
                    executablePath: selected.path,
                    installerPath: "existing-installation",
                    environmentID: managed.id,
                    status: .ready,
                    compatibility: communityProfile?.tier.rating ?? .unknown,
                    graphics: resolved.graphicsStack.backend.displayName,
                    storageBytes: GameStorage.allocatedSize(of: selected.deletingLastPathComponent()) ?? 0,
                    iconSymbol: symbol(for: name),
                    lastResult: "Existing installation added",
                    storeProvider: gogIdentity == nil ? metadata?.provider : .gog,
                    storeExternalID: gogIdentity?.externalID ?? metadata?.externalID,
                    storeMetadataOnly: metadata == nil && gogIdentity == nil ? nil : true,
                    communityCompatibility: communityProfile
                )
                environments.append(environment)
                applications.append(app)
                if var metadata {
                    metadata.isInstalled = false
                    metadata.installPath = nil
                    metadata.installedPlatform = nil
                    upsertImportedPresentationMetadata(metadata)
                }
                if let gogIdentity, let appIndex = applications.indices.last {
                    adoptGOGInstallationIdentity(gogIdentity, forApplicationAt: appIndex)
                }
                await refreshAuxiliaryExecutables(for: app.id)
                await updateInstallation(.committing)
                save()
                installation.completedStages = [.preparingRuntime, .creatingEnvironment, .committing]
                installation.state = .succeeded(app.id)
                SoundService.shared.play(.installationCompleted)
                installationTask = nil
                await refreshRuntimeStatuses()
                return app.id
            } catch is CancellationError {
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                installation = InstallationProgress(state: .cancelled)
                installationTask = nil
                return nil
            } catch {
                let diagnostics = await preserveDiagnosticsAndRemoveFailedEnvironment(createdEnvironment)
                installation.state = .failed
                installation.failureMessage = diagnostics?.technicalDetails(for: error) ?? error.localizedDescription
                installation.rollbackCompleted = createdEnvironment != nil
                SoundService.shared.play(.error)
                installationTask = nil
                return nil
            }
        }
        installationTask = task
    }

    func registerExistingGame(_ game: StoreLibraryGame, at selectedURL: URL) {
        let selected = selectedURL.standardizedFileURL
        let key = storeOperationKey(for: game)
        guard storeGameOperations[key] == nil else { return }

        if selected.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            guard preferredStoreInstallationPlatform(for: game) == .nativeMacOS,
                  FileManager.default.fileExists(atPath: selected.path) else {
                presentedIssue = BorealIssue(
                    title: "This installation couldn’t be added",
                    stage: "Validating the selected native macOS game.",
                    recovery: game.provider == .epic
                        ? "Epic games are prepared through Boreal’s managed Windows environment. Choose the game’s main Windows .exe file."
                        : "Choose the installed game’s .app bundle.",
                    technicalDetails: selected.path
                )
                return
            }
            guard let index = storeGames.firstIndex(where: { $0.id == game.id }) else { return }
            storeGames[index].isInstalled = true
            storeGames[index].installPath = selected.path
            storeGames[index].installedPlatform = .nativeMacOS
            storeGames[index].storageBytes = GameStorage.allocatedSize(of: selected)
            recordInstallation(for: game, location: selected, platform: .nativeMacOS)
            save()
            SoundService.shared.play(.installationCompleted)
            return
        }

        guard selected.pathExtension.caseInsensitiveCompare("exe") == .orderedSame,
              FileManager.default.fileExists(atPath: selected.path),
              ExecutableDiscovery.isEligibleExecutablePath(selected.lastPathComponent) else {
            presentedIssue = BorealIssue(
                title: "This installation couldn’t be added",
                stage: "Validating the selected Windows game executable.",
                recovery: "Choose the game’s main .exe file, not an installer, updater, helper, or uninstaller.",
                technicalDetails: selected.path
            )
            return
        }

        let token = UUID()
        storeOperationTokens[key] = token
        SoundService.shared.play(.installationStarted)
        storeGameOperations[key] = .preparingEnvironment(StoreGameOperationProgress(
            message: "Preparing the existing installation…",
            fractionCompleted: 0
        ))
        let task = Task { [weak self] in
            guard let self else { return }
            var createdEnvironment: ManagedBorealEnvironment?
            do {
                async let communityProfile = services.communityCompatibility.profile(for: game)
                updateEnvironmentPreparation("Preparing a verified Wine runtime…", fraction: 0.15, key: key, token: token)
                let gameProfile = GameGraphicsProfiles.profile(provider: game.provider, externalID: game.externalID)
                var automaticProfile = WineCompatibilityProfile.default
                if let enforcedBackend = gameProfile?.enforcedBackend {
                    automaticProfile.graphicsBackend = enforcedBackend
                }
                let analysis = ExecutableCompatibilityAnalyzer.analyze(
                    root: selected.deletingLastPathComponent(),
                    applicationName: game.name,
                    knownPrimary: selected
                )
                guard let primary = analysis.gameExecutable else {
                    throw CompatibilityPreparationError.noGameExecutable(selected.deletingLastPathComponent())
                }
                let directXAPI = CompatibilityPreparationResolver.directXAPI(
                    executable: primary.url,
                    userProfile: automaticProfile,
                    gameProfile: gameProfile
                )
                let runtime = try await services.runtimeManager.prepareReadyRuntime(for: RuntimeSelectionRequest(
                    architectures: analysis.requiredArchitectures.isEmpty
                        ? [WindowsExecutableArchitecture.inspect(selected)]
                        : analysis.requiredArchitectures,
                    requestedBackend: automaticProfile.graphicsBackend,
                    directXAPI: directXAPI,
                    gameProfile: gameProfile,
                    requiredEngine: GameRuntimeProfiles.requiredEngine(for: game) ?? recommendedRuntimeEngine(for: game),
                    runtimeIDOverride: automaticProfile.runtimeIDOverride
                ))
                let resolved = try CompatibilityPreparationResolver.resolve(
                    analysis: analysis,
                    userProfile: automaticProfile,
                    gameProfile: gameProfile,
                    runtime: runtime
                )
                automaticProfile.graphicsAPI = resolved.directXAPI
                automaticProfile.graphicsBackend = resolved.graphicsStack.backend
                automaticProfile.prefixMode = resolved.prefixMode
                automaticProfile.architecture = resolved.executableArchitecture == .x86 ? .win32 : .win64
                automaticProfile.requiredDependencies = Set(resolved.dependencies)
                try Task.checkCancellation()
                updateEnvironmentPreparation("Creating an isolated Windows environment…", fraction: 0.4, key: key, token: token)
                var managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: game.name, profile: automaticProfile),
                    runtime: runtime
                )
                createdEnvironment = managed
                try await services.environmentManager.initialize(managed, runtime: runtime)
                managed.state = .ready
                try Task.checkCancellation()
                guard storeOperationTokens[key] == token else { throw CancellationError() }

                let environment = WindowsEnvironment(
                    id: managed.id,
                    name: game.name,
                    runtime: runtime.runtimeDescription,
                    graphics: resolved.graphicsStack.backend.displayName,
                    runtimeID: runtime.id,
                    rootPath: managed.rootURL.path,
                    prefixPath: managed.prefixURL.path,
                    logsPath: managed.logsURL.path
                )
                let loadedCompatibility = await communityProfile
                let compatibility = game.compatibility ?? loadedCompatibility
                let app = WindowsApplication(
                    name: game.name,
                    publisher: game.developer ?? game.provider.rawValue,
                    executablePath: selected.path,
                    installerPath: "existing-installation",
                    environmentID: managed.id,
                    compatibility: compatibility?.tier.rating ?? .unknown,
                    graphics: resolved.graphicsStack.backend.displayName,
                    storageBytes: GameStorage.allocatedSize(of: selected.deletingLastPathComponent()) ?? 0,
                    iconSymbol: "gamecontroller.fill",
                    lastResult: "Existing installation added",
                    storeProvider: game.provider,
                    storeExternalID: game.externalID,
                    communityCompatibility: compatibility
                )
                environments.append(environment)
                applications.append(app)
                await refreshAuxiliaryExecutables(for: app.id)
                if let index = storeGames.firstIndex(where: { $0.id == game.id }) {
                    storeGames[index].isInstalled = true
                    storeGames[index].installPath = selected.deletingLastPathComponent().path
                    storeGames[index].installedPlatform = .windows
                    storeGames[index].storageBytes = app.storageBytes
                    recordInstallation(
                        for: game,
                        location: selected.deletingLastPathComponent(),
                        platform: .windows,
                        environmentID: managed.id,
                        executable: selected
                    )
                    if storeGames[index].compatibility == nil { storeGames[index].compatibility = compatibility }
                }
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
                SoundService.shared.play(.installationCompleted)
            } catch is CancellationError {
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                let diagnostics = await preserveDiagnosticsAndRemoveFailedEnvironment(createdEnvironment)
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(SecretRedactor.redact(error.localizedDescription))
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                present(
                    error,
                    title: "\(game.name) couldn’t be added",
                    stage: "Preparing the existing Windows installation",
                    diagnostics: diagnostics
                )
            }
        }
        storeOperationTasks[key] = task
    }

    private func startStoreGameInstallation(
        _ game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform
    ) {
        let key = storeOperationKey(for: game)
        guard [.epic, .gog].contains(game.provider), storeGameOperations[key] == nil else { return }
        guard Self.gameInstallationDestinationIsAvailable(destinationRoot) else {
            presentedIssue = BorealIssue(
                title: "The game location is unavailable",
                stage: "Preparing the installation destination.",
                recovery: "Connect the selected disk or choose another game installation location in Settings → Storage.",
                technicalDetails: destinationRoot.path
            )
            return
        }
        let token = UUID()
        let previousRecord = storeDownloadRecords[key]
        var initialProgress = initialDownloadProgress(
            message: "Preparing \(game.provider.rawValue) download…",
            game: game
        )
        if let startedAt = previousRecord?.lastProgress?.startedAt {
            initialProgress.startedAt = startedAt
        }
        storeOperationTokens[key] = token
        SoundService.shared.play(.installationStarted)
        storeGameOperations[key] = .installing(initialProgress)
        let operationID = previousRecord?.operationID ?? UUID()
        storeDownloadRecords[key] = StoreDownloadRecord(
            provider: game.provider,
            externalID: game.externalID,
            destinationRootPath: destinationRoot.path,
            platform: platform,
            status: .downloading,
            lastProgress: initialProgress,
            samples: previousRecord?.samples,
            operationID: operationID,
            kind: .install,
            providerBuildID: game.sizeEstimate?.buildID,
            helperVersionUsed: helperVersion(for: game.provider),
            startedAt: previousRecord?.startedAt ?? .now
        )
        markInstallationInstalling(for: game, destinationRoot: destinationRoot, platform: platform)
        save()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let update: @Sendable (StoreGameOperationProgress) async -> Void = { [weak self] progress in
                    await self?.updateStoreDownload(progress, key: key, token: token)
                }
                let root = destinationRoot
                let installationURL = try await services.installationService.install(
                    game,
                    destinationRoot: root,
                    platform: platform,
                    providerRegistry: services.storeProviders,
                    progress: update
                )
                try Task.checkCancellation()
                guard storeOperationTokens[key] == token else { return }
                guard let installationURL else {
                    throw GameStoreProviderError.installationMissing(game.provider)
                }
                guard let index = storeGames.firstIndex(where: { $0.id == game.id }) else {
                    throw GameStoreProviderError.installationMissing(game.provider)
                }
                storeGames[index].isInstalled = true
                storeGames[index].installPath = installationURL.path
                storeGames[index].installedPlatform = platform
                storeGames[index].storageBytes = GameStorage.allocatedSize(of: installationURL)
                recordInstallation(for: game, location: installationURL, platform: platform)
                save()
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                storeDownloadRecords[key] = nil
                lastDownloadRecordSave[key] = nil
                save()
                SoundService.shared.play(.downloadCompleted)
                syncLibrary(game.provider)
            } catch is CancellationError {
                markInstallationFailed(for: game)
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                guard storeOperationTokens[key] == token else { return }
                markInstallationFailed(for: game)
                storeGameOperations[key] = .failed(SecretRedactor.redact(error.localizedDescription))
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                if var record = storeDownloadRecords[key] {
                    record.status = .failed
                    record.lastError = SecretRedactor.redact(error.localizedDescription)
                    record.updatedAt = .now
                    storeDownloadRecords[key] = record
                    save()
                }
                let platformName = platform == .nativeMacOS ? "native macOS" : "Windows"
                present(error, title: "\(game.name) couldn’t be installed", stage: "Downloading the \(platformName) build from \(game.provider.rawValue)")
            }
        }
        storeOperationTasks[key] = task
    }

    func storeGameOperation(for game: StoreLibraryGame) -> StoreGameOperationState? {
        storeGameOperations[storeOperationKey(for: game)]
    }

    func canResumeStoreGameOperation(_ game: StoreLibraryGame) -> Bool {
        storeDownloadRecords[storeOperationKey(for: game)] != nil
            && storeOperationTasks[storeOperationKey(for: game)] == nil
    }

    func storeDownloadRecord(for game: StoreLibraryGame) -> StoreDownloadRecord? {
        storeDownloadRecords[storeOperationKey(for: game)]
    }

    func storeOperation(for game: StoreLibraryGame) -> StoreOperation? {
        storeDownloadRecords[storeOperationKey(for: game)]?.operation
    }

    func resumeStoreGameOperation(_ game: StoreLibraryGame) {
        let key = storeOperationKey(for: game)
        guard let record = storeDownloadRecords[key], storeOperationTasks[key] == nil else { return }
        storeGameOperations[key] = nil
        startStoreGameInstallation(
            game,
            destinationRoot: URL(fileURLWithPath: record.destinationRootPath, isDirectory: true),
            platform: record.platform
        )
    }

    func loadCommunityCompatibility(for gameID: UUID) async {
        guard let game = storeGame(id: gameID), game.compatibility == nil else { return }
        guard game.supportsNativeMacOS != true,
              let profile = await services.communityCompatibility.profile(for: game),
              let index = storeGames.firstIndex(where: { $0.id == gameID }),
              storeGames[index].compatibility == nil else { return }
        storeGames[index].compatibility = profile
        if let appIndex = applications.firstIndex(where: {
            $0.storeProvider == game.provider && $0.storeExternalID == game.externalID && $0.compatibility == .unknown
        }) {
            applications[appIndex].compatibility = profile.tier.rating
            applications[appIndex].communityCompatibility = profile
        }
        save()
    }

    private func enrichCompatibility(in games: [StoreLibraryGame]) async -> [StoreLibraryGame] {
        var result = games
        let candidates = games.indices.filter {
            games[$0].compatibility == nil && games[$0].supportsNativeMacOS != true
        }
        for start in stride(from: 0, to: candidates.count, by: 3) {
            let indices = Array(candidates[start..<min(start + 3, candidates.count)])
            let loaded = await withTaskGroup(of: (Int, CommunityCompatibility?).self) { group in
                for index in indices {
                    let game = games[index]
                    group.addTask { [services] in
                        (index, await services.communityCompatibility.profile(for: game))
                    }
                }
                var values: [(Int, CommunityCompatibility?)] = []
                for await value in group { values.append(value) }
                return values
            }
            for (index, profile) in loaded where profile != nil { result[index].compatibility = profile }
        }
        return result
    }

    var activeStoreGameOperations: [(game: StoreLibraryGame, state: StoreGameOperationState)] {
        storeGames.compactMap { game in
            storeGameOperation(for: game).map { (game, $0) }
        }
    }

    var hasResumableStoreGameOperations: Bool {
        activeStoreGameOperations.contains { $0.state.isResumable || canResumeStoreGameOperation($0.game) }
    }

    var hasPausableStoreGameOperations: Bool {
        activeStoreGameOperations.contains { $0.state.isCancellable }
    }

    func resumeAllStoreGameOperations() {
        for operation in activeStoreGameOperations where operation.state.isResumable || canResumeStoreGameOperation(operation.game) {
            resumeStoreGameOperation(operation.game)
        }
    }

    func pauseAllStoreGameOperations() {
        for operation in activeStoreGameOperations where operation.state.isCancellable {
            cancelStoreGameOperation(operation.game)
        }
    }

    func clearStoreGameOperation(for game: StoreLibraryGame) {
        let key = storeOperationKey(for: game)
        storeGameOperations[key] = nil
        storeOperationTokens[key] = nil
        storeDownloadRecords[key] = nil
        lastDownloadRecordSave[key] = nil
        save()
    }

    func cancelStoreGameOperation(_ game: StoreLibraryGame) {
        let key = storeOperationKey(for: game)
        let progress = storeGameOperations[key]?.progress ?? storeDownloadRecords[key]?.lastProgress
            ?? StoreGameOperationProgress(message: "Download paused", fractionCompleted: nil)
        storeOperationTasks[key]?.cancel()
        storeOperationTasks[key] = nil
        storeOperationTokens[key] = nil
        if var record = storeDownloadRecords[key] {
            record.status = .paused
            record.lastProgress = progress
            record.lastError = nil
            record.updatedAt = .now
            storeDownloadRecords[key] = record
            storeGameOperations[key] = .paused(progress, reason: "Paused. Downloaded files were kept and can be resumed.")
            save()
        } else {
            storeGameOperations[key] = nil
        }
    }

    func prepareEpicGame(_ game: StoreLibraryGame) {
        prepareStoreGame(game)
    }

    func supportsStoreGameUpdate(_ game: StoreLibraryGame) -> Bool {
        services.storeProviders.capabilities(for: game.provider).contains(.update)
    }

    func supportsStoreGameVerification(_ game: StoreLibraryGame) -> Bool {
        services.storeProviders.capabilities(for: game.provider).contains(.verify)
    }

    func updateStoreGame(_ game: StoreLibraryGame) {
        startStoreGameMaintenance(game, action: .update)
    }

    func verifyStoreGame(_ game: StoreLibraryGame) {
        startStoreGameMaintenance(game, action: .verify)
    }

    private enum StoreGameMaintenanceAction: Equatable {
        case update
        case verify

        var capability: GameStoreProviderCapabilities { self == .update ? .update : .verify }
        var initialMessage: String { self == .update ? "Checking for updates…" : "Preparing file verification…" }
        var title: String { self == .update ? "updated" : "verified" }
        var phase: StoreGameOperationPhase { self == .update ? .preparing : .verifying }
    }

    private func startStoreGameMaintenance(_ game: StoreLibraryGame, action: StoreGameMaintenanceAction) {
        let key = storeOperationKey(for: game)
        let capabilities = services.storeProviders.capabilities(for: game.provider)
        guard isInstalled(game),
              game.resolvedEntitlementState.isUsable,
              capabilities.contains(action.capability),
              storeGameOperations[key] == nil else { return }
        let providerGame = canonicalStoreGame(game)
        let token = UUID()
        storeOperationTokens[key] = token
        storeGameOperations[key] = .installing(StoreGameOperationProgress(
            message: action.initialMessage,
            fractionCompleted: nil,
            phase: action.phase
        ))
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let update: @Sendable (StoreGameOperationProgress) async -> Void = { [weak self] progress in
                    await self?.updateMaintenanceProgress(progress, key: key, token: token)
                }
                switch action {
                case .update:
                    try await services.installationService.update(
                        providerGame,
                        providerRegistry: services.storeProviders,
                        progress: update
                    )
                case .verify:
                    try await services.installationService.verify(
                        providerGame,
                        providerRegistry: services.storeProviders,
                        progress: update
                    )
                }
                try Task.checkCancellation()
                guard storeOperationTokens[key] == token else { return }
                if let installationIndex = installations.firstIndex(where: {
                    $0.gameID == game.id || $0.storeReference == game.storeReference
                }) {
                    installations[installationIndex].lastSeenAt = .now
                    if action == .verify { installations[installationIndex].lastVerifiedAt = .now }
                    installations[installationIndex].updatedAt = .now
                }
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
                syncLibrary(game.provider)
            } catch is CancellationError {
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(SecretRedactor.redact(error.localizedDescription))
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                present(error, title: "\(game.name) couldn’t be \(action.title)", stage: action.initialMessage)
            }
        }
        storeOperationTasks[key] = task
    }

    private func updateMaintenanceProgress(_ progress: StoreGameOperationProgress, key: String, token: UUID) {
        guard storeOperationTokens[key] == token else { return }
        storeGameOperations[key] = .installing(progress)
    }

    func uninstallStoreGame(_ game: StoreLibraryGame) {
        let key = storeOperationKey(for: game)
        guard [.epic, .gog].contains(game.provider),
              hasInstallation(game),
              storeGameOperations[key] == nil else { return }
        let providerGame = canonicalStoreGame(game)
        let token = UUID()
        storeOperationTokens[key] = token
        storeGameOperations[key] = .preparingEnvironment(StoreGameOperationProgress(
            message: "Uninstalling \(game.name)…",
            fractionCompleted: nil
        ))
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                if let app = linkedApplication(for: game) {
                    await removeApplicationAndEnvironment(app.id)
                    guard application(id: app.id) == nil else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                try Task.checkCancellation()
                try await services.installationService.uninstall(
                    providerGame,
                    providerRegistry: services.storeProviders
                )
                guard storeOperationTokens[key] == token else { return }
                if let index = storeGames.firstIndex(where: { $0.id == game.id }) {
                    storeGames[index].isInstalled = false
                    storeGames[index].installPath = nil
                    storeGames[index].installedPlatform = nil
                    storeGames[index].storageBytes = nil
                }
                markInstallationUninstalled(for: game)
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
                syncLibrary(game.provider)
            } catch is CancellationError {
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(SecretRedactor.redact(error.localizedDescription))
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                present(error, title: "\(game.name) couldn’t be uninstalled", stage: "Removing the installed game and its Boreal environment")
            }
        }
        storeOperationTasks[key] = task
    }

    func prepareStoreGame(_ game: StoreLibraryGame, runtimeEngine: RuntimeEngine? = nil) {
        let key = storeOperationKey(for: game)
        guard [.epic, .gog].contains(game.provider),
              game.resolvedEntitlementState.isUsable,
              usesManagedRuntime(for: game),
              isInstalled(game),
              linkedApplication(for: game) == nil,
              storeGameOperations[key] == nil else { return }
        let providerGame = canonicalStoreGame(game)
        let token = UUID()
        let selectedEngine = runtimeEngine ?? recommendedRuntimeEngine(for: game)
        storeOperationTokens[key] = token
        setPreparationState(for: game, to: .preparing)
        storeGameOperations[key] = .preparingEnvironment(StoreGameOperationProgress(
            message: "Finding a compatible \(selectedEngine.displayName) runtime…",
            fractionCompleted: 0
        ))
        let task = Task { [weak self] in
            guard let self else { return }
            var createdEnvironment: ManagedBorealEnvironment?
            do {
                async let communityProfile = services.communityCompatibility.profile(for: game)
                updateEnvironmentPreparation("Preparing a verified \(selectedEngine.displayName) runtime…", fraction: 0.1, key: key, token: token)
                updateEnvironmentPreparation("Analyzing game executables…", fraction: 0.08, key: key, token: token)
                guard let installationRoot = installedLocation(for: game) else {
                    throw CompatibilityPreparationError.noGameExecutable(installedLocation(for: game) ?? URL(fileURLWithPath: "."))
                }
                let gameProfile = GameGraphicsProfiles.profile(provider: game.provider, externalID: game.externalID)
                var automaticProfile = WineCompatibilityProfile.default
                if let enforcedBackend = gameProfile?.enforcedBackend {
                    automaticProfile.graphicsBackend = enforcedBackend
                }
                let analysis = ExecutableCompatibilityAnalyzer.analyze(
                    root: installationRoot,
                    applicationName: game.name
                )
                guard let primary = analysis.gameExecutable else {
                    throw CompatibilityPreparationError.noGameExecutable(installationRoot)
                }
                let directXAPI = CompatibilityPreparationResolver.directXAPI(
                    executable: primary.url,
                    userProfile: automaticProfile,
                    gameProfile: gameProfile
                )
                let request = RuntimeSelectionRequest(
                    architectures: analysis.requiredArchitectures.isEmpty ? [.unknown] : analysis.requiredArchitectures,
                    prefixMode: automaticProfile.prefixMode,
                    requestedBackend: automaticProfile.graphicsBackend,
                    directXAPI: directXAPI,
                    gameProfile: gameProfile,
                    requiredEngine: GameRuntimeProfiles.requiredEngine(provider: game.provider, externalID: game.externalID) ?? selectedEngine,
                    runtimeIDOverride: automaticProfile.runtimeIDOverride
                )
                let runtime = try await services.runtimeManager.prepareReadyRuntime(for: request)
                try Task.checkCancellation()
                updateEnvironmentPreparation("Creating an isolated Windows environment…", fraction: 0.25, key: key, token: token)
                let resolved = try CompatibilityPreparationResolver.resolve(
                    analysis: analysis,
                    userProfile: automaticProfile,
                    gameProfile: gameProfile,
                    runtime: runtime
                )
                automaticProfile.graphicsAPI = resolved.directXAPI
                automaticProfile.graphicsBackend = resolved.graphicsStack.backend
                automaticProfile.prefixMode = resolved.prefixMode
                automaticProfile.architecture = resolved.executableArchitecture == .x86 ? .win32 : .win64
                automaticProfile.requiredDependencies = Set(resolved.dependencies)
                var configuration = EnvironmentConfiguration(name: game.name, profile: automaticProfile)
                configuration.requiredDependencies = Set(resolved.dependencies)
                var managed = try await services.environmentManager.create(configuration: configuration, runtime: runtime)
                createdEnvironment = managed
                try Task.checkCancellation()
                updateEnvironmentPreparation("Preparing compatibility…", fraction: 0.5, key: key, token: token)
                try await services.environmentManager.initialize(managed, runtime: runtime)
                managed.state = .ready
                try Task.checkCancellation()
                updateEnvironmentPreparation("Validating compatibility…", fraction: 0.75, key: key, token: token)
                let plan = try await services.launchCoordinator.makeStoreLaunchPlan(
                    for: providerGame,
                    runtime: runtime,
                    environment: managed,
                    providerRegistry: services.storeProviders
                )
                let environment = WindowsEnvironment(
                    id: managed.id,
                    name: game.name,
                    runtime: runtime.runtimeDescription,
                    graphics: resolved.graphicsStack.backend.displayName,
                    runtimeID: runtime.id,
                    rootPath: managed.rootURL.path,
                    prefixPath: managed.prefixURL.path,
                    logsPath: managed.logsURL.path
                )
                let loadedCommunityProfile = await communityProfile
                let resolvedCompatibility = game.compatibility ?? loadedCommunityProfile
                let app = WindowsApplication(
                    name: game.name,
                    publisher: game.developer ?? game.provider.rawValue,
                    executablePath: plan.executable.path,
                    installerPath: installedLocation(for: game)?.path ?? "",
                    environmentID: managed.id,
                    status: .ready,
                    compatibility: resolvedCompatibility?.tier.rating ?? .unknown,
                    graphics: resolved.graphicsStack.backend.displayName,
                    iconSymbol: "gamecontroller.fill",
                    lastResult: "Compatibility prepared; ready to play through \(game.provider.rawValue)",
                    storeProvider: game.provider,
                    storeExternalID: game.externalID,
                    communityCompatibility: resolvedCompatibility
                )
                environments.append(environment)
                applications.append(app)
                lastLaunchPlans[app.id] = await makeLaunchPlan(
                    plan,
                    applicationID: app.id,
                    provider: game.provider,
                    externalID: game.externalID,
                    environment: managed,
                    runtime: runtime,
                    profile: automaticProfile
                )
                await refreshAuxiliaryExecutables(for: app.id)
                if let resolvedCompatibility,
                   let gameIndex = storeGames.firstIndex(where: { $0.id == game.id }),
                    storeGames[gameIndex].compatibility == nil {
                    storeGames[gameIndex].compatibility = resolvedCompatibility
                }
                setPreparationState(for: game, to: .ready, runtime: runtime)
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
                SoundService.shared.play(.installationCompleted)
            } catch is CancellationError {
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                setPreparationState(for: game, to: .notPrepared)
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                let diagnostics = await preserveDiagnosticsAndRemoveFailedEnvironment(createdEnvironment)
                guard storeOperationTokens[key] == token else { return }
                setPreparationState(for: game, to: .needsRepair)
                storeGameOperations[key] = .failed(SecretRedactor.redact(error.localizedDescription))
                storeOperationTasks[key] = nil
                present(
                    error,
                    title: "\(game.name) couldn’t be prepared",
                    stage: "Creating its isolated Windows environment",
                    diagnostics: diagnostics
                )
            }
        }
        storeOperationTasks[key] = task
    }

    func recreateEnvironment(_ applicationID: UUID, with engine: RuntimeEngine, launchWhenReady: Bool = false, rollbackProfile: WineCompatibilityProfile? = nil) {
        guard let appIndex = applications.firstIndex(where: { $0.id == applicationID }),
              !applications[appIndex].status.isBusy,
              applications[appIndex].status != .running,
              let provider = applications[appIndex].storeProvider,
              let externalID = applications[appIndex].storeExternalID,
              [.epic, .gog].contains(provider),
              let game = storeGames.first(where: { $0.provider == provider && $0.externalID == externalID }) else { return }

        let providerGame = canonicalStoreGame(game)
        let key = storeOperationKey(for: game)
        guard storeGameOperations[key] == nil else { return }
        let token = UUID()
        let oldEnvironmentID = applications[appIndex].environmentID
        let currentExecutable = URL(fileURLWithPath: applications[appIndex].executablePath)
        let previousStatus = applications[appIndex].status
        storeOperationTokens[key] = token
        applications[appIndex].status = .preparing
        applications[appIndex].lastResult = "Recreating environment with \(engine.displayName)"
        applications[appIndex].lastErrorDetail = nil
        storeGameOperations[key] = .preparingEnvironment(StoreGameOperationProgress(
            message: "Preparing \(engine.displayName)…",
            fractionCompleted: 0
        ))
        save()

        let task = Task { [weak self] in
            guard let self else { return }
            var replacement: ManagedBorealEnvironment?
            do {
                updateEnvironmentPreparation("Validating \(engine.displayName)…", fraction: 0.1, key: key, token: token)
                let compatibilityProfile = applications[appIndex].resolvedCompatibilityProfile
                let currentArchitecture = WindowsExecutableArchitecture.inspect(currentExecutable)
                let runtime = try await prepareRuntime(
                    supporting: compatibilityProfile.graphicsBackend,
                    preferredEngine: engine,
                    executableArchitecture: currentArchitecture,
                    prefixMode: compatibilityProfile.prefixMode
                )
                try validatePrefixSelection(compatibilityProfile, executableArchitecture: currentArchitecture, runtime: runtime)
                try Task.checkCancellation()
                updateEnvironmentPreparation("Creating a new isolated prefix…", fraction: 0.3, key: key, token: token)
                var managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: game.name, profile: applications[appIndex].resolvedCompatibilityProfile),
                    runtime: runtime
                )
                replacement = managed
                try await services.environmentManager.initialize(managed, runtime: runtime)
                managed.state = .ready
                try Task.checkCancellation()
                updateEnvironmentPreparation("Validating the game launch plan…", fraction: 0.75, key: key, token: token)

                let plan = try await services.launchCoordinator.makeStoreLaunchPlan(
                    for: providerGame,
                    runtime: runtime,
                    environment: managed,
                    providerRegistry: services.storeProviders
                )
                guard FileManager.default.fileExists(atPath: plan.executable.path) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let launchArchitecture = WindowsExecutableArchitecture.inspect(plan.executable)
                try validatePrefixSelection(compatibilityProfile, executableArchitecture: launchArchitecture, runtime: runtime)
                let validation = try await services.environmentManager.validate(managed)
                guard validation.isReady else { throw EnvironmentManagerError.validationFailed(validation) }
                guard storeOperationTokens[key] == token,
                      let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) else {
                    throw CancellationError()
                }

                environments.append(WindowsEnvironment(
                    id: managed.id,
                    name: game.name,
                    windowsVersion: applications[currentIndex].resolvedCompatibilityProfile.windowsVersion.displayName,
                    architecture: managed.configuration.architecture == WinePrefixArchitecture.win64.rawValue ? "64-bit" : "32-bit",
                    runtime: runtime.runtimeDescription,
                    graphics: applications[currentIndex].resolvedCompatibilityProfile.graphicsBackend == .automatic ? runtime.graphicsName : applications[currentIndex].resolvedCompatibilityProfile.graphicsBackend.displayName,
                    runtimeID: runtime.id,
                    rootPath: managed.rootURL.path,
                    prefixPath: managed.prefixURL.path,
                    logsPath: managed.logsURL.path
                ))
                applications[currentIndex].environmentID = managed.id
                applications[currentIndex].compatibilityProfile?.architecture = managed.configuration.architecture == WinePrefixArchitecture.win64.rawValue ? .win64 : .win32
                applications[currentIndex].executablePath = plan.executable.path
                applications[currentIndex].graphics = compatibilityProfile.graphicsBackend == .automatic
                    ? runtime.graphicsName
                    : compatibilityProfile.graphicsBackend.displayName
                applications[currentIndex].status = .ready
                applications[currentIndex].lastResult = "Environment recreated with \(engine.displayName)"
                applications[currentIndex].lastExitCode = nil
                applications[currentIndex].lastFailureStage = nil
                applications[currentIndex].lastErrorDetail = nil
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()

                if launchWhenReady {
                    await toggleRunningAsync(applicationID)
                }

                if applications.allSatisfy({ $0.environmentID != oldEnvironmentID }),
                   let oldRecord = environment(id: oldEnvironmentID),
                   let oldManaged = managedEnvironment(from: oldRecord) {
                    do {
                        try await services.environmentManager.remove(oldManaged)
                        environments.removeAll { $0.id == oldEnvironmentID }
                        save()
                    } catch {
                        present(error, title: "The previous environment couldn’t be removed", stage: "Cleaning up after the successful runtime migration")
                    }
                }
            } catch is CancellationError {
                if let replacement { try? await services.environmentManager.remove(replacement) }
                if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                    if let rollbackProfile {
                        applications[currentIndex].compatibilityProfile = rollbackProfile
                        applications[currentIndex].windowsVersion = rollbackProfile.windowsVersion.displayName
                        applications[currentIndex].graphics = rollbackProfile.graphicsBackend.displayName
                    }
                    applications[currentIndex].status = previousStatus
                    applications[currentIndex].lastResult = "Environment migration cancelled"
                }
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                let diagnostics = await preserveDiagnosticsAndRemoveFailedEnvironment(replacement)
                guard storeOperationTokens[key] == token else { return }
                if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                    if let rollbackProfile {
                        applications[currentIndex].compatibilityProfile = rollbackProfile
                        applications[currentIndex].windowsVersion = rollbackProfile.windowsVersion.displayName
                        applications[currentIndex].graphics = rollbackProfile.graphicsBackend.displayName
                    }
                    applications[currentIndex].status = previousStatus
                    applications[currentIndex].lastResult = "Environment migration failed"
                    applications[currentIndex].lastFailureStage = "Recreating environment"
                    applications[currentIndex].lastErrorDetail = SecretRedactor.redact(error.localizedDescription)
                }
                storeGameOperations[key] = .failed(SecretRedactor.redact(error.localizedDescription))
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
                present(
                    error,
                    title: "\(game.name) couldn’t switch runtime",
                    stage: "Creating and validating a new \(engine.displayName) environment",
                    diagnostics: diagnostics
                )
            }
        }
        storeOperationTasks[key] = task
    }

    private func prepareRuntime(
        supporting backend: WineGraphicsBackend,
        preferredEngine: RuntimeEngine,
        executableArchitecture: WindowsExecutableArchitecture? = nil,
        prefixMode: WinePrefixMode? = nil,
        runtimeIDOverride: String? = nil
    ) async throws -> InstalledRuntime {
        let installed = try await services.runtimeManager.installedRuntimes()
        if let runtime = installed.first(where: {
            if let runtimeIDOverride, $0.id != runtimeIDOverride { return false }
            guard $0.resolvedEngine == preferredEngine else { return false }
            let capabilities = $0.features?.resolvedArchitectureCapabilities ?? .unknown
            if prefixMode == nil, executableArchitecture == .x86, !capabilities.canRunX86 { return false }
            if let prefixMode {
                let unsupported: Bool = switch prefixMode {
                case .wow64:
                    !capabilities.usesNewWoW64
                case .legacyWin32:
                    !capabilities.supportsLegacyWin32Prefix
                case .legacyWin64:
                    !capabilities.canRunX86_64 || capabilities.usesNewWoW64
                }
                if unsupported { return false }
            }
            switch backend {
            case .d3dMetal: return $0.features?.d3dmetal == true
            case .dxmt: return $0.features?.dxmt == true
            case .dxvk: return $0.features?.dxvk == true
            case .vkd3d: return $0.features?.vkd3d == true
            case .automatic, .wineD3D: return true
            }
        }) {
            return runtime
        }
        guard backend == .automatic || backend == .wineD3D else {
            throw InstallerServiceError.noRuntimeAvailable
        }
        if prefixMode != nil, prefixMode != .wow64 {
            throw InstallerServiceError.noRuntimeAvailable
        }
        if runtimeIDOverride != nil {
            throw RuntimeManagerError.noCompatibleRuntime("The selected runtime is not installed or does not satisfy this game's architecture and graphics requirements.")
        }
        return try await services.runtimeManager.prepareReadyRuntime(
            preferredEngine: preferredEngine,
            executableArchitecture: executableArchitecture
        )
    }

    private func validatePrefixSelection(
        _ profile: WineCompatibilityProfile,
        executableArchitecture: WindowsExecutableArchitecture,
        runtime: InstalledRuntime
    ) throws {
        if executableArchitecture == .x86_64, profile.architecture == .win32 {
            throw RuntimeManagerError.incompatible64BitExecutable
        }
        let capabilities = runtime.features?.resolvedArchitectureCapabilities ?? .unknown
        if executableArchitecture == .x86,
           profile.architecture == .win64,
           !capabilities.usesNewWoW64 {
            throw RuntimeManagerError.incompatible32BitExecutable(runtime: runtime.displayName)
        }
        let mode = WinePrefixMode.resolve(
            requestedMode: profile.prefixMode,
            requestedArchitecture: profile.architecture.rawValue,
            runtimeSupportsWoW64: capabilities.usesNewWoW64
        )
        if executableArchitecture == .x86_64, mode == .legacyWin32 {
            throw RuntimeManagerError.incompatible64BitExecutable
        }
        let supportsMode: Bool = switch mode {
        case .wow64:
            capabilities.usesNewWoW64
        case .legacyWin32:
            capabilities.supportsLegacyWin32Prefix
        case .legacyWin64:
            capabilities.canRunX86_64 && !capabilities.usesNewWoW64
        }
        if !supportsMode {
            throw EnvironmentManagerError.unsupportedPrefixMode(mode: mode, runtime: runtime.displayName)
        }
    }

    private func steamWindowsApplication(
        game: StoreLibraryGame,
        executable: URL,
        environmentID: UUID,
        status: ApplicationStatus,
        graphics: String,
        poolKey: String = "shared"
    ) -> WindowsApplication {
        WindowsApplication(
            name: game.name,
            publisher: game.developer ?? "Steam",
            executablePath: executable.path,
            installerPath: "steam-windows-game",
            environmentID: environmentID,
            status: status,
            compatibility: game.compatibility?.tier.rating ?? .unknown,
            graphics: graphics,
            lastOpened: status == .running ? .now : nil,
            iconSymbol: "gamecontroller.fill",
            lastResult: "Installed by Windows Steam; launched through steam.exe -applaunch",
            storeProvider: .steam,
            storeExternalID: game.externalID,
            communityCompatibility: game.compatibility,
            steamPoolKey: poolKey
        )
    }

    func toggleRunning(_ id: UUID) {
        Task { await toggleRunningAsync(id) }
    }

    func removeApplication(_ id: UUID) {
        Task { await removeApplicationAndEnvironment(id) }
    }

    func createEnvironment(named name: String = "New Environment") {
        Task {
            do {
                guard let runtime = try await services.runtimeManager.installedRuntimes().first,
                      try await services.runtimeManager.validate(runtime).isReady else { throw InstallerServiceError.noRuntimeAvailable }
                let managed = try await services.environmentManager.create(configuration: EnvironmentConfiguration(name: name), runtime: runtime)
                try await services.environmentManager.initialize(managed, runtime: runtime)
                environments.append(WindowsEnvironment(id: managed.id, name: name, runtime: runtime.runtimeDescription, graphics: runtime.graphicsName, runtimeID: runtime.id, rootPath: managed.rootURL.path, prefixPath: managed.prefixURL.path, logsPath: managed.logsURL.path))
                save()
            } catch { present(error, title: "Environment couldn’t be created", stage: "Preparing the Windows environment") }
        }
    }

    func removeEnvironment(_ id: UUID) {
        Task {
            guard applications(in: id).isEmpty else {
                presentedIssue = BorealIssue(title: "Environment couldn’t be removed", stage: "It still contains applications.", recovery: "Remove those applications first, then try again.", technicalDetails: "Environment ID: \(id.uuidString)")
                return
            }
            do {
                if let record = environment(id: id), let managed = managedEnvironment(from: record) { try await services.environmentManager.remove(managed) }
                environments.removeAll { $0.id == id }
                save()
            } catch { present(error, title: "Environment couldn’t be removed", stage: "Removing environment data") }
        }
    }

    func formattedBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    private func symbol(for name: String) -> String {
        let value = name.lowercased()
        if value.contains("game") || value.contains("steam") { return "gamecontroller.fill" }
        if value.contains("photo") || value.contains("paint") { return "paintbrush.pointed.fill" }
        if value.contains("note") || value.contains("text") { return "doc.text.fill" }
        return "shippingbox.fill"
    }

    private func load() {
        if usesLayeredStorage, let layered = BorealStorageLoader.loadLayered(from: storageLayout) {
            applications = layered.applications
            environments = layered.environments
            installations = layered.installations
            let persistedGames = layered.storeGames
            storeGames = persistedGames.filter { $0.provider != .gog }
                + GOGReleaseNormalizer.deduplicate(persistedGames.filter { $0.provider == .gog })
            storeDownloadRecords = layered.storeDownloads
            favoriteKeys = layered.favoriteKeys
            lastAutomaticLibraryRefreshAt = layered.lastAutomaticLibraryRefreshAt
            recoverInterruptedDownloads()
            storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            migrateStoreOperationMetadata()
            synchronizeInstallationCompatibilityBridge()
            reconcileInstallationState()
            if !storeDownloadRecords.isEmpty { save() }
            return
        }

        let sourceURL = usesLayeredStorage ? storageLayout.legacyLibraryURL : storageURL
        guard let originalData = try? Data(contentsOf: sourceURL),
              let data = Self.removingNonProtonCompatibility(from: originalData),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        applications = state.applications
        environments = state.environments
        if usesLayeredStorage {
            BorealStorageLoader.migrateLegacyEnvironments(state.environments, to: storageLayout)
        }
        let persistedGames = state.storeGames ?? []
        installations = InstallationMigration.fromLegacy(
            applications: applications,
            storeGames: persistedGames,
            layout: storageLayout
        ).map { InstallationStateResolver.resolve($0, layout: storageLayout) }
        storeGames = persistedGames.filter { $0.provider != .gog }
            + GOGReleaseNormalizer.deduplicate(persistedGames.filter { $0.provider == .gog })
        storeDownloadRecords = state.storeDownloads ?? [:]
        favoriteKeys = Set(state.favoriteKeys ?? [])
        lastAutomaticLibraryRefreshAt = state.lastAutomaticLibraryRefreshAt
        migrateStoreOperationMetadata()
        recoverInterruptedDownloads()
        storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        synchronizeInstallationCompatibilityBridge()
        reconcileInstallationState()
        if usesLayeredStorage || !storeDownloadRecords.isEmpty { save() }
    }

    /// Reconciles only the persisted installation projection. Filesystem
    /// presence changes the installation state to `.missing`; the record and
    /// its provider link are intentionally retained.
    private func reconcileInstallationState() {
        installations = installations.map { installation in
            var value = InstallationStateResolver.resolve(installation, layout: storageLayout)
            let hasPreparedApplication = applications.contains { application in
                guard !application.isSteamRuntimeHost, !application.isInstallerOnly else { return false }
                if application.id == value.gameID { return true }
                return application.storeReference == value.storeReference
            }
            // Older canonical records predate PreparationState. A linked
            // application proves that Boreal already created its environment;
            // preserve that established lifecycle instead of forcing a second
            // preparation after migration.
            if hasPreparedApplication, value.preparationState == .notPrepared {
                value.preparationState = .ready
            }
            return value
        }
        for installation in installations where installation.state.representsAnInstallation {
            guard let index = storeGames.firstIndex(where: { $0.id == installation.gameID }) else { continue }
            storeGames[index].isInstalled = true
            storeGames[index].installPath = StoragePathResolver.resolve(installation.location, layout: storageLayout).path
            storeGames[index].installedPlatform = installation.platform
            storeGames[index].storageBytes = installation.installedSize
        }
    }

    private func synchronizeInstallationCompatibilityBridge() {
        let migrated = InstallationMigration.fromLegacy(
            applications: applications,
            storeGames: storeGames,
            layout: storageLayout
        )
        var byGameID = Dictionary(uniqueKeysWithValues: installations.map { ($0.gameID, $0) })
        for legacy in migrated {
            guard let game = storeGames.first(where: { $0.id == legacy.gameID }), game.isInstalled else {
                let hasLinkedApplication = applications.contains { application in
                    guard !application.isSteamRuntimeHost, !application.isInstallerOnly else { return false }
                    return application.id == legacy.gameID
                        || (legacy.storeReference != nil && application.storeReference == legacy.storeReference)
                }
                if byGameID[legacy.gameID] == nil, hasLinkedApplication {
                    byGameID[legacy.gameID] = legacy
                }
                continue
            }
            if var current = byGameID[legacy.gameID], current.state != .uninstalled {
                current.storeReference = legacy.storeReference ?? current.storeReference
                current.displayName = legacy.displayName ?? current.displayName
                // An active provider operation owns its destination and
                // lifecycle state. Do not let the legacy compatibility fields
                // turn `.installing` into `.installed` during an intermediate
                // save.
                if current.state != .installing && current.state != .broken {
                    let locationChanged = current.location != legacy.location
                    current.location = legacy.location
                    current.platform = legacy.platform
                    current.installedSize = legacy.installedSize
                    if locationChanged || current.state == .unknown {
                        current.state = .installed
                    }
                    if !legacy.executables.isEmpty { current.executables = legacy.executables }
                }
                current.updatedAt = .now
                byGameID[legacy.gameID] = current
            } else if byGameID[legacy.gameID] == nil {
                byGameID[legacy.gameID] = legacy
            }
        }
        installations = byGameID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func recordInstallation(
        for game: StoreLibraryGame,
        location: URL,
        platform: StoreGameInstallationPlatform,
        environmentID: UUID? = nil,
        executable: URL? = nil
    ) {
        let normalizedLocation = location.standardizedFileURL
        let resolvedLocation = StoragePathResolver.location(for: normalizedLocation, layout: storageLayout)
        var current = installations.first {
            $0.gameID == game.id || $0.storeReference == game.storeReference
        } ?? GameInstallation(
            id: game.id,
            gameID: game.id,
            storeReference: game.storeReference,
            displayName: game.name,
            location: resolvedLocation,
            platform: platform
        )
        current.storeReference = game.storeReference
        current.displayName = game.name
        current.location = resolvedLocation
        current.platform = platform
        current.environmentID = environmentID ?? current.environmentID
        current.installedSize = GameStorage.allocatedSize(of: normalizedLocation) ?? game.displayedStorageBytes
        current.state = .installed
        if platform == .nativeMacOS || game.provider == .steam {
            current.preparationState = .ready
        }
        current.volumeIdentity = InstallationVolumeIdentity.capture(at: normalizedLocation, location: resolvedLocation)
        current.providerBuildID = game.sizeEstimate?.buildID ?? current.providerBuildID
        current.helperVersionUsed = helperVersion(for: game.provider)
        current.installedAt = current.installedAt ?? .now
        current.lastSeenAt = .now
        current.updatedAt = .now
        if let executable {
            let executablePath = executable.standardizedFileURL.path
            let rootPath = normalizedLocation.path.hasSuffix("/") ? normalizedLocation.path : normalizedLocation.path + "/"
            let relativePath = executablePath.hasPrefix(rootPath)
                ? String(executablePath.dropFirst(rootPath.count))
                : executable.lastPathComponent
            let architecture: ExecutableArchitecture? = switch WindowsExecutableArchitecture.inspect(executable) {
            case .x86: .x86
            case .x86_64: .x86_64
            case .unknown: nil
            }
            let value = GameExecutable(relativePath: relativePath, role: .game, architecture: architecture)
            current.executables = current.executables.filter { $0.relativePath != relativePath } + [value]
            current.selectedExecutableID = value.id
        }
        if let index = installations.firstIndex(where: { $0.gameID == current.gameID }) {
            installations[index] = current
        } else {
            installations.append(current)
        }
    }

    private func markInstallationUninstalled(for game: StoreLibraryGame) {
        guard let index = installations.firstIndex(where: {
            $0.gameID == game.id || $0.storeReference == game.storeReference
        }) else { return }
        installations[index].state = .uninstalled
        installations[index].updatedAt = .now
    }

    private func markInstallationInstalling(
        for game: StoreLibraryGame,
        destinationRoot: URL,
        platform: StoreGameInstallationPlatform
    ) {
        var current = installation(for: game) ?? GameInstallation(
            id: game.id,
            gameID: game.id,
            storeReference: game.storeReference,
            displayName: game.name,
            location: StoragePathResolver.location(for: destinationRoot, layout: storageLayout),
            platform: platform,
            state: .installing
        )
        let location = StoragePathResolver.location(for: destinationRoot, layout: storageLayout)
        current.location = location
        current.platform = platform
        current.storeReference = game.storeReference
        current.displayName = game.name
        current.state = .installing
        current.preparationState = platform == .nativeMacOS ? .ready : .notPrepared
        current.volumeIdentity = InstallationVolumeIdentity.capture(at: destinationRoot, location: location)
        current.updatedAt = .now
        if let index = installations.firstIndex(where: { $0.gameID == current.gameID }) {
            installations[index] = current
        } else {
            installations.append(current)
        }
    }

    private func markInstallationFailed(for game: StoreLibraryGame) {
        guard let index = installations.firstIndex(where: {
            $0.gameID == game.id || $0.storeReference == game.storeReference
        }), installations[index].state == .installing else { return }
        installations[index].state = .broken
        installations[index].updatedAt = .now
    }

    private func setPreparationState(
        for game: StoreLibraryGame,
        to state: GamePreparationState,
        runtime: InstalledRuntime? = nil
    ) {
        guard let index = installations.firstIndex(where: {
            $0.gameID == game.id || $0.storeReference == game.storeReference
        }) else { return }
        installations[index].preparationState = state
        if let runtime { installations[index].runtimeUsed = runtime.id }
        installations[index].updatedAt = .now
    }

    private func helperVersion(for provider: GameLibraryProvider) -> String? {
        switch provider {
        case .steam: nil
        case .epic: "Legendary 0.21.1"
        case .gog: "heroic-gogdl 1.3.0"
        }
    }

    private func recoverInterruptedDownloads() {
        for (key, record) in Array(storeDownloadRecords) {
            var recovered = record
            if recovered.status == .downloading { recovered.status = .paused }
            recovered.updatedAt = .now
            storeDownloadRecords[key] = recovered
            let progress = recovered.lastProgress
                ?? StoreGameOperationProgress(message: "Download ready to resume", fractionCompleted: nil)
            storeGameOperations[key] = .paused(
                progress,
                reason: record.status == .downloading
                    ? "Boreal closed during this download. Resume it when you are ready."
                    : (record.lastError ?? "Paused. Downloaded files were kept.")
                )
        }
    }

    /// Assigns stable identities to records written by versions that only had
    /// the provider/externalID resource key. This is deliberately a migration
    /// of persisted download records; the resource key remains the lock, while
    /// the UUID becomes the operation identity exposed to diagnostics/UI.
    private func migrateStoreOperationMetadata() {
        for key in Array(storeDownloadRecords.keys) {
            guard var record = storeDownloadRecords[key] else { continue }
            if record.operationID == nil {
                record.operationID = UUID()
            }
            if record.kind == nil {
                record.kind = .install
            }
            if record.startedAt == nil {
                record.startedAt = record.lastProgress?.startedAt ?? record.updatedAt
            }
            if record.helperVersionUsed == nil {
                record.helperVersionUsed = helperVersion(for: record.provider)
            }
            storeDownloadRecords[key] = record
        }
    }

    private nonisolated static func removingNonProtonCompatibility(from data: Data) -> Data? {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        if var games = root["storeGames"] as? [[String: Any]] {
            for index in games.indices {
                if let profile = games[index]["compatibility"] as? [String: Any],
                   profile["source"] as? String != CompatibilitySource.protonDB.rawValue {
                    games[index].removeValue(forKey: "compatibility")
                }
            }
            root["storeGames"] = games
        }
        if var apps = root["applications"] as? [[String: Any]] {
            for index in apps.indices {
                if let profile = apps[index]["communityCompatibility"] as? [String: Any],
                   profile["source"] as? String != CompatibilitySource.protonDB.rawValue {
                    apps[index].removeValue(forKey: "communityCompatibility")
                    apps[index]["compatibility"] = CompatibilityRating.unknown.rawValue
                }
            }
            root["applications"] = apps
        }
        return try? JSONSerialization.data(withJSONObject: root)
    }

    func forceQuit(_ id: UUID) {
        Task {
            do {
                guard let app = application(id: id),
                      let environmentRecord = environment(id: app.environmentID),
                      let managed = activeEnvironments[id] ?? managedEnvironment(from: environmentRecord),
                      let runtime = try await runtime(for: environmentRecord) else {
                    throw InstallerServiceError.noRuntimeAvailable
                }
                if app.usesSharedSteamGameSession {
                    guard let session = activeSessions[id]
                        ?? recoveredSessionForSharedSteam(application: app, environment: managed) else {
                        throw ProcessRunnerError.sessionNotFound(id)
                    }
                    try await services.processRunner.forceQuitProcessGroup(
                        session: session,
                        environment: managed,
                        runtime: runtime
                    )
                } else {
                    try await services.processRunner.forceQuitEnvironment(environment: managed, runtime: runtime)
                }
                requestedStops.remove(id)
                unexpectedLauncherFailures.remove(id)
                markEnvironmentEnded(appID: id, environmentSessionEnded: !app.usesSharedSteamGameSession)
            }
            catch { present(error, title: "The application couldn’t be force quit", stage: "Stopping the Windows environment") }
        }
    }

    private func auxiliarySearchRoot(for application: WindowsApplication) -> URL {
        if let provider = application.storeProvider,
           let externalID = application.storeExternalID,
           let game = storeGames.first(where: {
               $0.provider == provider && $0.externalID == externalID
           }),
           let path = installedLocation(for: game)?.path {
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        let installerURL = URL(fileURLWithPath: application.installerPath, isDirectory: true).standardizedFileURL
        var installerIsDirectory: ObjCBool = false
        if application.installerPath.hasPrefix("/"),
           FileManager.default.fileExists(atPath: installerURL.path, isDirectory: &installerIsDirectory),
           installerIsDirectory.boolValue {
            return installerURL
        }
        return URL(fileURLWithPath: application.executablePath).deletingLastPathComponent()
    }

    private func refreshAuxiliaryExecutables(for applicationID: UUID, searchRoot: URL? = nil) async {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }),
              !applications[index].isSteamRuntimeHost,
              !applications[index].isInstallerOnly else { return }
        let primary = URL(fileURLWithPath: applications[index].executablePath)
        let root = searchRoot ?? auxiliarySearchRoot(for: applications[index])
        let actions = await Task.detached {
            ExecutableDiscovery.auxiliaryExecutables(for: primary, searchRoot: root)
        }.value
        guard let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        applications[currentIndex].auxiliaryExecutables = actions
    }

    private func refreshMissingAuxiliaryExecutables() async {
        let applicationIDs = applications.filter {
            $0.auxiliaryExecutables == nil && !$0.isSteamRuntimeHost && !$0.isInstallerOnly
        }.map(\.id)
        guard !applicationIDs.isEmpty else { return }
        for applicationID in applicationIDs {
            await refreshAuxiliaryExecutables(for: applicationID)
        }
        save()
    }

    private func normalizeLauncherRedirectors() async {
        let candidates = applications.compactMap { application -> (UUID, URL, URL)? in
            guard !application.isSteamRuntimeHost, !application.isInstallerOnly else { return nil }
            let primary = URL(fileURLWithPath: application.executablePath).standardizedFileURL
            return (application.id, primary, auxiliarySearchRoot(for: application))
        }
        let replacements = await Task.detached(priority: .utility) {
            candidates.compactMap { applicationID, primary, searchRoot -> (UUID, URL)? in
                let preferred = ExecutableDiscovery.preferredLaunchExecutable(
                    for: primary,
                    searchRoot: searchRoot
                )
                return preferred == primary ? nil : (applicationID, preferred)
            }
        }.value
        guard !replacements.isEmpty else { return }

        for (applicationID, executable) in replacements {
            guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { continue }
            applications[index].executablePath = executable.path
            applications[index].auxiliaryExecutables = nil
            applications[index].lastResult = "Direct game executable selected: \(executable.lastPathComponent)"
        }
        save()
    }

    private func runAuxiliaryExecutableAsync(_ requestedAction: AuxiliaryExecutable, for applicationID: UUID) async {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        let application = applications[index]
        guard application.status != .running, !application.status.isBusy else { return }
        guard let action = auxiliaryExecutables(for: application).first(where: { $0.id == requestedAction.id }) else {
            presentedIssue = BorealIssue(
                title: "This game action is no longer available",
                stage: "Validating the selected auxiliary executable.",
                recovery: "Reopen the game details so Boreal can scan the installation again.",
                technicalDetails: requestedAction.executablePath
            )
            return
        }
        let executable = URL(fileURLWithPath: action.executablePath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: executable.path) else {
            presentedIssue = BorealIssue(
                title: "\(action.displayName) couldn’t open",
                stage: "Finding the selected executable.",
                recovery: "Verify or reinstall the game files, then try again.",
                technicalDetails: executable.path
            )
            return
        }

        advancedConfigurations[applicationID] = await services.advancedConfigurationStore.configuration(for: applicationID)
        do {
            guard let environmentRecord = environment(id: application.environmentID),
                  var managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await runtime(for: environmentRecord) else {
                throw InstallerServiceError.noRuntimeAvailable
            }
            let launchProfile = GameGraphicsProfiles.effectiveCompatibilityProfile(
                application.resolvedCompatibilityProfile,
                for: application
            )
            let existingComponentReferences = managed.configuration.graphicsComponentReferences
            managed.configuration = EnvironmentConfiguration(
                name: environmentRecord.name,
                profile: launchProfile
            )
            managed.configuration.graphicsComponentReferences = existingComponentReferences
            try GameLaunchCompatibility.prepare(
                application: application,
                environment: managed,
                runtime: runtime
            )
            managed = try await services.environmentManager.configure(managed, runtime: runtime)
            let windowsPlan = WindowsLaunchPlan(
                executable: executable,
                arguments: [],
                environment: [:],
                workingDirectory: executable.deletingLastPathComponent()
            )
            let launchPlan = await makeLaunchPlan(
                windowsPlan,
                applicationID: application.id,
                provider: application.storeProvider,
                externalID: application.storeExternalID,
                environment: managed,
                runtime: runtime,
                profile: launchProfile
            )
            lastLaunchPlans[application.id] = launchPlan
            if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[currentIndex].graphics = launchPlan.graphicsStack?.backend.displayName ?? launchPlan.graphicsBackend.displayName
            }
            let session = try await services.launchCoordinator.start(
                plan: launchPlan,
                environment: managed,
                runtime: runtime
            ).processSession
            if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[currentIndex].lastResult = "Opened \(action.displayName)"
                applications[currentIndex].lastErrorDetail = nil
                save()
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await services.processRunner.waitForExit(session)
                    guard let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) else { return }
                    applications[currentIndex].lastResult = result.exitCode == 0
                        ? "\(action.displayName) closed"
                        : "\(action.displayName) exited with code \(result.exitCode)"
                    save()
                } catch {
                    // Losing the bookkeeping receipt does not make the game
                    // installation unavailable, so keep this out of app status.
                }
            }
        } catch {
            present(
                error,
                title: "\(action.displayName) couldn’t open",
                stage: "Starting the tool in \(application.name)’s Windows environment"
            )
        }
    }

    private func dlssUnlockerExecutable(
        for application: WindowsApplication,
        in environment: ManagedBorealEnvironment
    ) -> URL? {
        if application.storeProvider == .steam,
           application.storeExternalID == GameLaunchCompatibility.gtaSanAndreasDefinitiveEditionSteamAppID,
           let gameRoot = SteamWindowsService.installedGameDirectory(
               appID: GameLaunchCompatibility.gtaSanAndreasDefinitiveEditionSteamAppID,
               in: environment
           ) {
            return GameLaunchCompatibility.gtaSanAndreasExecutable(in: gameRoot)
                ?? SteamWindowsService.primaryExecutable(in: gameRoot, applicationName: application.name)
        }
        let executable = URL(fileURLWithPath: application.executablePath).standardizedFileURL
        if let gameExecutable = GameLaunchCompatibility.gtaSanAndreasExecutable(
            in: executable.deletingLastPathComponent()
        ) {
            return gameExecutable
        }
        return FileManager.default.isReadableFile(atPath: executable.path) ? executable : nil
    }

    private func installDLSSUnlockerAsync(_ requestedArchive: URL, for applicationID: UUID) async {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        let application = applications[index]
        guard GameLaunchCompatibility.supportsDLSSUnlocker(for: application),
              application.status != .running,
              !application.status.isBusy,
              runtimeOperationDetail == nil else { return }

        let archive = requestedArchive.standardizedFileURL
        let hasSecurityScope = archive.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { archive.stopAccessingSecurityScopedResource() } }
        do {
            guard let environmentRecord = environment(id: application.environmentID),
                  let managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await runtime(for: environmentRecord),
                  let gameExecutable = dlssUnlockerExecutable(for: application, in: managed) else {
                throw GameLaunchCompatibilityError.dlssUnlockerTargetUnavailable(
                    URL(fileURLWithPath: application.executablePath)
                )
            }
            let environmentManager = services.environmentManager
            try await GameLaunchCompatibility.installDLSSUnlocker(
                from: archive,
                nextTo: gameExecutable,
                importRegistry: { registryFile in
                    try await environmentManager.importRegistry(
                        registryFile,
                        in: managed,
                        runtime: runtime
                    )
                }
            )
            if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[currentIndex].lastResult = "GTA SA DLSS Unlocker installed"
                applications[currentIndex].lastErrorDetail = "FSR 2.1 replacement is enabled for the next DX12 launch."
                save()
            }
            SoundService.shared.play(.confirmation)
        } catch {
            present(
                error,
                title: "GTA SA DLSS Unlocker couldn’t be installed",
                stage: "Validating the archive, backing up game DLLs, and importing the Wine signature override"
            )
        }
    }

    private func uninstallDLSSUnlockerAsync(for applicationID: UUID) async {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        let application = applications[index]
        guard GameLaunchCompatibility.supportsDLSSUnlocker(for: application),
              application.status != .running,
              !application.status.isBusy,
              runtimeOperationDetail == nil else { return }

        do {
            guard let environmentRecord = environment(id: application.environmentID),
                  let managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await runtime(for: environmentRecord),
                  let gameExecutable = dlssUnlockerExecutable(for: application, in: managed) else {
                throw GameLaunchCompatibilityError.dlssUnlockerTargetUnavailable(
                    URL(fileURLWithPath: application.executablePath)
                )
            }
            let environmentManager = services.environmentManager
            try await GameLaunchCompatibility.uninstallDLSSUnlocker(
                nextTo: gameExecutable,
                importRegistry: { registryFile in
                    try await environmentManager.importRegistry(
                        registryFile,
                        in: managed,
                        runtime: runtime
                    )
                }
            )
            if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[currentIndex].lastResult = "GTA SA DLSS Unlocker removed"
                applications[currentIndex].lastErrorDetail = nil
                save()
            }
            SoundService.shared.play(.confirmation)
        } catch {
            present(
                error,
                title: "GTA SA DLSS Unlocker couldn’t be removed",
                stage: "Restoring the original GTA San Andreas DLLs and disabling the Wine signature override"
            )
        }
    }

    private func runWindowsInstallerAsync(_ requestedInstaller: URL, for applicationID: UUID) async {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        let application = applications[index]
        guard !application.isInstallerOnly,
              !application.isSteamRuntimeHost,
              application.status != .running,
              !application.status.isBusy else { return }

        let installer = requestedInstaller.standardizedFileURL
        let supportedExtensions = ["exe", "msi"]
        guard supportedExtensions.contains(installer.pathExtension.lowercased()),
              (try? installer.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            presentedIssue = BorealIssue(
                title: "This Windows installer can’t be opened",
                stage: "Validating the selected patch or DLC installer.",
                recovery: "Choose a Windows installer in .exe or .msi format.",
                technicalDetails: installer.path
            )
            return
        }

        do {
            guard let environmentRecord = environment(id: application.environmentID),
                  var managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await runtime(for: environmentRecord) else {
                throw InstallerServiceError.noRuntimeAvailable
            }
            let launchProfile = GameGraphicsProfiles.effectiveCompatibilityProfile(
                application.resolvedCompatibilityProfile,
                for: application
            )
            let existingComponentReferences = managed.configuration.graphicsComponentReferences
            managed.configuration = EnvironmentConfiguration(
                name: environmentRecord.name,
                profile: launchProfile
            )
            managed.configuration.graphicsComponentReferences = existingComponentReferences
            managed = try await services.environmentManager.configure(managed, runtime: runtime)
            let session = try await services.processRunner.run(
                plan: WindowsLaunchPlan(
                    executable: installer,
                    arguments: [],
                    environment: [:],
                    workingDirectory: installer.deletingLastPathComponent()
                ),
                environment: managed,
                runtime: runtime
            )
            if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[currentIndex].lastResult = "Running \(installer.lastPathComponent)"
                applications[currentIndex].lastErrorDetail = nil
                save()
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await services.processRunner.waitForExit(session)
                    guard let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) else { return }
                    applications[currentIndex].lastResult = result.exitCode == 0
                        ? "\(installer.lastPathComponent) completed"
                        : "\(installer.lastPathComponent) exited with code \(result.exitCode)"
                    save()
                } catch {
                    // The external installer does not own the game lifecycle.
                }
            }
        } catch {
            present(
                error,
                title: "\(installer.lastPathComponent) couldn’t open",
                stage: "Starting the installer in \(application.name)’s Windows environment"
            )
        }
    }

    private func toggleRunningAsync(_ id: UUID) async {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        if applications[index].status == .running {
            requestedStops.insert(id)
            var stopError: Error?
            if applications[index].usesSharedSteamGameSession {
                if let environment = activeEnvironments[id],
                   let runtime = activeRuntimes[id],
                   let session = activeSessions[id]
                    ?? recoveredSessionForSharedSteam(application: applications[index], environment: environment) {
                    do {
                        try await services.processRunner.stopProcessGroup(
                            session: session,
                            environment: environment,
                            runtime: runtime
                        )
                    } catch {
                        stopError = error
                    }
                } else {
                    stopError = ProcessRunnerError.sessionNotFound(id)
                }
                // Steam's client and wineserver belong to the shared host,
                // not to this game's session.
                if stopError == nil {
                    markEnvironmentEnded(appID: id, environmentSessionEnded: false)
                    return
                }
            } else {
                do {
                    if let session = activeSessions[id] {
                        try await services.processRunner.stopApplication(session)
                    }
                }
                catch {
                    stopError = error
                }
                // Stopping the Wine launcher does not necessarily stop child
                // processes or the environment's wineserver. Close both layers so
                // the environment monitor can reach the terminal Ready state.
                if let environment = activeEnvironments[id], let runtime = activeRuntimes[id] {
                    do {
                        try await services.processRunner.terminateEnvironmentSession(environment: environment, runtime: runtime)
                        // The environment is the authoritative lifecycle owner;
                        // a stale launcher session error is no longer actionable
                        // once the Wine session was closed successfully.
                        stopError = nil
                    }
                    catch {
                        stopError = stopError ?? error
                    }
                }
            }
            if activeSessions[id] == nil && activeEnvironments[id] == nil {
                markEnvironmentEnded(appID: id, environmentSessionEnded: !applications[index].usesSharedSteamGameSession)
            } else if let stopError {
                requestedStops.remove(id)
                present(stopError, title: "\(applications[index].name) couldn’t stop", stage: "Requesting a normal application exit")
            }
            return
        }
        guard !applications[index].status.isBusy else { return }
        if let provider = applications[index].storeProvider,
           let externalID = applications[index].storeExternalID,
           let game = storeGames.first(where: { $0.provider == provider && $0.externalID == externalID }) {
            let currentInstallation = installation(for: game)
            guard let installation = currentInstallation, installation.state.isLaunchable else {
                let detail = currentInstallation?.state == .volumeUnavailable
                    ? "Connect the volume containing this installation, then try again."
                    : "Boreal could not confirm the installed game files. Reconnect the volume or repair the installation first."
                presentedIssue = BorealIssue(
                    title: "\(game.name) is not ready to play",
                    stage: "Checking the canonical game installation.",
                    recovery: detail,
                    technicalDetails: "\(game.provider.rawValue):\(game.externalID)"
                )
                applications[index].status = .needsAttention
                save()
                return
            }
            guard !installation.preparationState.blocksLaunch else {
                presentedIssue = BorealIssue(
                    title: "\(game.name) needs preparation",
                    stage: "Checking the game’s compatibility environment.",
                    recovery: installation.preparationState == .incompatible
                        ? "Choose a compatible runtime or repair the environment before launching."
                        : "Prepare the game environment before launching it.",
                    technicalDetails: "Preparation state: \(installation.preparationState.rawValue)"
                )
                return
            }
        }
        advancedConfigurations[id] = await services.advancedConfigurationStore.configuration(for: id)
        if let requiredEngine = GameRuntimeProfiles.requiredEngine(for: applications[index]),
           let environmentRecord = environment(id: applications[index].environmentID),
           let runtime = try? await services.runtimeManager.installedRuntimes().first(where: { $0.id == environmentRecord.runtimeID }),
           runtime.resolvedEngine != requiredEngine {
            let previousProfile = applications[index].resolvedCompatibilityProfile
            var compatibleProfile = previousProfile
            compatibleProfile.graphicsBackend = requiredEngine == .gamePortingToolkit ? .d3dMetal : .automatic
            applications[index].compatibilityProfile = compatibleProfile
            applications[index].graphics = requiredEngine.graphicsName
            applications[index].lastResult = "Preparing the compatible \(requiredEngine.displayName) runtime"
            save()
            recreateEnvironment(
                id,
                with: requiredEngine,
                launchWhenReady: true,
                rollbackProfile: previousProfile
            )
            return
        }
        let usesExistingExecutable = applications[index].installerPath == "existing-installation"
            || applications[index].usesStoreMetadataOnly
        let refreshesExecutableAtLaunch = !usesExistingExecutable && [.epic, .gog].contains(applications[index].storeProvider) && applications[index].storeExternalID != nil
        guard refreshesExecutableAtLaunch || FileManager.default.fileExists(atPath: applications[index].executablePath) else {
            let itemType = applications[index].isInstallerOnly ? "installer" : "application executable"
            applications[index].status = .unavailable
            applications[index].lastResult = "Executable unavailable"
            applications[index].lastFailureStage = "Checking application files"
            applications[index].lastErrorDetail = "The configured \(itemType) no longer exists at \(applications[index].executablePath)."
            save()
            presentedIssue = BorealIssue(
                title: "\(applications[index].name) is unavailable",
                stage: "Boreal couldn’t find the configured \(itemType).",
                recovery: applications[index].isInstallerOnly
                    ? "Choose the installer again if you want to create a new installer environment."
                    : "Reinstall the application to create a complete environment.",
                technicalDetails: applications[index].executablePath
            )
            return
        }
        applications[index].status = .preparing
        executionStates[id] = .preparing
        applications[index].lastErrorDetail = nil
        applications[index].lastFailureStage = nil
        do {
            guard let environmentRecord = environment(id: applications[index].environmentID),
                  var managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await services.runtimeManager.installedRuntimes().first(where: { $0.id == environmentRecord.runtimeID }) else {
                throw InstallerServiceError.noRuntimeAvailable
            }
            var profile = compatibilityProfile(for: applications[index])
            if applications[index].compatibilityProfile == nil {
                // The persisted environment is the resolved automatic choice.
                // Reuse it for this launch instead of re-running an older
                // default profile and accidentally discarding the prepared
                // backend/prefix decision.
                profile.windowsVersion = WineWindowsVersion(rawValue: managed.configuration.windowsVersion) ?? profile.windowsVersion
                profile.graphicsBackend = managed.configuration.graphicsBackend
                profile.graphicsAPI = managed.configuration.graphicsAPI == .automatic ? nil : managed.configuration.graphicsAPI
                profile.graphicsFallback = managed.configuration.graphicsFallback
                profile.prefixMode = managed.configuration.prefixMode
                profile.requiredDependencies = managed.configuration.requiredDependencies
            }
            if GameGraphicsProfiles.profile(for: applications[index])?.enforcedBackend != nil,
               applications[index].compatibilityProfile != profile {
                applications[index].compatibilityProfile = profile
                applications[index].graphics = profile.graphicsBackend.displayName
                applications[index].lastResult = "Using the stable graphics profile for \(applications[index].name)"
                save()
            }
            let configuredExecutable = URL(fileURLWithPath: applications[index].executablePath)
            let executable = ExecutableDiscovery.preferredLaunchExecutable(
                for: configuredExecutable,
                searchRoot: auxiliarySearchRoot(for: applications[index])
            )
            if executable != configuredExecutable {
                applications[index].executablePath = executable.path
                applications[index].auxiliaryExecutables = nil
                applications[index].lastResult = "Using direct game executable \(executable.lastPathComponent)"
                save()
            }
            let isUnityIL2CPP = UnityIL2CPPRuntimeCompatibility.requiresModernWine(at: executable)
            if runtime.resolvedEngine == .gamePortingToolkit, isUnityIL2CPP {
                let previousProfile = profile
                profile.graphicsBackend = .automatic
                if let recommendedGraphicsAPI = UnityIL2CPPRuntimeCompatibility.recommendedGraphicsAPI(for: executable) {
                    profile.graphicsAPI = recommendedGraphicsAPI
                }
                applications[index].compatibilityProfile = profile
                applications[index].lastResult = "Rebuilding the Unity IL2CPP environment with Wine"
                applications[index].lastErrorDetail = nil
                save()
                recreateStandaloneEnvironment(
                    applications[index].id,
                    profile: profile,
                    previousProfile: previousProfile,
                    engine: .wine,
                    launchWhenReady: true
                )
                return
            }
            if isUnityIL2CPP,
               let recommendedGraphicsAPI = UnityIL2CPPRuntimeCompatibility.recommendedGraphicsAPI(for: executable),
               profile.graphicsBackend != .automatic || profile.graphicsAPI != recommendedGraphicsAPI {
                profile.graphicsBackend = .automatic
                profile.graphicsAPI = recommendedGraphicsAPI
                applications[index].compatibilityProfile = profile
                applications[index].lastResult = "Using DirectX 11 with the compatible Wine graphics backend"
                applications[index].lastErrorDetail = nil
                save()
            }
            if Heroes3DirectDrawCompatibility.usesWineBuiltinDirectDraw(for: executable) {
                // Heroes 3 Complete ships DDrawCompat as xdd.dll. It crashes
                // under this Wine WoW64 runtime, while Wine's builtin
                // DirectDraw path is stable for the game's PE32 executable.
                profile.graphicsBackend = .wineD3D
                profile.graphicsAPI = .automatic
                applications[index].compatibilityProfile = profile
                applications[index].graphics = profile.graphicsBackend.displayName
            } else if profile.graphicsAPI == nil {
                profile.graphicsAPI = await Task.detached(priority: .utility) {
                    GraphicsAPIDetector.detect(executable: executable)
                }.value
            }
            let graphicsProfile = GameGraphicsProfiles.profile(for: applications[index])
            let selectedGraphicsAPI = profile.graphicsAPI ?? graphicsProfile?.defaultAPI ?? .automatic
            let graphicsLaunchOption = selectedGraphicsAPI == .automatic ? nil : graphicsProfile?.launchOption(for: selectedGraphicsAPI)
            let environmentProfile = applications[index].usesSharedSteamGameSession
                ? sharedSteamEnvironmentProfile(from: profile, environment: managed, runtime: runtime)
                : profile
            let existingComponentReferences = managed.configuration.graphicsComponentReferences
            managed.configuration = EnvironmentConfiguration(name: environmentRecord.name, profile: environmentProfile)
            managed.configuration.graphicsComponentReferences = existingComponentReferences
            try GameLaunchCompatibility.prepare(
                application: applications[index],
                environment: managed,
                runtime: runtime
            )
            managed = try await services.environmentManager.configure(managed, runtime: runtime)
            applications[index].status = .starting
            let session: WindowsProcessSession
            if !usesExistingExecutable,
               let provider = applications[index].storeProvider,
               [.steam, .epic, .gog].contains(provider),
               let appID = applications[index].storeExternalID {
                let plan: WindowsLaunchPlan
                var gameDirectory: URL?
                switch provider {
                case .steam:
                    let executable = URL(fileURLWithPath: applications[index].executablePath)
                    guard let installedDirectory = SteamWindowsService.installedGameDirectory(appID: appID, in: managed) else {
                        throw SteamWindowsError.gameNotInstalled(appID)
                    }
                    gameDirectory = installedDirectory
                    var bootstrapPlan = SteamWindowsService.bootstrapPlan(steamExecutable: executable)
                    bootstrapPlan.overlayCompatibleFullscreen = profile.overlayCompatibleFullscreen
                    bootstrapPlan.overlayDisplayID = profile.overlayDisplayID
                    let bootstrap = try await services.launchCoordinator.start(
                        plan: await makeLaunchPlan(
                            bootstrapPlan,
                            applicationID: applications[index].id,
                            provider: provider,
                            externalID: appID,
                            environment: managed,
                            runtime: runtime,
                            profile: profile
                        ),
                        environment: managed,
                        runtime: runtime
                    ).processSession
                    Task { _ = try? await services.processRunner.waitForExit(bootstrap) }
                    try await Task.sleep(for: .milliseconds(400))
                    let gameExecutable = SteamWindowsService.primaryExecutable(
                        in: installedDirectory,
                        applicationName: applications[index].name
                    )
                    plan = SteamWindowsService.playPlan(
                        appID: appID,
                        steamExecutable: executable,
                        gameExecutableName: gameExecutable?.lastPathComponent,
                        gameExecutablePath: gameExecutable?.path,
                        sessionScope: applications[index].usesSharedSteamGameSession ? .processGroup : .exclusiveEnvironment
                    )
                case .epic, .gog:
                    guard let storedGame = storeGames.first(where: { $0.provider == provider && $0.externalID == appID }) else {
                        throw GameStoreProviderError.installationMissing(provider)
                    }
                    let game = canonicalStoreGame(storedGame)
                    if let installPath = installedLocation(for: storedGame) {
                        gameDirectory = installPath
                    }
                    plan = try await services.launchCoordinator.makeStoreLaunchPlan(
                        for: game,
                        runtime: runtime,
                        environment: managed,
                        providerRegistry: services.storeProviders
                    )
                }
                applications[index].executablePath = plan.executable.path
                var configuredPlan = try GameGraphicsProfiles.applying(
                    graphicsLaunchOption,
                    to: plan,
                    gameDirectory: gameDirectory
                )
                configuredPlan.arguments.append(contentsOf: profile.parsedLaunchArguments)
                configuredPlan.overlayCompatibleFullscreen = profile.overlayCompatibleFullscreen
                configuredPlan.overlayDisplayID = profile.overlayDisplayID
                configuredPlan = GameGraphicsProfiles.applying(
                    graphicsProfile,
                    backend: environmentProfile.graphicsBackend,
                    to: configuredPlan
                )
                if provider != .steam {
                    let graphicsPlan = try graphicsCompatibilityManager.apply(
                        configuration: profile,
                        application: applications[index],
                        executable: configuredPlan.executable,
                        environment: managed,
                        runtime: runtime
                    )
                    configuredPlan = graphicsCompatibilityManager.applying(graphicsPlan, to: configuredPlan)
                }
                configuredPlan = GameLaunchCompatibility.applying(
                    to: configuredPlan,
                    application: applications[index],
                    gameDirectory: gameDirectory
                )
                let launchPlan = await makeLaunchPlan(
                    configuredPlan,
                    applicationID: applications[index].id,
                    provider: provider,
                    externalID: appID,
                    environment: managed,
                    runtime: runtime,
                    profile: environmentProfile,
                    directXAPIOverride: applications[index].usesSharedSteamGameSession ? selectedGraphicsAPI : nil,
                    gameRoot: gameDirectory
                )
                lastLaunchPlans[applications[index].id] = launchPlan
                applications[index].graphics = launchPlan.graphicsStack?.backend.displayName ?? launchPlan.graphicsBackend.displayName
                session = try await services.launchCoordinator.start(
                    plan: launchPlan,
                    environment: managed,
                    runtime: runtime
                ).processSession
            } else {
                let executable = URL(fileURLWithPath: applications[index].executablePath)
                var configuredPlan = try GameGraphicsProfiles.applying(
                    graphicsLaunchOption,
                    to: WindowsLaunchPlan(
                        executable: executable,
                        arguments: [],
                        environment: [:],
                        workingDirectory: executable.deletingLastPathComponent()
                    )
                )
                configuredPlan.arguments.append(contentsOf: profile.parsedLaunchArguments)
                configuredPlan.overlayCompatibleFullscreen = profile.overlayCompatibleFullscreen
                configuredPlan.overlayDisplayID = profile.overlayDisplayID
                configuredPlan = GameGraphicsProfiles.applying(
                    graphicsProfile,
                    backend: profile.graphicsBackend,
                    to: configuredPlan
                )
                let graphicsPlan = try graphicsCompatibilityManager.apply(
                    configuration: profile,
                    application: applications[index],
                    executable: configuredPlan.executable,
                    environment: managed,
                    runtime: runtime
                )
                configuredPlan = graphicsCompatibilityManager.applying(graphicsPlan, to: configuredPlan)
                configuredPlan = GameLaunchCompatibility.applying(
                    to: configuredPlan,
                    application: applications[index]
                )
                let launchPlan = await makeLaunchPlan(
                    configuredPlan,
                    applicationID: applications[index].id,
                    provider: applications[index].storeProvider,
                    externalID: applications[index].storeExternalID,
                    environment: managed,
                    runtime: runtime,
                    profile: profile
                )
                lastLaunchPlans[applications[index].id] = launchPlan
                applications[index].graphics = launchPlan.graphicsStack?.backend.displayName ?? launchPlan.graphicsBackend.displayName
                session = try await services.launchCoordinator.start(
                    plan: launchPlan,
                    environment: managed,
                    runtime: runtime
                ).processSession
            }
            applications[index].status = .running
            executionStates[id] = .running
            applications[index].lastOpened = .now
            SoundService.shared.play(.launch)
            activeSessions[id] = session
            beginPlaySession(appID: id)
            if !applications[index].isInstallerOnly {
                ControllerManager.shared.activate(
                    for: id,
                    profileName: applications[index].name,
                    keyboardMappingEnabled: !profile.disableSteamInputEquivalent
                        && (advancedConfigurations[id]?.controllerProfile.desktopNavigationEnabled ?? true),
                    controllerProfile: advancedConfigurations[id]?.controllerProfile ?? .default
                )
            }
            performanceLogURLs[id] = session.stderrLog
            activeEnvironments[id] = managed
            activeRuntimes[id] = runtime
            save()
            startPerformanceProcessTracking(session: session, environment: managed, runtime: runtime, appID: id)
            monitorLauncher(session: session, appID: id)
            monitorEnvironmentSession(environment: managed, runtime: runtime, appID: id)
        } catch {
            let diagnosis = await diagnoseLaunchFailure(for: id, stderr: SecretRedactor.redact(error.localizedDescription))
            executionStates[id] = .failed(SecretRedactor.redact(error.localizedDescription))
            applications[index].status = .needsAttention
            applications[index].lastResult = diagnosis?.summary ?? "Couldn’t open"
            applications[index].lastFailureStage = diagnosis.map { "Launch diagnosis: \($0.category.rawValue)" } ?? "Starting application"
            applications[index].lastErrorDetail = SecretRedactor.redact(error.localizedDescription)
            save()
            present(error, title: "\(applications[index].name) couldn’t open", stage: "Boreal was preparing or starting the application.", retryApplicationID: id)
        }
    }

    private func removeApplicationAndEnvironment(_ id: UUID) async {
        guard let app = application(id: id) else { return }
        do {
            if let environment = activeEnvironments[id], let runtime = activeRuntimes[id] {
                if app.usesSharedSteamGameSession {
                    guard let session = activeSessions[id]
                        ?? recoveredSessionForSharedSteam(application: app, environment: environment) else {
                        throw ProcessRunnerError.sessionNotFound(id)
                    }
                    try await services.processRunner.forceQuitProcessGroup(
                        session: session,
                        environment: environment,
                        runtime: runtime
                    )
                } else {
                    try? await services.processRunner.forceQuitEnvironment(environment: environment, runtime: runtime)
                }
            }
            if !app.isInstallerOnly {
                _ = try? await createSaveBackup(for: id, trigger: .beforeUninstall)
                if let record = environment(id: app.environmentID),
                   let managed = managedEnvironment(from: record),
                   FileManager.default.fileExists(atPath: managed.rootURL.appending(path: "environment.json").path) {
                    _ = try? await createEnvironmentSnapshot(for: app.environmentID, reason: .manualCompatibilityChange)
                }
            }
            let hasOtherApps = applications.contains { $0.id != id && $0.environmentID == app.environmentID }
            if !hasOtherApps, let record = environment(id: app.environmentID), let managed = managedEnvironment(from: record) {
                try await services.environmentManager.remove(managed)
            }
            applications.removeAll { $0.id == id }
            ControllerManager.shared.deactivate(for: id)
            if !hasOtherApps { environments.removeAll { $0.id == app.environmentID } }
            activeSessions[id] = nil
            stopPerformanceProcessTracking(for: id)
            performanceLogURLs[id] = nil
            activeEnvironments[id] = nil
            activeRuntimes[id] = nil
            automaticRendererFallbacksPending.remove(id)
            environmentSessionStates[app.environmentID] = nil
            environmentMonitorIDs[id] = nil
            save()
        } catch { present(error, title: "The application couldn’t be removed", stage: "Removing application and environment data") }
    }

    private func managedEnvironment(from record: WindowsEnvironment) -> ManagedBorealEnvironment? {
        guard let runtimeID = record.runtimeID, let root = record.rootPath, let prefix = record.prefixPath, let logs = record.logsPath else { return nil }
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let prefixURL = URL(fileURLWithPath: prefix).standardizedFileURL
        let logsURL = URL(fileURLWithPath: logs).standardizedFileURL
        let descriptor = rootURL.appending(path: "environment.json")
        if let data = try? Data(contentsOf: descriptor),
           let stored = try? JSONDecoder().decode(ManagedBorealEnvironment.self, from: data),
           stored.id == record.id,
           stored.runtimeID == runtimeID,
           stored.rootURL.standardizedFileURL == rootURL,
           stored.prefixURL.standardizedFileURL == prefixURL,
           stored.logsURL.standardizedFileURL == logsURL {
            return stored
        }

        // Legacy records did not persist the managed descriptor separately.
        // Reconstruct only the fields that the old UI record could represent.
        return ManagedBorealEnvironment(
            id: record.id,
            configuration: EnvironmentConfiguration(
                name: record.name,
                windowsVersion: "win11",
                architecture: record.architecture == "64-bit" ? "win64" : "win32"
            ),
            runtimeID: runtimeID,
            rootURL: rootURL,
            prefixURL: prefixURL,
            logsURL: logsURL,
            state: .ready
        )
    }

    private func monitorLauncher(session: WindowsProcessSession, appID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let result = try? await services.processRunner.waitForExit(session)
            guard let index = applications.firstIndex(where: { $0.id == appID }) else { return }
            let wasRequested = requestedStops.contains(appID)
            let fallbackWasAlreadyPrepared = automaticRendererFallbackLogURLs.remove(session.stderrLog) != nil
            let shouldRetryWithWineD3D = !wasRequested
                && !fallbackWasAlreadyPrepared
                && prepareAutomaticRendererFallback(appID: appID, logURL: session.stderrLog)
            if shouldRetryWithWineD3D {
                applications[index].lastResult = "Renderer initialization failed; switching to WineD3D/Vulkan"
                applications[index].lastExitCode = result?.exitCode
            } else if let result, result.exitCode != 0, !wasRequested, !fallbackWasAlreadyPrepared {
                SoundService.shared.play(.error)
                unexpectedLauncherFailures.insert(appID)
                applications[index].lastResult = "Exited unexpectedly"
                applications[index].lastExitCode = result.exitCode
                applications[index].lastFailureStage = applications[index].isInstallerOnly ? "Running installer" : "Running application"
                applications[index].lastErrorDetail = "The application process exited with code \(result.exitCode)."
                if !applications[index].isInstallerOnly {
                    _ = await diagnoseLaunchFailure(for: appID, stderr: applications[index].lastErrorDetail ?? "")
                }
            } else {
                applications[index].lastResult = applications[index].isInstallerOnly
                    ? (wasRequested ? "Installer stopped" : "Installer exited normally")
                    : (wasRequested ? "Launcher stopped" : "Launcher exited normally")
                applications[index].lastExitCode = result?.exitCode
            }
            executionStates[appID] = .terminated(exitCode: result?.exitCode)
            activeSessions[appID] = nil
            stopPerformanceProcessTracking(for: appID)
            save()
            if !wasRequested,
               let application = application(id: appID),
               !application.usesSharedSteamGameSession,
               !application.isInstallerOnly {
                schedulePrimaryProcessExit(appID: appID)
            }
        }
    }

    private func schedulePrimaryProcessExit(appID: UUID) {
        guard let expectedSessionID = activePlaySessions[appID]?.sessionID else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, activePlaySessions[appID]?.sessionID == expectedSessionID else { return }
            endPlaySession(appID: appID)
        }
    }

    private func monitorEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime, appID: UUID) {
        let monitorID = UUID()
        environmentMonitorIDs[appID] = monitorID
        let application = application(id: appID)
        let session = activeSessions[appID] ?? recoveredSessionForSharedSteam(
            application: application,
            environment: environment
        )
        Task { [weak self] in
            guard let self else { return }
            if let session, session.sessionScope == .processGroup {
                do {
                    try await services.gameSessionCoordinator.waitForEnd(
                        session: session,
                        environment: environment,
                        runtime: runtime
                    )
                    guard environmentMonitorIDs[appID] == monitorID else { return }
                    // Steam's client and wineserver intentionally survive the
                    // game. Only the process-group session has ended here.
                    markEnvironmentEnded(appID: appID, environmentSessionEnded: false)
                } catch is CancellationError {
                    return
                } catch {
                    guard environmentMonitorIDs[appID] == monitorID else { return }
                    markEnvironmentUnknown(appID: appID, detail: error.localizedDescription)
                }
                return
            }
            for _ in 0..<40 {
                guard environmentMonitorIDs[appID] == monitorID else { return }
                switch await services.processRunner.environmentSessionState(environment: environment, runtime: runtime) {
                case .active:
                    environmentSessionStates[environment.id] = .active
                    do {
                        try await services.gameSessionCoordinator.waitForEnd(
                            session: session ?? WindowsProcessSession(
                                id: UUID(),
                                environmentID: environment.id,
                                launcherPID: 0,
                                startedAt: .now,
                                stdoutLog: environment.logsURL.appending(path: "session-monitor.stdout.log"),
                                stderrLog: environment.logsURL.appending(path: "session-monitor.stderr.log")
                            ),
                            environment: environment,
                            runtime: runtime
                        )
                        guard environmentMonitorIDs[appID] == monitorID else { return }
                        markEnvironmentEnded(appID: appID)
                    } catch {
                        guard environmentMonitorIDs[appID] == monitorID else { return }
                        markEnvironmentUnknown(appID: appID, detail: error.localizedDescription)
                    }
                    return
                case .unknown:
                    markEnvironmentUnknown(appID: appID, detail: "Boreal couldn’t determine whether the Windows environment is active.")
                    return
                case .inactive:
                    if await launcherIsRunning(appID: appID) {
                        try? await Task.sleep(for: .milliseconds(250))
                        continue
                    }
                    markEnvironmentEnded(appID: appID)
                    return
                }
            }
            markEnvironmentUnknown(appID: appID, detail: "The Windows environment did not reach a stable session state.")
        }
    }

    private func launcherIsRunning(appID: UUID) async -> Bool {
        guard let session = activeSessions[appID],
              let state = try? await services.processRunner.state(of: session) else { return false }
        if case .running = state { return true }
        return false
    }

    private func recoveredSessionForSharedSteam(
        application: WindowsApplication?,
        environment: ManagedBorealEnvironment
    ) -> WindowsProcessSession? {
        guard let application, application.usesSharedSteamGameSession else { return nil }
        let gameExecutable = SteamWindowsService.installedGameDirectory(
            appID: application.storeExternalID ?? "",
            in: environment
        ).flatMap {
            SteamWindowsService.primaryExecutable(in: $0, applicationName: application.name)
        }
        return WindowsProcessSession(
            id: UUID(),
            environmentID: environment.id,
            launcherPID: 0,
            startedAt: .now,
            stdoutLog: environment.logsURL.appending(path: "recovered-steam.stdout.log"),
            stderrLog: environment.logsURL.appending(path: "recovered-steam.stderr.log"),
            sessionScope: .processGroup,
            processExecutableName: gameExecutable?.lastPathComponent,
            processExecutablePath: gameExecutable?.path
        )
    }

    private func recoveredSessionForApplication(
        application: WindowsApplication,
        environment: ManagedBorealEnvironment
    ) -> WindowsProcessSession {
        let plan = lastLaunchPlans[application.id]
        return WindowsProcessSession(
            id: UUID(),
            environmentID: environment.id,
            launcherPID: 0,
            startedAt: application.lastOpened ?? .now,
            stdoutLog: environment.logsURL.appending(path: "recovered-\(application.id.uuidString).stdout.log"),
            stderrLog: performanceLogURL(for: application.id) ?? environment.logsURL.appending(path: "recovered-\(application.id.uuidString).stderr.log"),
            sessionScope: .exclusiveEnvironment,
            processExecutableName: plan?.processExecutableName ?? URL(fileURLWithPath: application.executablePath).lastPathComponent,
            processExecutablePath: plan?.processExecutablePath ?? application.executablePath
        )
    }

    private func recoverPersistedSessions(appIDs: [UUID]) async {
        for appID in appIDs {
            guard let app = application(id: appID),
                  let environmentRecord = environment(id: app.environmentID),
                  let managed = managedEnvironment(from: environmentRecord),
                  let installedRuntime = try? await runtime(for: environmentRecord) else {
                markEnvironmentUnknown(appID: appID, detail: "Boreal couldn’t reconstruct the environment runtime after restart.")
                continue
            }
            activeEnvironments[appID] = managed
            activeRuntimes[appID] = installedRuntime
            advancedConfigurations[appID] = await services.advancedConfigurationStore.configuration(for: appID)
            if app.usesSharedSteamGameSession {
                let recoveredSession = recoveredSessionForSharedSteam(
                    application: app,
                    environment: managed
                )
                if let recoveredSession {
                    activeSessions[appID] = recoveredSession
                    performanceLogURLs[appID] = recoveredSession.stderrLog
                    startPerformanceProcessTracking(session: recoveredSession, environment: managed, runtime: installedRuntime, appID: appID)
                }
                if let index = applications.firstIndex(where: { $0.id == appID }) { applications[index].status = .running }
                executionStates[appID] = .running
                beginPlaySession(appID: appID)
                if !app.isInstallerOnly {
                    ControllerManager.shared.activate(
                        for: appID,
                        profileName: app.name,
                        keyboardMappingEnabled: !compatibilityProfile(for: app).disableSteamInputEquivalent
                            && (advancedConfigurations[appID]?.controllerProfile.desktopNavigationEnabled ?? true),
                        controllerProfile: advancedConfigurations[appID]?.controllerProfile ?? .default
                    )
                }
                save()
                monitorEnvironmentSession(environment: managed, runtime: installedRuntime, appID: appID)
                continue
            }
            switch await services.processRunner.environmentSessionState(environment: managed, runtime: installedRuntime) {
            case .active:
                let recoveredSession = activeSessions[appID] ?? recoveredSessionForApplication(application: app, environment: managed)
                activeSessions[appID] = recoveredSession
                performanceLogURLs[appID] = recoveredSession.stderrLog
                startPerformanceProcessTracking(session: recoveredSession, environment: managed, runtime: installedRuntime, appID: appID)
                environmentSessionStates[managed.id] = .active
                if let index = applications.firstIndex(where: { $0.id == appID }) { applications[index].status = .running }
                executionStates[appID] = .running
                beginPlaySession(appID: appID)
                if !app.isInstallerOnly {
                    ControllerManager.shared.activate(
                        for: appID,
                        profileName: app.name,
                        keyboardMappingEnabled: !compatibilityProfile(for: app).disableSteamInputEquivalent
                            && (advancedConfigurations[appID]?.controllerProfile.desktopNavigationEnabled ?? true),
                        controllerProfile: advancedConfigurations[appID]?.controllerProfile ?? .default
                    )
                }
                save()
                monitorEnvironmentSession(environment: managed, runtime: installedRuntime, appID: appID)
            case .inactive:
                markEnvironmentEnded(appID: appID)
            case .unknown:
                markEnvironmentUnknown(appID: appID, detail: "Boreal couldn’t recover the Windows environment session after restart.")
            }
        }
    }

    private func runtime(for record: WindowsEnvironment) async throws -> InstalledRuntime? {
        guard let runtimeID = record.runtimeID else { return nil }
        return try await services.runtimeManager.installedRuntimes().first { $0.id == runtimeID }
    }

    private func markEnvironmentEnded(appID: UUID, environmentSessionEnded: Bool = true) {
        guard let index = applications.firstIndex(where: { $0.id == appID }) else { return }
        stopPerformanceProcessTracking(for: appID)
        endPlaySession(appID: appID)
        let environmentID = applications[index].environmentID
        let wasRequested = requestedStops.remove(appID) != nil
        let shouldRetryWithWineD3D = !wasRequested && (
            automaticRendererFallbacksPending.remove(appID) != nil
            || prepareAutomaticRendererFallback(appID: appID, logURL: nil)
        )
        if shouldRetryWithWineD3D {
            automaticRendererFallbacksPending.remove(appID)
            unexpectedLauncherFailures.remove(appID)
            applications[index].status = .ready
            applications[index].lastResult = "Retrying with WineD3D/Vulkan"
            applications[index].lastErrorDetail = nil
        } else if unexpectedLauncherFailures.remove(appID) != nil && !wasRequested {
            applications[index].status = .needsAttention
        } else {
            applications[index].status = .ready
            if wasRequested { applications[index].lastResult = "Stopped" }
        }
        executionStates[appID] = .terminated(exitCode: applications[index].lastExitCode)
        if environmentSessionEnded {
            environmentSessionStates[environmentID] = .inactive
        }
        activeSessions[appID] = nil
        performanceLogURLs[appID] = nil
        activeEnvironments[appID] = nil
        activeRuntimes[appID] = nil
        ControllerManager.shared.deactivate(for: appID)
        environmentMonitorIDs[appID] = nil
        save()
        if shouldRetryWithWineD3D {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self,
                      self.applications.first(where: { $0.id == appID })?.status == .ready else { return }
                await self.toggleRunningAsync(appID)
            }
        }
    }

    private func prepareAutomaticRendererFallback(appID: UUID, logURL: URL?) -> Bool {
        guard let index = applications.firstIndex(where: { $0.id == appID }),
              !applications[index].isInstallerOnly,
              let resolvedLogURL = logURL ?? performanceLogURLs[appID] else { return false }
        let application = applications[index]
        guard GameGraphicsProfiles.profile(for: application)?.enforcedBackend == nil else { return false }
        let currentProfile = application.resolvedCompatibilityProfile
        guard RendererLaunchFailureDetector.shouldUseWineD3DVulkanFallback(
            logURL: resolvedLogURL,
            profile: currentProfile
        ) else { return false }
        let failedBackend = lastLaunchPlans[appID]?.graphicsStack?.backend
            ?? lastLaunchPlans[appID]?.graphicsBackend
            ?? currentProfile.graphicsBackend
        automaticRendererFallbackLogURLs.insert(resolvedLogURL)
        automaticRendererFallbacksPending.insert(appID)
        var fallbackProfile = currentProfile
        fallbackProfile.graphicsBackend = .wineD3D
        fallbackProfile.graphicsFallback = .wineD3DVulkan
        applications[index].compatibilityProfile = fallbackProfile
        applications[index].graphics = fallbackProfile.graphicsBackend.displayName
        var events = applications[index].compatibilityFallbackEvents ?? []
        events.append(CompatibilityFallbackEvent(
            failedBackend: failedBackend,
            fallbackBackend: .wineD3D,
            reason: .graphicsDeviceInitialization,
            logReference: resolvedLogURL,
            environmentID: application.environmentID,
            resolverRevision: 1
        ))
        applications[index].compatibilityFallbackEvents = events
        applications[index].lastResult = "Renderer initialization failed; switching to WineD3D/Vulkan"
        applications[index].lastErrorDetail = "Boreal detected a Direct3D device initialization failure in the renderer log and selected the built-in Wine fallback for the next launch."
        save()
        return true
    }

    func beginPlaySession(appID: UUID, at date: Date = .now) {
        guard activePlaySessions[appID] == nil,
              let application = application(id: appID),
              let session = services.activityService.begin(
                  application: application,
                  games: &storeGames,
                  at: date
              ) else { return }
        save()
        activePlaySessions[appID] = ActivePlaySession(
            sessionID: session.id,
            checkpointInstant: ContinuousClock().now
        )
        startPlaySessionCheckpointing(appID: appID, sessionID: session.id)
    }

    func endPlaySession(appID: UUID, at date: Date = .now) {
        playSessionCheckpointTasks[appID]?.cancel()
        playSessionCheckpointTasks[appID] = nil
        checkpointPlaySession(appID: appID, at: date)
        let active = activePlaySessions.removeValue(forKey: appID)
        guard let application = application(id: appID) else { return }
        services.activityService.finish(
            sessionID: active?.sessionID,
            application: application,
            games: &storeGames,
            at: date
        )
        save()
    }

    private func startPlaySessionCheckpointing(appID: UUID, sessionID: UUID) {
        playSessionCheckpointTasks[appID]?.cancel()
        playSessionCheckpointTasks[appID] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self,
                      activePlaySessions[appID]?.sessionID == sessionID else { return }
                checkpointPlaySession(appID: appID)
            }
        }
    }

    private func checkpointPlaySession(appID: UUID, at date: Date = .now) {
        guard var active = activePlaySessions[appID],
              let application = application(id: appID) else { return }
        let now = ContinuousClock().now
        let elapsed = active.checkpointInstant.duration(to: now)
        let components = elapsed.components
        let elapsedSeconds = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        services.activityService.checkpoint(
            sessionID: active.sessionID,
            application: application,
            games: &storeGames,
            elapsed: elapsedSeconds,
            at: date
        )
        active.checkpointInstant = now
        activePlaySessions[appID] = active
        save()
    }

    private func markEnvironmentUnknown(appID: UUID, detail: String) {
        guard let index = applications.firstIndex(where: { $0.id == appID }) else { return }
        stopPerformanceProcessTracking(for: appID)
        applications[index].status = .needsAttention
        applications[index].lastErrorDetail = detail
        environmentSessionStates[applications[index].environmentID] = .unknown
        environmentMonitorIDs[appID] = nil
        SoundService.shared.play(.warning)
        save()
    }

    private func save() {
        synchronizeInstallationCompatibilityBridge()
        if usesLayeredStorage {
            let snapshot = BorealStorageSnapshot(
                applications: applications,
                storeGames: storeGames,
                favoriteKeys: favoriteKeys,
                storeDownloads: storeDownloadRecords,
                lastAutomaticLibraryRefreshAt: lastAutomaticLibraryRefreshAt,
                layout: storageLayout,
                installations: installations
            )
            Task { [weak self, libraryRepository] in
                do {
                    try await libraryRepository.save(snapshot)
                } catch {
                    await MainActor.run {
                        self?.present(error, title: "Boreal couldn’t save your Library", stage: "Saving layered application state")
                    }
                }
            }
            return
        }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(PersistedState(
                applications: applications,
                environments: environments,
                storeGames: storeGames,
                storeDownloads: storeDownloadRecords,
                favoriteKeys: Array(favoriteKeys).sorted(),
                lastAutomaticLibraryRefreshAt: lastAutomaticLibraryRefreshAt
            ))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            present(error, title: "Boreal couldn’t save your Library", stage: "Saving application state")
        }
    }

    func refreshRuntimeStatuses() async {
        runtimeDiscoveryState = .loading
        do {
            let installed = try await services.runtimeManager.installedRuntimes()
            let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
            for index in environments.indices {
                guard let runtimeID = environments[index].runtimeID,
                      let runtime = installedByID[runtimeID] else { continue }
                environments[index].runtime = runtime.runtimeDescription
            }
            var values: [RuntimeStatus] = []
            for runtime in installed {
                let validation = try await services.runtimeManager.validate(runtime)
                values.append(RuntimeStatus(
                    id: runtime.id,
                    name: runtime.displayName,
                    wineVersion: runtime.wineVersion,
                    architecture: runtime.architecture,
                    state: validation.isReady ? .installed : .needsAttention,
                    isVerified: validation.isReady,
                    detail: validation.isReady
                        ? (runtime.origin == .localImport ? "Validated local snapshot" : nil)
                        : "Runtime verification failed",
                    source: .installed,
                    origin: runtime.origin,
                    engine: runtime.resolvedEngine,
                    features: runtime.features
                ))
            }
            let installedIDs = Set(installed.map(\.id))
            localRuntimeCandidates = await services.runtimeManager.localRuntimeCandidates()
                .filter { !installedIDs.contains($0.id) }
            let available: [BorealRuntime]
            do {
                available = try await services.runtimeManager.availableRuntimes()
            } catch {
                runtimeStatuses = values
                runtimeDiscoveryState = localRuntimeCandidates.isEmpty
                    ? .failed(runtimeCatalogDetails(error: error))
                    : .loaded
                await refreshRuntimeComponentUpdates()
                return
            }
            for runtime in available where !installedIDs.contains(runtime.id) {
                values.append(RuntimeStatus(
                    id: runtime.id,
                    name: runtime.displayName,
                    wineVersion: runtime.wineVersion,
                    architecture: runtime.architecture,
                    compressedSize: runtime.artifact.compressedSize,
                    state: .available,
                    isVerified: false,
                    source: .catalog,
                    engine: runtime.engine,
                    features: runtime.features
                ))
            }
            runtimeStatuses = values
            runtimeDiscoveryState = .loaded
            await refreshRuntimeComponentUpdates()
        } catch {
            runtimeStatuses = []
            localRuntimeCandidates = await services.runtimeManager.localRuntimeCandidates()
            runtimeDiscoveryState = .failed(runtimeCatalogDetails(error: error))
        }
    }

    func refreshRuntimeComponentUpdates() async {
        do {
            runtimeComponentUpdates = try await services.runtimeManager.componentUpdates()
            runtimeComponentUpdateError = nil
        } catch {
            runtimeComponentUpdateError = error.localizedDescription
        }
    }

    func updateRuntimeComponent(_ update: RuntimeComponentUpdate) {
        guard runtimeOperationDetail == nil else { return }
        guard !activeRuntimes.values.contains(where: { $0.id == update.runtimeID }) else {
            runtimeComponentUpdateError = "Quit games using \(update.runtimeName) before updating its compatibility components."
            return
        }
        runtimeOperationDetail = "Downloading, verifying, and installing \(update.component.displayName) \(update.latestVersion)…"
        Task {
            do {
                _ = try await services.runtimeManager.downloadAndInstallComponent(update.component, into: update.runtimeID)
                runtimeOperationDetail = nil
                await refreshRuntimeStatuses()
            } catch {
                runtimeOperationDetail = nil
                present(
                    error,
                    title: "\(update.component.displayName) couldn’t be updated",
                    stage: "Checking and installing the independent compatibility component update"
                )
            }
        }
    }

    func runAutomaticCompatibilityUpdateCheck() async {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.object(forKey: "lastCompatibilityUpdateCheck") as? Date
        guard lastCheck == nil || Date.now.timeIntervalSince(lastCheck!) >= 24 * 60 * 60 else { return }
        defaults.set(Date.now, forKey: "lastCompatibilityUpdateCheck")
        await refreshRuntimeStatuses()
        if defaults.object(forKey: "automaticRuntimeUpdates") == nil || defaults.bool(forKey: "automaticRuntimeUpdates") {
            await installAvailableRuntimeRevisionsIfSafe()
        }
        for update in runtimeComponentUpdates where update.state == .available {
            guard !activeRuntimes.values.contains(where: { $0.id == update.runtimeID }) else { continue }
            let key: String?
            switch update.component {
            case .dxvk: key = "automaticDXVKUpdates"
            case .vkd3d: key = "automaticVKD3DUpdates"
            case .dxmt: key = nil
            }
            guard let key else { continue }
            guard defaults.object(forKey: key) == nil || defaults.bool(forKey: key) else { continue }
            do {
                _ = try await services.runtimeManager.downloadAndInstallComponent(update.component, into: update.runtimeID)
            } catch {
                runtimeComponentUpdateError = error.localizedDescription
            }
        }
        await refreshRuntimeStatuses()
    }

    private func installAvailableRuntimeRevisionsIfSafe() async {
        guard activeSessions.isEmpty,
              !applications.contains(where: { $0.status == .running || $0.status.isBusy }) else { return }
        let installed = runtimeStatuses.filter { $0.source == .installed }
        let candidates = runtimeStatuses.filter { candidate in
            guard candidate.source == .catalog, candidate.state == .available else { return false }
            return installed.contains {
                $0.name == candidate.name && $0.architecture == candidate.architecture
                    && $0.engine == candidate.engine
            }
        }
        for candidate in candidates {
            do {
                guard let manifest = try await services.runtimeManager.availableRuntimes().first(where: { $0.id == candidate.id }) else { continue }
                let replacement = try await services.runtimeManager.install(manifest)
                let replacedIDs = Set(installed.filter {
                    $0.name == candidate.name && $0.architecture == candidate.architecture && $0.engine == candidate.engine
                }.map(\.id))
                for index in environments.indices where environments[index].runtimeID.map(replacedIDs.contains) == true {
                    environments[index].runtimeID = replacement.id
                    environments[index].runtime = replacement.runtimeDescription
                }
                save()
            } catch {
                runtimeComponentUpdateError = error.localizedDescription
            }
        }
    }

    private func runtimeCatalogDetails(error: Error? = nil) -> String {
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif
        var lines = [
            "Runtime catalog",
            error?.localizedDescription ?? "No compatible runtime returned.",
            "",
            "Architecture: \(architecture)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Channel: stable"
        ]
        if error == nil { lines[1] = "No compatible runtime returned." }
        return lines.joined(separator: "\n")
    }

    func prepareRuntime(id: String) {
        Task {
            guard let index = runtimeStatuses.firstIndex(where: { $0.id == id }) else { return }
            runtimeStatuses[index].state = .preparing
            runtimeOperationDetail = "Downloading and verifying Windows compatibility runtime…"
            do {
                guard let runtime = try await services.runtimeManager.availableRuntimes().first(where: { $0.id == id }) else {
                    throw InstallerServiceError.noRuntimeAvailable
                }
                _ = try await services.runtimeManager.install(runtime)
                runtimeOperationDetail = nil
                await refreshRuntimeStatuses()
            } catch {
                runtimeStatuses[index].state = .needsAttention
                runtimeStatuses[index].detail = error.localizedDescription
                runtimeOperationDetail = nil
                runtimeDiscoveryState = .failed(runtimeCatalogDetails(error: error))
                present(error, title: "Boreal Runtime couldn’t be installed", stage: "Downloading, verifying, or preparing the runtime")
            }
        }
    }

    func importLocalRuntime(id: String) {
        guard let candidate = localRuntimeCandidates.first(where: { $0.id == id }), runtimeOperationDetail == nil else { return }
        runtimeOperationDetail = "Copying and validating \(candidate.displayName) as an isolated Boreal runtime…"
        Task {
            do {
                _ = try await services.runtimeManager.importLocalRuntime(candidate)
                runtimeOperationDetail = nil
                await refreshRuntimeStatuses()
            } catch {
                runtimeOperationDetail = nil
                runtimeDiscoveryState = .failed(runtimeCatalogDetails(error: error))
                present(error, title: "Installed Wine couldn’t be imported", stage: "Copying, validating, and smoke-testing the local runtime")
            }
        }
    }

    func importGPTKRuntime(from source: URL, for applicationID: UUID) {
        guard runtimeOperationDetail == nil,
              let index = applications.firstIndex(where: { $0.id == applicationID }),
              !applications[index].usesSharedSteamEnvironment,
              applications[index].status != .running,
              !applications[index].status.isBusy else { return }
        runtimeOperationDetail = String(localized: "Validating and importing the selected Game Porting Toolkit runtime…")
        Task {
            let hasSecurityScope = source.startAccessingSecurityScopedResource()
            defer { if hasSecurityScope { source.stopAccessingSecurityScopedResource() } }
            do {
                let runtime = try await services.runtimeManager.importSelectedGPTKRuntime(from: source)
                await refreshRuntimeStatuses()
                guard let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) else {
                    throw CancellationError()
                }
                let previousProfile = applications[currentIndex].resolvedCompatibilityProfile
                var profile = GameGraphicsProfiles.effectiveCompatibilityProfile(previousProfile, for: applications[currentIndex])
                profile.graphicsBackend = .d3dMetal
                profile.graphicsAPI = .directX12
                profile.runtimeIDOverride = runtime.id
                applications[currentIndex].compatibilityProfile = profile
                applications[currentIndex].lastResult = String(localized: "Imported GPTK runtime; rebuilding the game environment")
                runtimeOperationDetail = nil
                save()
                recreateStandaloneEnvironment(
                    applicationID,
                    profile: profile,
                    previousProfile: previousProfile,
                    engine: .gamePortingToolkit,
                    launchWhenReady: true
                )
            } catch {
                runtimeOperationDetail = nil
                present(
                    error,
                    title: String(localized: "Game Porting Toolkit couldn’t be imported"),
                    stage: String(localized: "Validating D3DMetal and preparing Dawnwalker's runtime")
                )
            }
        }
    }

    func installGraphicsComponent(
        _ backend: WineGraphicsBackend,
        from source: URL,
        into runtimeID: String
    ) {
        guard runtimeOperationDetail == nil else { return }
        runtimeOperationDetail = "Validating and installing \(backend.displayName)…"
        Task {
            let hasSecurityScope = source.startAccessingSecurityScopedResource()
            defer { if hasSecurityScope { source.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await services.runtimeManager.installGraphicsComponent(
                    backend, from: source, into: runtimeID
                )
                runtimeOperationDetail = nil
                await refreshRuntimeStatuses()
            } catch {
                runtimeOperationDetail = nil
                present(
                    error,
                    title: "\(backend.displayName) couldn’t be installed",
                    stage: "Validating and adding the graphics component to the selected runtime"
                )
            }
        }
    }

    func downloadGraphicsComponent(
        _ backend: WineGraphicsBackend,
        into runtimeID: String
    ) {
        guard runtimeOperationDetail == nil else { return }
        runtimeOperationDetail = "Finding the latest official \(backend.displayName) release…"
        Task {
            do {
                runtimeOperationDetail = "Downloading, verifying, and installing \(backend.displayName)…"
                _ = try await services.runtimeManager.downloadAndInstallGraphicsComponent(
                    backend, into: runtimeID
                )
                runtimeOperationDetail = nil
                await refreshRuntimeStatuses()
            } catch {
                runtimeOperationDetail = nil
                present(
                    error,
                    title: "\(backend.displayName) couldn’t be installed",
                    stage: "Finding and installing the latest official graphics component"
                )
            }
        }
    }

    func installedUpscalingBridgeVersion(
        for application: WindowsApplication,
        bridge: TemporalUpscalingBridge
    ) async -> String? {
        guard bridge != .none,
              let environment = environment(id: application.environmentID),
              let runtime = try? await services.runtimeManager.installedRuntimes().first(where: { $0.id == environment.runtimeID }),
              let references = try? await services.runtimeManager.upscalingBridgeReferences(bridge) else {
            return nil
        }
        let version = "gptk-" + runtime.id
        return references.first(where: { $0.version == version })?.version
    }

    func temporalUpscalingInspector(for applicationID: UUID) async -> TemporalUpscalingInspectorSnapshot? {
        guard let application = applications.first(where: { $0.id == applicationID }),
              let environmentRecord = environment(id: application.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let runtime = try? await services.runtimeManager.installedRuntimes().first(where: { $0.id == managed.runtimeID }) else {
            return nil
        }
        let gameRoot = temporalGameRoot(for: application)
        let executable = lastLaunchPlans[applicationID]?.processExecutablePath.map(URL.init(fileURLWithPath:))
            ?? URL(fileURLWithPath: application.executablePath)
        let game = await services.gameUpscalerAnalyzer.analyze(gameRoot: gameRoot, executable: executable)
        let profile = compatibilityProfile(for: application)
        let architecture = managed.configuration.resolvedPrefixArchitecture(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true)
        let gameProfile = application.storeProvider.flatMap { provider in
            application.storeExternalID.flatMap { GameGraphicsProfiles.profile(provider: provider, externalID: $0) }
        }
        let graphics = GraphicsBackendResolver.resolve(
            api: profile.graphicsAPI ?? .automatic,
            requestedBackend: profile.graphicsBackend,
            gameProfile: application.usesSharedSteamEnvironment ? nil : gameProfile,
            runtime: runtime,
            architecture: architecture,
            fallback: profile.graphicsFallback
        ).stack
        var temporalConfiguration = profile.temporalUpscaling
        if temporalConfiguration.mode == .automatic, profile.upscalingBridge == .ngxToMetalFX {
            temporalConfiguration.mode = .metalFXBridge
        }
        let dlsstweaks = await services.dlsstweaksManager.installedReference()
        let optiScaler = await services.optiScalerManager.installedReference()
        let dlsstweaksCapabilities: DLSSTweaksCapabilities? = if let dlsstweaks {
            // The manager exposes only controls declared by this exact
            // component version; no release-wide assumptions are made here.
            await services.dlsstweaksManager.capabilities(for: dlsstweaks)
        } else {
            nil
        }
        let metalFX = await Task.detached(priority: .utility) {
            MetalFXBridgeAnalyzer.inspect(runtime: runtime)
        }.value
        let managedDLSSRuntime = await services.dlssRuntimeManager.installedReference()
        let plan = await services.temporalUpscalingResolver.resolve(
            game: game,
            runtime: runtime,
            graphicsStack: graphics,
            configuration: temporalConfiguration,
            metalFX: metalFX,
            dlsstweaks: dlsstweaks,
            optiScaler: optiScaler,
            applicationID: applicationID
        )
        let dlssRuntime = await services.dlssRuntimeManager.detect(in: gameRoot)
        let ngxIndicator = await services.environmentManager.ngxDebugIndicatorState(in: managed, runtime: runtime)
        return TemporalUpscalingInspectorSnapshot(
            game: game,
            dlssRuntime: dlssRuntime,
            dlssRuntimeStatus: TemporalComponentStatus(installation: dlssRuntime),
            managedDLSSRuntime: TemporalComponentStatus(reference: managedDLSSRuntime),
            dlsstweaks: TemporalComponentStatus(reference: dlsstweaks),
            dlsstweaksCapabilities: dlsstweaksCapabilities,
            optiScaler: TemporalComponentStatus(reference: optiScaler),
            metalFX: metalFX,
            temporalPlan: plan,
            graphicsStack: graphics,
            runtimeDescription: runtime.runtimeDescription,
            ngxDebugIndicator: ngxIndicator
        )
    }

    private func temporalGameRoot(for application: WindowsApplication) -> URL {
        if let path = lastLaunchPlans[application.id]?.processExecutablePath {
            return URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
        }
        if let reference = application.storeReference,
           let game = storeGames.first(where: { $0.storeReference == reference }),
           let installPath = installedLocation(for: game) {
            return installPath.standardizedFileURL
        }
        return URL(fileURLWithPath: application.executablePath).deletingLastPathComponent().standardizedFileURL
    }

    func importTemporalComponent(
        _ component: TemporalComponentID,
        from source: URL,
        version requestedVersion: String? = nil,
        for applicationID: UUID
    ) async {
        guard let application = applications.first(where: { $0.id == applicationID }),
              application.status != .running,
              !application.status.isBusy,
              runtimeOperationDetail == nil else { return }
        let version = requestedVersion ?? source.lastPathComponent
        guard !version.isEmpty else { return }
        let scope = source.startAccessingSecurityScopedResource()
        defer { if scope { source.stopAccessingSecurityScopedResource() } }
        runtimeOperationDetail = "Importing \(component.displayName)…"
        do {
            let reference: TemporalComponentReference
            switch component {
            case .dlsstweaks:
                reference = try await services.dlsstweaksManager.install(from: source, version: version, licenseMetadata: "User-imported; redistribution not assumed")
            case .optiScaler:
                reference = try await services.optiScalerManager.install(from: source, version: version, licenseMetadata: "User-imported; redistribution not assumed")
            case .dlssRuntime:
                reference = try await services.dlssRuntimeManager.install(from: source, version: version, licenseMetadata: "User-imported; redistribution not assumed")
            }
            runtimeOperationDetail = nil
            if component == .optiScaler {
                await injectOptiScaler(reference: reference, for: applicationID)
            } else if let index = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[index].lastResult = "\(component.displayName) \(reference.version) imported into ComponentStore"
                applications[index].lastErrorDetail = nil
                save()
            }
        } catch {
            runtimeOperationDetail = nil
            present(error, title: "\(component.displayName) couldn’t be imported", stage: "Validating and storing the immutable temporal component")
        }
    }

    func installManagedDLSSRuntime(for applicationID: UUID) async {
        guard let application = applications.first(where: { $0.id == applicationID }),
              application.status != .running,
              !application.status.isBusy,
              let reference = await services.dlssRuntimeManager.installedReference() else { return }
        let gameRoot = temporalGameRoot(for: application)
        let executable = lastLaunchPlans[applicationID]?.processExecutablePath.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: application.executablePath)
        do {
            let installation = try await services.dlssRuntimeManager.installManagedVersion(
                reference,
                in: gameRoot,
                applicationID: applicationID,
                targetArchitecture: WindowsExecutableArchitecture.inspect(executable)
            )
            if let index = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[index].lastResult = "DLSS runtime \(reference.version) installed; original backup retained"
                applications[index].lastErrorDetail = "Active SHA-256: \(installation.activeSHA256)"
                save()
            }
        } catch {
            present(error, title: "DLSS runtime couldn’t be installed", stage: "Backing up the original DLL and applying the validated managed runtime")
        }
    }

    func restoreManagedDLSSRuntime(for applicationID: UUID) async {
        guard let application = applications.first(where: { $0.id == applicationID }),
              application.status != .running,
              !application.status.isBusy else { return }
        do {
            let installation = try await services.dlssRuntimeManager.removeManagedOverride(in: temporalGameRoot(for: application))
            if let index = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[index].lastResult = "Original DLSS runtime restored"
                applications[index].lastErrorDetail = "Restored SHA-256: \(installation.activeSHA256)"
                save()
            }
        } catch {
            present(error, title: "Original DLSS runtime couldn’t be restored", stage: "Validating the managed file and restoring the protected backup")
        }
    }

    func injectOptiScaler(for applicationID: UUID, confirmUnknownPolicy: Bool = true) async {
        guard let reference = await services.optiScalerManager.installedReference() else { return }
        await injectOptiScaler(
            reference: reference,
            for: applicationID,
            confirmUnknownPolicy: confirmUnknownPolicy
        )
    }

    private func injectOptiScaler(
        reference: TemporalComponentReference,
        for applicationID: UUID,
        confirmUnknownPolicy: Bool = true
    ) async {
        guard let application = applications.first(where: { $0.id == applicationID }),
              application.status != .running,
              !application.status.isBusy else { return }
        runtimeOperationDetail = "Backing up game files and installing OptiScaler next to the game executable…"
        defer { runtimeOperationDetail = nil }
        let gameRoot = temporalGameRoot(for: application)
        let executable = lastLaunchPlans[applicationID]?.processExecutablePath.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: application.executablePath)
        let game = await services.gameUpscalerAnalyzer.analyze(gameRoot: gameRoot, executable: executable)
        let profile = compatibilityProfile(for: application)
        var configuration = profile.temporalUpscaling.optiScaler
        configuration.enabled = true
        do {
            let receipt = try await services.optiScalerManager.inject(
                reference: reference,
                configuration: configuration,
                gameRoot: gameRoot,
                applicationID: applicationID,
                targetArchitecture: WindowsExecutableArchitecture.inspect(executable),
                antiCheat: game.antiCheat,
                confirmUnknownInjectionPolicy: confirmUnknownPolicy
            )
            if let index = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[index].compatibilityProfile?.temporalUpscaling.mode = .optiScaler
                applications[index].compatibilityProfile?.temporalUpscaling.optiScaler = configuration
                applications[index].lastResult = "OptiScaler \(reference.version) injected with receipt \(receipt.id.uuidString.prefix(8))"
                applications[index].lastErrorDetail = nil
                save()
            }
        } catch {
            present(error, title: "OptiScaler couldn’t be injected", stage: "Backing up game files and applying the managed DLL transaction")
        }
    }

    func injectDLSSTweaks(for applicationID: UUID, confirmUnknownPolicy: Bool = true) async {
        guard let application = applications.first(where: { $0.id == applicationID }),
              application.status != .running,
              !application.status.isBusy,
              let reference = await services.dlsstweaksManager.installedReference() else { return }
        let gameRoot = temporalGameRoot(for: application)
        let executable = lastLaunchPlans[applicationID]?.processExecutablePath.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: application.executablePath)
        let game = await services.gameUpscalerAnalyzer.analyze(gameRoot: gameRoot, executable: executable)
        guard game.dlss?.detected == true else {
            present(
                CocoaError(.featureUnsupported),
                title: "DLSSTweaks couldn’t be injected",
                stage: "A native DLSS interface was not detected in the game files"
            )
            return
        }
        do {
            let receipt = try await services.dlsstweaksManager.inject(
                reference: reference,
                gameRoot: gameRoot,
                applicationID: applicationID,
                targetArchitecture: WindowsExecutableArchitecture.inspect(executable),
                antiCheat: game.antiCheat,
                confirmUnknownInjectionPolicy: confirmUnknownPolicy
            )
            if let index = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[index].compatibilityProfile?.temporalUpscaling.mode = .dlsstweaks
                applications[index].compatibilityProfile?.temporalUpscaling.dlsstweaks.enabled = true
                applications[index].lastResult = "DLSSTweaks \(reference.version) injected with receipt \(receipt.id.uuidString.prefix(8))"
                applications[index].lastErrorDetail = nil
                save()
            }
        } catch {
            present(error, title: "DLSSTweaks couldn’t be injected", stage: "Backing up game files and applying the declared DLL transaction")
        }
    }

    func setNGXDebugIndicator(_ enabled: Bool, for applicationID: UUID) async {
        guard let application = applications.first(where: { $0.id == applicationID }),
              let environmentRecord = environment(id: application.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let runtime = try? await runtime(for: environmentRecord) else { return }
        do {
            let receipt = try await services.environmentManager.setNGXDebugIndicator(enabled, in: managed, runtime: runtime)
            let receiptURL = managed.rootURL.appending(path: "ngx-indicator-receipt.json")
            try TemporalComponentSecurity.makeEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
        } catch {
            present(error, title: "NGX debug indicator couldn’t be changed", stage: "Updating the selected Wine prefix registry")
        }
    }

    func restoreNGXDebugIndicator(for applicationID: UUID) async {
        guard let application = applications.first(where: { $0.id == applicationID }),
              let environmentRecord = environment(id: application.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let runtime = try? await runtime(for: environmentRecord) else { return }
        let receiptURL = managed.rootURL.appending(path: "ngx-indicator-receipt.json")
        guard let data = try? Data(contentsOf: receiptURL),
              let receipt = try? TemporalComponentSecurity.makeDecoder().decode(NGXDebugIndicatorReceipt.self, from: data) else { return }
        do {
            try await services.environmentManager.restoreNGXDebugIndicator(receipt, in: managed, runtime: runtime)
            try? FileManager.default.removeItem(at: receiptURL)
        } catch {
            present(error, title: "NGX debug indicator couldn’t be restored", stage: "Restoring the previous Wine prefix registry value")
        }
    }

    /// Copies a bridge into Boreal's immutable component store. The selected
    /// game profile is intentionally not changed here; the user chooses the
    /// bridge in the configurator and saves that choice explicitly.
    func installUpscalingBridge(
        _ bridge: TemporalUpscalingBridge,
        for applicationID: UUID
    ) async {
        guard bridge != .none,
              runtimeOperationDetail == nil,
              let application = applications.first(where: { $0.id == applicationID }),
              application.status != .running,
              !application.status.isBusy,
              let environmentRecord = environment(id: application.environmentID),
              let runtimeID = environmentRecord.runtimeID else { return }
        let bridgeName = bridge == .ngxToMetalFX ? String(localized: "NGX → MetalFX") : String(localized: "Disabled")
        runtimeOperationDetail = String(localized: "Installing \(bridgeName) from the selected Game Porting Toolkit runtime…")
        do {
            _ = try await services.runtimeManager.installUpscalingBridge(
                bridge,
                fromRuntimeID: runtimeID
            )
            runtimeOperationDetail = nil
            if let index = applications.firstIndex(where: { $0.id == applicationID }) {
                applications[index].lastResult = String(localized: "\(bridgeName) installed")
                applications[index].lastErrorDetail = nil
                save()
            }
        } catch {
            runtimeOperationDetail = nil
            present(
                error,
                title: String(localized: "\(bridgeName) couldn’t be installed"),
                stage: String(localized: "Copying and validating the immutable temporal upscaling bridge")
            )
        }
    }

    func retry(_ id: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        applications[index].status = .ready
        toggleRunning(id)
    }

    private func updateInstallation(_ stage: InstallationStage) {
        if let previous = installation.stage { installation.completedStages.insert(previous) }
        installation.stage = stage
    }

    private func storeOperationKey(for game: StoreLibraryGame) -> String {
        "\(game.provider.rawValue)::\(game.externalID)"
    }

    func defaultGameInstallationRoot(for provider: GameLibraryProvider) -> URL {
        gameInstallationBaseRoot
            .appending(path: provider == .epic ? "Epic" : provider.rawValue, directoryHint: .isDirectory)
    }

    var gameInstallationBaseRoot: URL {
        if let path = UserDefaults.standard.string(forKey: Self.gameInstallationRootDefaultsKey),
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return storageURL.deletingLastPathComponent()
            .appending(path: "Games", directoryHint: .isDirectory)
    }

    nonisolated static func gameInstallationDestinationIsAvailable(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents
        if components.count >= 3, components[1] == "Volumes" {
            let volumeRoot = URL(fileURLWithPath: "/Volumes", isDirectory: true)
                .appending(path: components[2], directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: volumeRoot.path) else { return false }
        }

        var candidate = standardized
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: candidate.path)
    }

    var gamesNeedingRelocation: [StoreLibraryGame] {
        storeGames.filter { game in
            guard installation(for: game)?.state == .installed,
                  [.epic, .gog].contains(game.provider),
                  let path = installedLocation(for: game)?.path else { return false }
            let destination = defaultGameInstallationRoot(for: game.provider).standardizedFileURL.path
            let installed = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
            return installed != destination && !installed.hasPrefix(destination + "/")
        }
    }

    func moveInstalledGamesToPreferredLocation() {
        guard gameRelocationProgress == nil else { return }
        let games = gamesNeedingRelocation
        guard !games.isEmpty else { return }
        let references = Set(games.map(\.storeReference))
        let busyApplication = applications.contains {
            guard let provider = $0.storeProvider, let externalID = $0.storeExternalID else { return false }
            return references.contains(StoreReference(provider: provider, externalID: externalID))
                && ($0.status == .running || $0.status.isBusy)
        }
        let busyDownload = games.contains { storeGameOperations[storeOperationKey(for: $0)] != nil }
        guard !busyApplication, !busyDownload else {
            presentedIssue = BorealIssue(
                title: "Games are currently in use",
                stage: "Preparing to move installed games.",
                recovery: "Close the affected games and wait for their downloads or updates to finish, then try again.",
                technicalDetails: "Affected games: \(games.map(\.name).joined(separator: ", "))"
            )
            return
        }
        let roots = Set(games.map { defaultGameInstallationRoot(for: $0.provider) })
        guard roots.allSatisfy(Self.gameInstallationDestinationIsAvailable) else {
            presentedIssue = BorealIssue(
                title: "The new game location is unavailable",
                stage: "Preparing to move installed games.",
                recovery: "Connect the selected disk or choose another location.",
                technicalDetails: gameInstallationBaseRoot.path
            )
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                for (offset, game) in games.enumerated() {
                    gameRelocationProgress = "Moving \(game.name) (\(offset + 1) of \(games.count))…"
                    try await moveInstalledGame(game)
                }
                gameRelocationProgress = nil
                SoundService.shared.play(.confirmation)
            } catch {
                gameRelocationProgress = nil
                present(error, title: "Games couldn’t be moved", stage: "Moving installed games to the new location")
            }
        }
    }

    private func moveInstalledGame(_ game: StoreLibraryGame) async throws {
        guard let index = storeGames.firstIndex(where: { $0.id == game.id }),
              installation(for: game)?.state == .installed,
              let oldPath = installedLocation(for: game)?.path else { return }
        let oldURL = URL(fileURLWithPath: oldPath, isDirectory: true).standardizedFileURL
        let newURL: URL
        switch game.provider {
        case .epic:
            newURL = try await services.epicLibrary.moveInstallation(
                appID: game.externalID,
                destinationRoot: defaultGameInstallationRoot(for: .epic)
            )
        case .gog:
            let root = defaultGameInstallationRoot(for: .gog)
            newURL = try await Task.detached(priority: .utility) {
                try Self.moveGOGInstallation(game, from: oldURL, destinationRoot: root)
            }.value
        default:
            return
        }
        replaceInstallationPath(from: oldURL, to: newURL, gameIndex: index)
        save()
        refreshGameDiskStorage(for: storeGames[index])
    }

    nonisolated private static func moveGOGInstallation(
        _ game: StoreLibraryGame,
        from installationURL: URL,
        destinationRoot root: URL
    ) throws -> URL {
        var container = installationURL
        while container.path != "/", container.lastPathComponent != game.externalID {
            container.deleteLastPathComponent()
        }
        if container.lastPathComponent != game.externalID { container = installationURL }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appending(path: game.externalID, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let staging = root.appending(path: ".moving-\(game.id.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: container, to: staging)
        do {
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        // The complete copy is already published. If deleting the source fails,
        // keep both copies rather than risking the only valid installation.
        try? FileManager.default.removeItem(at: container)
        let relativeSuffix = installationURL.path.dropFirst(container.path.count)
        return URL(fileURLWithPath: destination.path + relativeSuffix, isDirectory: true)
    }

    private func replaceInstallationPath(from oldURL: URL, to newURL: URL, gameIndex: Int) {
        let oldPath = oldURL.path
        let newPath = newURL.path
        storeGames[gameIndex].installPath = newPath
        storeGames[gameIndex].storageBytes = GameStorage.allocatedSize(of: newURL)
        recordInstallation(
            for: storeGames[gameIndex],
            location: newURL,
            platform: installedPlatform(for: storeGames[gameIndex]) ?? .windows
        )
        for index in applications.indices {
            guard applications[index].storeProvider == storeGames[gameIndex].provider,
                  applications[index].storeExternalID == storeGames[gameIndex].externalID else { continue }
            if applications[index].executablePath == oldPath || applications[index].executablePath.hasPrefix(oldPath + "/") {
                applications[index].executablePath = newPath + applications[index].executablePath.dropFirst(oldPath.count)
            }
        }
    }

    private func updateStoreDownload(_ progress: StoreGameOperationProgress, key: String, token: UUID) {
        guard storeOperationTokens[key] == token else { return }
        var progress = progress
        let previousProgress = storeGameOperations[key]?.progress ?? storeDownloadRecords[key]?.lastProgress
        let knownTotal = storeGames.first(where: { storeOperationKey(for: $0) == key })?.sizeEstimate?.downloadBytes
        if progress.totalBytes == nil {
            progress.totalBytes = previousProgress?.totalBytes ?? knownTotal
        }
        if progress.total == nil, let totalBytes = progress.totalBytes {
            progress.total = StoreGameOperationProgress.byteCountString(totalBytes)
        }
        if progress.fractionCompleted == nil {
            progress.fractionCompleted = previousProgress?.fractionCompleted
        }
        if progress.estimatedTimeRemaining == nil,
           progress.phase == previousProgress?.phase {
            progress.estimatedTimeRemaining = previousProgress?.estimatedTimeRemaining
        }
        if progress.networkBytesPerSecond == nil,
           progress.phase == previousProgress?.phase {
            progress.networkBytesPerSecond = previousProgress?.networkBytesPerSecond
        }
        if progress.diskBytesPerSecond == nil,
           progress.phase == previousProgress?.phase {
            progress.diskBytesPerSecond = previousProgress?.diskBytesPerSecond
        }
        if progress.transferredBytes == nil,
           let fraction = progress.fractionCompleted,
           let totalBytes = progress.totalBytes {
            progress.transferredBytes = Int64((Double(totalBytes) * min(max(fraction, 0), 1)).rounded())
        }
        if progress.transferredBytes == nil {
            progress.transferredBytes = previousProgress?.transferredBytes
        }
        if progress.transferred == nil, let transferredBytes = progress.transferredBytes {
            progress.transferred = StoreGameOperationProgress.byteCountString(transferredBytes)
        }
        if var record = storeDownloadRecords[key] {
            if let startedAt = record.lastProgress?.startedAt { progress.startedAt = startedAt }
            record.status = .downloading
            record.lastProgress = progress
            record.lastError = nil
            record.updatedAt = .now
            var samples = record.samples ?? []
            if progress.networkBytesPerSecond != nil || progress.diskBytesPerSecond != nil,
               samples.last.map({ Date.now.timeIntervalSince($0.timestamp) >= 1 }) != false {
                samples.append(StoreDownloadSample(
                    timestamp: .now,
                    networkBytesPerSecond: progress.networkBytesPerSecond,
                    diskBytesPerSecond: progress.diskBytesPerSecond
                ))
                if samples.count > 120 {
                    samples.removeFirst(samples.count - 120)
                }
                record.samples = samples
            }
            storeDownloadRecords[key] = record
            let now = Date()
            if lastDownloadRecordSave[key].map({ now.timeIntervalSince($0) >= 2 }) != false {
                lastDownloadRecordSave[key] = now
                save()
            }
        }
        storeGameOperations[key] = .installing(progress)
    }

    private func initialDownloadProgress(message: String, game: StoreLibraryGame) -> StoreGameOperationProgress {
        var progress = StoreGameOperationProgress(message: message, fractionCompleted: nil)
        if let totalBytes = game.sizeEstimate?.downloadBytes {
            progress.totalBytes = totalBytes
            progress.total = StoreGameOperationProgress.byteCountString(totalBytes)
        }
        return progress
    }

    private func updateSteamPreparation(_ stage: InstallationStage, key: String, token: UUID) {
        guard storeOperationTokens[key] == token else { return }
        let stages = InstallationStage.allCases
        let index = stages.firstIndex(of: stage) ?? 0
        let fraction = Double(index) / Double(max(stages.count, 1))
        updateStoreDownload(StoreGameOperationProgress(
            message: stage.userMessage,
            fractionCompleted: fraction,
            phase: .installing
        ), key: key, token: token)
    }

    private func updateEnvironmentPreparation(_ message: String, fraction: Double, key: String, token: UUID) {
        guard storeOperationTokens[key] == token else { return }
        storeGameOperations[key] = .preparingEnvironment(StoreGameOperationProgress(
            message: message,
            fractionCompleted: fraction
        ))
    }

    private func finishCancelledStoreOperation(key: String, token: UUID) {
        guard storeOperationTokens[key] == token else { return }
        storeOperationTasks[key] = nil
        storeOperationTokens[key] = nil
        storeGameOperations[key] = nil
    }

    private func preserveDiagnosticsAndRemoveFailedEnvironment(
        _ environment: ManagedBorealEnvironment?
    ) async -> EnvironmentFailureDiagnostics? {
        guard let environment else { return nil }
        let diagnostics = await services.environmentManager.preserveFailureDiagnostics(environment)
        try? await services.environmentManager.remove(environment)
        return diagnostics
    }

    private func present(
        _ error: Error,
        title: String,
        stage: String,
        retryApplicationID: UUID? = nil,
        diagnostics: EnvironmentFailureDiagnostics? = nil
    ) {
        SoundService.shared.play(.error)
        presentedIssue = BorealIssue(
            title: title,
            stage: stage,
            recovery: "Try again. If the problem continues, open Details for technical information.",
            technicalDetails: SecretRedactor.redact(diagnostics?.technicalDetails(for: error) ?? error.localizedDescription),
            retryApplicationID: retryApplicationID
        )
    }
}
