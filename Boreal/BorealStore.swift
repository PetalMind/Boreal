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
    private(set) var favoriteKeys: Set<String> = []
    var librarySyncState: LibrarySyncState = .idle
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
    private let storageURL: URL
    private let services: BorealServices
    private let graphicsCompatibilityManager = GraphicsCompatibilityManager()
    private var activeSessions: [UUID: WindowsProcessSession] = [:]
    private var performanceLogURLs: [UUID: URL] = [:]
    private var activeEnvironments: [UUID: ManagedBorealEnvironment] = [:]
    private var activeRuntimes: [UUID: InstalledRuntime] = [:]
    private var requestedStops: Set<UUID> = []
    private var unexpectedLauncherFailures: Set<UUID> = []
    private var environmentSessionStates: [UUID: EnvironmentSessionState] = [:]
    private var environmentMonitorIDs: [UUID: UUID] = [:]
    private var storeOperationTasks: [String: Task<Void, Never>] = [:]
    private var storeOperationTokens: [String: UUID] = [:]
    private var storeDownloadRecords: [String: StoreDownloadRecord] = [:]
    private var lastDownloadRecordSave: [String: Date] = [:]
    private var steamMetadataRefreshes: Set<String> = []
    private var storeSizeEstimateLoads: Set<String> = []
    private let storeSizeEstimateGate = StoreSizeEstimateGate(limit: 3)
    private var installationTask: Task<UUID?, Never>?
    private var installationToken: UUID?
    private var lastAutomaticLibraryRefreshAt: Date?
    private var isRunningAutomaticLibraryRefresh = false
    private var isEnrichingInstalledApplicationMetadata = false

    nonisolated static let automaticLibraryRefreshInterval: TimeInterval = 8 * 60 * 60

    init(storageURL: URL? = nil, services: BorealServices? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageURL = storageURL ?? base.appending(path: "Boreal/library.json")
        self.services = services ?? .live(applicationSupportURL: (storageURL?.deletingLastPathComponent() ?? base.appending(path: "Boreal")))
        load()
        var didNormalizeApplicationState = false
        for index in applications.indices {
            let application = applications[index]
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
                    $0.provider == provider && $0.externalID == externalID && $0.isInstalled
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
            await refreshRuntimeStatuses()
            await refreshMissingAuxiliaryExecutables()
            await enrichInstalledApplicationMetadata()
        }
    }

    func application(id: UUID) -> WindowsApplication? { applications.first { $0.id == id } }
    func storeGame(id: UUID) -> StoreLibraryGame? { storeGames.first { $0.id == id } }
    func isFavorite(key: String) -> Bool { favoriteKeys.contains(key) }

    func auxiliaryExecutables(for application: WindowsApplication) -> [AuxiliaryExecutable] {
        application.resolvedAuxiliaryExecutables.filter {
            FileManager.default.fileExists(atPath: $0.executablePath)
        }
    }

    func runAuxiliaryExecutable(_ action: AuxiliaryExecutable, for applicationID: UUID) {
        Task { await runAuxiliaryExecutableAsync(action, for: applicationID) }
    }

    func toggleFavorite(key: String) {
        if favoriteKeys.contains(key) { favoriteKeys.remove(key) }
        else { favoriteKeys.insert(key) }
        save()
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
            storeGames[index] = value
            save()
        }
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
        let platform: StoreGameInstallationPlatform = game.supportsNativeMacOS == true ? .nativeMacOS : .windows
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
    func applications(in environmentID: UUID) -> [WindowsApplication] { applications.filter { $0.environmentID == environmentID } }

    func recommendedRuntimeEngine(for game: StoreLibraryGame) -> RuntimeEngine {
        game.provider == .gog && game.externalID == "2022341186" ? .gamePortingToolkit : .wine
    }

    func hasInstalledRuntime(engine: RuntimeEngine) -> Bool {
        runtimeStatuses.contains { $0.source == .installed && $0.state == .installed && $0.engine == engine }
    }

    func runtimeCompatibilityIssue(for application: WindowsApplication, engine: RuntimeEngine) -> String? {
        guard engine == .gamePortingToolkit,
              WindowsExecutableArchitecture.inspect(URL(fileURLWithPath: application.executablePath)) == .x86 else { return nil }
        let supportsWoW64 = runtimeStatuses.contains {
            $0.source == .installed
                && $0.state == .installed
                && $0.engine == engine
                && $0.features?.wow64 == true
        }
        return supportsWoW64 ? nil : "This game is 32-bit. The installed GPTK runtime does not support WoW64, so use Wine instead."
    }

    func compatibilityProfile(for application: WindowsApplication) -> WineCompatibilityProfile {
        if let saved = application.compatibilityProfile { return saved }
        var profile = application.resolvedCompatibilityProfile
        if let builtIn = GameGraphicsProfiles.profile(for: application) {
            profile.graphicsAPI = builtIn.defaultAPI
            if let preferredBackend = builtIn.preferredBackend {
                profile.graphicsBackend = preferredBackend
            }
        }
        if environment(id: application.environmentID)?.architecture == "32-bit" {
            profile.architecture = .win32
        }
        return profile
    }

    func graphicsBackendIssue(_ backend: WineGraphicsBackend, for application: WindowsApplication) -> String? {
        guard backend != .automatic, backend != .wineD3D else { return nil }
        if backend == .dxmt, compatibilityProfile(for: application).architecture == .win32 {
            return "DXMT currently supports only 64-bit Windows games. Choose Win64 or another renderer."
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
        case .automatic, .wineD3D:
            return nil
        }
    }

    func updateCompatibilityProfile(for applicationID: UUID, profile: WineCompatibilityProfile) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }),
              applications[index].status != .running,
              !applications[index].status.isBusy else { return }
        let previousProfile = applications[index].resolvedCompatibilityProfile
        let previousWindowsVersion = applications[index].windowsVersion
        let previousGraphics = applications[index].graphics
        let currentEngine: RuntimeEngine = environment(id: applications[index].environmentID)?.graphics == RuntimeEngine.gamePortingToolkit.graphicsName
            ? .gamePortingToolkit : .wine
        let currentRuntimeID = environment(id: applications[index].environmentID)?.runtimeID
        let currentRuntimeFeatures = runtimeStatuses.first { $0.id == currentRuntimeID }?.features
        applications[index].compatibilityProfile = profile
        applications[index].windowsVersion = profile.windowsVersion.displayName
        let requestedEngine = profile.graphicsBackend.requiredEngine ?? currentEngine
        let currentRuntimeSupportsBackend: Bool
        switch profile.graphicsBackend {
        case .d3dMetal: currentRuntimeSupportsBackend = currentRuntimeFeatures?.d3dmetal == true
        case .dxmt: currentRuntimeSupportsBackend = currentRuntimeFeatures?.dxmt == true
        case .dxvk: currentRuntimeSupportsBackend = currentRuntimeFeatures?.dxvk == true
        case .automatic, .wineD3D: currentRuntimeSupportsBackend = true
        }
        let requiresRecreation = previousProfile.architecture != profile.architecture
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
                managed.configuration = EnvironmentConfiguration(name: environmentRecord.name, profile: profile)
                try await services.environmentManager.configure(managed, runtime: runtime)
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
                    applications[currentIndex].lastErrorDetail = error.localizedDescription
                    save()
                    present(error, title: "\(applications[currentIndex].name) couldn’t be configured", stage: "Applying the Wine compatibility profile")
                }
            }
        }
    }

    private func recreateStandaloneEnvironment(_ applicationID: UUID, profile: WineCompatibilityProfile, previousProfile: WineCompatibilityProfile, engine: RuntimeEngine) {
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
                let runtime = try await prepareRuntime(
                    supporting: profile.graphicsBackend,
                    preferredEngine: engine
                )
                let executableArchitecture = WindowsExecutableArchitecture.inspect(executable)
                if executableArchitecture == .x86_64, profile.architecture == .win32 {
                    throw RuntimeManagerError.incompatible64BitExecutable
                }
                if executableArchitecture == .x86, profile.architecture == .win64, runtime.features?.wow64 != true {
                    throw RuntimeManagerError.incompatible32BitExecutable(runtime: runtime.displayName)
                }
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
            } catch {
                let diagnostics = await preserveDiagnosticsAndRemoveFailedEnvironment(replacement)
                if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                    applications[currentIndex].compatibilityProfile = previousProfile
                    applications[currentIndex].windowsVersion = previousProfile.windowsVersion.displayName
                    applications[currentIndex].graphics = previousProfile.graphicsBackend.displayName
                    applications[currentIndex].status = .ready
                    applications[currentIndex].lastResult = "Environment rebuild failed"
                    applications[currentIndex].lastErrorDetail = error.localizedDescription
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

    func install(_ candidate: InstallCandidate) async -> UUID? {
        installation = InstallationProgress(state: .installing, stage: .preparingRuntime)
        do {
            let commit = try await services.installer.install(candidate.url, name: candidate.name) { [weak self] stage in
                await self?.updateInstallation(stage)
            }
            let communityProfile: CommunityCompatibility? = nil
            let managed = commit.environment
            let environment = WindowsEnvironment(
                id: managed.id,
                name: managed.configuration.name,
                windowsVersion: "Windows 11",
                architecture: managed.configuration.architecture == "win64" ? "64-bit" : "32-bit",
                runtime: commit.runtime.runtimeDescription,
                graphics: commit.runtime.graphicsName,
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
            let app = WindowsApplication(
                name: metadata?.name ?? candidate.name,
                publisher: metadata?.developer ?? "Windows application",
                executablePath: commit.executable.path,
                installerPath: candidate.url.path,
                environmentID: environment.id,
                status: .running,
                compatibility: communityProfile?.tier.rating ?? .unknown,
                graphics: commit.runtime.graphicsName,
                lastOpened: .now,
                iconSymbol: symbol(for: candidate.name),
                lastResult: "First launch verified",
                storeProvider: metadata?.provider,
                storeExternalID: metadata?.externalID,
                storeMetadataOnly: metadata == nil ? nil : true,
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
            await refreshAuxiliaryExecutables(for: app.id)
            activeSessions[app.id] = commit.firstLaunch
            performanceLogURLs[app.id] = commit.firstLaunch.stderrLog
            activeEnvironments[app.id] = managed
            activeRuntimes[app.id] = commit.runtime
            save()
            installation.completedStages = Set(InstallationStage.allCases)
            installation.state = .succeeded(app.id)
            monitorLauncher(session: commit.firstLaunch, appID: app.id)
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
            return nil
        }
    }

    private func matchStoreMetadata(for rawNames: [String]) async -> StoreLibraryGame? {
        for name in rawNames.map(Self.storeSearchTitle).filter({ !$0.isEmpty }) {
            let normalized = SteamLibraryService.normalizedStoreTitle(name)
            let localMatches = storeGames.filter { SteamLibraryService.normalizedStoreTitle($0.name) == normalized }
            if localMatches.count == 1 { return localMatches[0] }
            if localMatches.count > 1 { continue }
            if let match = await services.steamLibrary.searchStoreGame(named: name) { return match }
        }
        return nil
    }

    private func enrichInstalledApplicationMetadata() async {
        guard !isEnrichingInstalledApplicationMetadata else { return }
        isEnrichingInstalledApplicationMetadata = true
        defer { isEnrichingInstalledApplicationMetadata = false }
        let candidates = applications.filter {
            !$0.isSteamRuntimeHost && $0.storeProvider == nil && $0.storeExternalID == nil
        }
        var changed = false
        for candidate in candidates {
            let executable = URL(fileURLWithPath: candidate.executablePath)
            guard let metadata = await matchStoreMetadata(for: [
                candidate.name,
                executable.deletingPathExtension().lastPathComponent,
                executable.deletingLastPathComponent().lastPathComponent,
            ]),
            let index = applications.firstIndex(where: { $0.id == candidate.id }) else { continue }
            applications[index].name = metadata.name
            applications[index].publisher = metadata.developer ?? applications[index].publisher
            applications[index].storeProvider = metadata.provider
            applications[index].storeExternalID = metadata.externalID
            applications[index].storeMetadataOnly = true
            if !storeGames.contains(where: { $0.provider == metadata.provider && $0.externalID == metadata.externalID }) {
                storeGames.append(metadata)
            }
            changed = true
        }
        if changed { save() }
    }

    nonisolated static func storeSearchTitle(from installerName: String) -> String {
        var value = installerName.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
        if value.lowercased().hasPrefix("setup ") { value.removeFirst("setup ".count) }
        for suffix in [" setup", " installer", " install"] where value.lowercased().hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func beginInstallation(_ candidate: InstallCandidate) {
        guard installationTask == nil else { return }
        let token = UUID()
        installationToken = token
        installationTask = Task { [weak self] in
            guard let self else { return nil }
            let result = await self.install(candidate)
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

    func syncSteamLibrary() {
        guard case .syncing = librarySyncState else {
            librarySyncState = .syncing(.steam)
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
                        if let existing = existingGames[game.externalID] {
                            value.id = existing.id
                            value.compatibility = game.compatibility ?? existing.compatibility
                            value.sizeEstimate = game.sizeEstimate ?? existing.sizeEstimate
                        }
                        return value
                    }
                    storeGames.removeAll { $0.provider == .steam }
                    storeGames.append(contentsOf: normalized)
                    storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    librarySyncState = .succeeded(.steam, count: normalized.count)
                    save()
                } catch {
                    librarySyncState = .failed(.steam, message: error.localizedDescription)
                    present(error, title: "Steam Library couldn’t be imported", stage: "Reading the signed-in Steam library")
                }
            }
            return
        }
    }

    func installSteamWindowsGame(_ game: StoreLibraryGame) {
        let key = storeOperationKey(for: game)
        guard game.provider == .steam,
              game.supportsWindows != false,
              linkedApplication(for: game) == nil,
              storeGameOperations[key] == nil else { return }
        let token = UUID()
        storeOperationTokens[key] = token
        storeGameOperations[key] = .installing(StoreGameOperationProgress(
            message: "Preparing Steam for Windows…",
            fractionCompleted: nil
        ))
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                if let host = steamRuntimeHost() {
                    try await launchSteamInstall(game, using: host)
                } else {
                    let prepared = try await services.steamWindows.prepareClient { [weak self] stage in
                        await self?.updateSteamPreparation(stage, key: key, token: token)
                    }
                    try await registerSteamRuntimeHost(prepared)
                    try await launchSteamInstall(game, steamExecutable: prepared.steamExecutable, environment: prepared.installation.environment, runtime: prepared.installation.runtime)
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
                storeGameOperations[key] = .failed(error.localizedDescription)
                storeOperationTasks[key] = nil
                present(error, title: "\(game.name) couldn’t be prepared", stage: "Installing Valve’s Windows Steam client in Boreal")
            }
        }
        storeOperationTasks[key] = task
    }

    func refreshSteamWindowsGame(_ game: StoreLibraryGame) {
        let key = storeOperationKey(for: game)
        guard game.provider == .steam,
              let host = steamRuntimeHost(),
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
        markSteamGameInstalled(game, installationPath: installation.path)
        storeGameOperations[key] = nil
        storeOperationTasks[key] = nil
        storeOperationTokens[key] = nil
        save()
    }

    private func refreshSteamWindowsGameWithoutApplication(_ game: StoreLibraryGame, key: String) {
        guard game.provider == .steam, let host = steamRuntimeHost(),
              let environmentRecord = environment(id: host.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let installation = SteamWindowsService.installedGameDirectory(appID: game.externalID, in: managed) else {
            storeGameOperations[key] = .awaitingProvider("Steam has not finished installing this game in the Windows Steam bottle yet.")
            return
        }
        let app = steamWindowsApplication(game: game, executable: URL(fileURLWithPath: host.executablePath), environmentID: host.environmentID, status: .ready, graphics: environmentRecord.graphics)
        applications.append(app)
        Task {
            await refreshAuxiliaryExecutables(for: app.id, searchRoot: installation)
            save()
        }
        if let index = applications.firstIndex(where: { $0.id == app.id }) {
            applications[index].storageBytes = GameStorage.allocatedSize(of: installation) ?? 0
        }
        markSteamGameInstalled(game, installationPath: installation.path)
        storeGameOperations[key] = nil
        storeOperationTasks[key] = nil
        storeOperationTokens[key] = nil
        save()
    }

    private func markSteamGameInstalled(_ game: StoreLibraryGame, installationPath: String) {
        guard let index = storeGames.firstIndex(where: { $0.id == game.id }) else { return }
        storeGames[index].isInstalled = true
        storeGames[index].installPath = installationPath
        storeGames[index].installedPlatform = .windows
        storeGames[index].storageBytes = GameStorage.allocatedSize(of: URL(fileURLWithPath: installationPath))
    }

    private func steamRuntimeHost() -> WindowsApplication? {
        applications.first {
            $0.isSteamRuntimeHost
                && FileManager.default.fileExists(atPath: $0.executablePath)
        }
    }

    private func registerSteamRuntimeHost(_ prepared: SteamWindowsClientCommit) async throws {
        let managed = prepared.installation.environment
        let environment = WindowsEnvironment(
            id: managed.id,
            name: "Steam for Windows",
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
            lastResult: "Steam for Windows manages downloads and launch"
        )
        environments.append(environment)
        applications.append(host)
        activeSessions[host.id] = prepared.installation.firstLaunch
        activeEnvironments[host.id] = managed
        activeRuntimes[host.id] = prepared.installation.runtime
        save()
        monitorLauncher(session: prepared.installation.firstLaunch, appID: host.id)
        monitorEnvironmentSession(environment: managed, runtime: prepared.installation.runtime, appID: host.id)
    }

    private func launchSteamInstall(_ game: StoreLibraryGame, using host: WindowsApplication) async throws {
        guard let environmentRecord = environment(id: host.environmentID),
              let managed = managedEnvironment(from: environmentRecord),
              let runtime = try await runtime(for: environmentRecord) else {
            throw InstallerServiceError.noRuntimeAvailable
        }
        try await launchSteamInstall(game, steamExecutable: URL(fileURLWithPath: host.executablePath), environment: managed, runtime: runtime)
    }

    private func launchSteamInstall(_ game: StoreLibraryGame, steamExecutable: URL, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let bootstrap = try await services.processRunner.run(
            plan: SteamWindowsService.bootstrapPlan(steamExecutable: steamExecutable),
            environment: environment,
            runtime: runtime
        )
        Task { _ = try? await services.processRunner.waitForExit(bootstrap) }
        try await Task.sleep(for: .milliseconds(400))
        let plan = SteamWindowsService.protocolPlan("steam://install/\(game.externalID)", steamExecutable: steamExecutable)
        let session = try await services.processRunner.run(plan: plan, environment: environment, runtime: runtime)
        Task { _ = try? await services.processRunner.waitForExit(session) }
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
                epicConnectionState = .failed(error.localizedDescription)
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
                syncEpicLibrary()
            } catch {
                epicConnectionState = .failed(error.localizedDescription)
                present(error, title: "Epic account couldn’t be connected", stage: "Exchanging the one-time authorization code")
            }
        }
    }

    func disconnectEpic() {
        guard !epicConnectionState.isBusy else { return }
        Task {
            do {
                try await services.epicLibrary.disconnect()
                storeGames.removeAll { $0.provider == .epic }
                epicConnectionState = .disconnected
                save()
            } catch {
                epicConnectionState = .failed(error.localizedDescription)
                present(error, title: "Epic account couldn’t be disconnected", stage: "Deleting Legendary account credentials")
            }
        }
    }

    func syncEpicLibrary() {
        guard case .syncing = librarySyncState else {
            librarySyncState = .syncing(.epic)
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
                        if let existing = existingGames[game.externalID] {
                            value.id = existing.id
                            value.developer = value.developer ?? existing.developer
                            value.summary = value.summary ?? existing.summary
                            value.artworkPath = value.artworkPath ?? existing.artworkPath
                            value.portraitImageURL = value.portraitImageURL ?? existing.portraitImageURL
                            value.headerImageURL = value.headerImageURL ?? existing.headerImageURL
                            value.backgroundImageURL = value.backgroundImageURL ?? existing.backgroundImageURL
                            value.screenshotURLs = value.screenshotURLs?.isEmpty == false
                                ? value.screenshotURLs : existing.screenshotURLs
                            value.videos = value.videos?.isEmpty == false ? value.videos : existing.videos
                            value.storeRating = value.storeRating ?? existing.storeRating
                            value.supportsWindows = value.supportsWindows ?? existing.supportsWindows
                            value.supportsNativeMacOS = value.supportsNativeMacOS ?? existing.supportsNativeMacOS
                            value.compatibility = value.compatibility ?? existing.compatibility
                            value.installedPlatform = existing.installedPlatform
                            value.sizeEstimate = value.sizeEstimate ?? existing.sizeEstimate
                        }
                        return value
                    }
                    let enriched = await enrichCompatibility(in: normalized)
                    storeGames.removeAll { $0.provider == .epic }
                    storeGames.append(contentsOf: enriched)
                    storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    librarySyncState = .succeeded(.epic, count: normalized.count)
                    epicConnectionState = await services.epicLibrary.connectionState()
                    save()
                } catch {
                    librarySyncState = .failed(.epic, message: error.localizedDescription)
                    epicConnectionState = await services.epicLibrary.connectionState()
                    present(error, title: "Epic Library couldn’t be imported", stage: "Reading the connected Epic account")
                }
            }
            return
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
                gogConnectionState = .failed(error.localizedDescription)
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
                syncGOGLibrary()
            } catch {
                gogConnectionState = .failed(error.localizedDescription)
                present(error, title: "GOG account couldn’t be connected", stage: "Exchanging the one-time authorization code")
            }
        }
    }

    func disconnectGOG() {
        guard !gogConnectionState.isBusy else { return }
        Task {
            do {
                try await services.gogLibrary.disconnect()
                storeGames.removeAll { $0.provider == .gog }
                gogConnectionState = .disconnected
                save()
            } catch {
                gogConnectionState = .failed(error.localizedDescription)
                present(error, title: "GOG account couldn’t be disconnected", stage: "Deleting local GOG credentials")
            }
        }
    }

    func syncGOGLibrary() {
        guard case .syncing = librarySyncState else {
            librarySyncState = .syncing(.gog)
            Task {
                do {
                    let imported = try await services.gogLibrary.loadLibrary()
                    let existingGames = Dictionary(
                        uniqueKeysWithValues: storeGames.filter { $0.provider == .gog }.map { ($0.externalID, $0) }
                    )
                    let normalized = imported.map { game in
                        var value = game
                        if let existing = existingGames[game.externalID] {
                            value.id = existing.id
                            value.compatibility = value.compatibility ?? existing.compatibility
                            value.installedPlatform = value.installedPlatform ?? existing.installedPlatform
                            value.sizeEstimate = value.sizeEstimate ?? existing.sizeEstimate
                            if !value.isInstalled,
                               existing.isInstalled,
                               let path = existing.installPath,
                               FileManager.default.fileExists(atPath: path) {
                                value.isInstalled = true
                                value.installPath = path
                                value.storageBytes = GameStorage.allocatedSize(of: URL(fileURLWithPath: path, isDirectory: true))
                                    ?? existing.storageBytes
                            }
                        }
                        return value
                    }
                    let enriched = await enrichCompatibility(in: normalized)
                    storeGames.removeAll { $0.provider == .gog }
                    storeGames.append(contentsOf: enriched)
                    storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    librarySyncState = .succeeded(.gog, count: normalized.count)
                    gogConnectionState = await services.gogLibrary.connectionState()
                    save()
                } catch {
                    librarySyncState = .failed(.gog, message: error.localizedDescription)
                    gogConnectionState = await services.gogLibrary.connectionState()
                    present(error, title: "GOG Library couldn’t be imported", stage: "Reading the connected GOG account")
                }
            }
            return
        }
    }

    func syncLibrary(_ provider: GameLibraryProvider) {
        switch provider {
        case .steam: syncSteamLibrary()
        case .epic: syncEpicLibrary()
        case .gog: syncGOGLibrary()
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
            await waitForLibrarySyncToFinish()
            guard !Task.isCancelled else { return }
            syncLibrary(provider)
            await waitForLibrarySyncToFinish()
        }
    }

    private func waitForLibrarySyncToFinish() async {
        while case .syncing = librarySyncState {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func installEpicGame(_ game: StoreLibraryGame) {
        installStoreGame(game)
    }

    func installStoreGame(_ game: StoreLibraryGame, destinationRoot: URL? = nil) {
        let platform: StoreGameInstallationPlatform = game.supportsNativeMacOS == true ? .nativeMacOS : .windows
        startStoreGameInstallation(
            game,
            destinationRoot: destinationRoot ?? defaultGameInstallationRoot(for: game.provider),
            platform: platform
        )
    }

    func addExistingWindowsApp(at selectedURL: URL) {
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
        let architecture = WindowsExecutableArchitecture.inspect(selected)
        let engine: RuntimeEngine = architecture == .x86_64 ? .gamePortingToolkit : .wine
        let environmentArchitecture = architecture == .x86 ? "win32" : "win64"
        installation = InstallationProgress(state: .installing, stage: .preparingRuntime)
        let task = Task<UUID?, Never> { [weak self] in
            guard let self else { return nil }
            var createdEnvironment: ManagedBorealEnvironment?
            do {
                let runtime = try await services.runtimeManager.prepareReadyRuntime(preferredEngine: engine)
                await updateInstallation(.creatingEnvironment)
                let managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: name, architecture: environmentArchitecture),
                    runtime: runtime
                )
                createdEnvironment = managed
                try await services.environmentManager.initialize(managed, runtime: runtime)
                try Task.checkCancellation()
                await updateInstallation(.verifyingFirstLaunch)
                let communityProfile: CommunityCompatibility? = nil
                let environment = WindowsEnvironment(
                    id: managed.id,
                    name: name,
                    architecture: environmentArchitecture == "win64" ? "64-bit" : "32-bit",
                    runtime: runtime.runtimeDescription,
                    graphics: runtime.graphicsName,
                    runtimeID: runtime.id,
                    rootPath: managed.rootURL.path,
                    prefixPath: managed.prefixURL.path,
                    logsPath: managed.logsURL.path
                )
                let app = WindowsApplication(
                    name: name,
                    publisher: "Windows application",
                    executablePath: selected.path,
                    installerPath: "existing-installation",
                    environmentID: managed.id,
                    status: .ready,
                    compatibility: communityProfile?.tier.rating ?? .unknown,
                    graphics: runtime.graphicsName,
                    storageBytes: GameStorage.allocatedSize(of: selected.deletingLastPathComponent()) ?? 0,
                    iconSymbol: symbol(for: name),
                    lastResult: "Existing installation added",
                    communityCompatibility: communityProfile
                )
                environments.append(environment)
                applications.append(app)
                await refreshAuxiliaryExecutables(for: app.id)
                await updateInstallation(.committing)
                save()
                installation.completedStages = Set(InstallationStage.allCases)
                installation.state = .succeeded(app.id)
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
            guard game.supportsNativeMacOS == true,
                  FileManager.default.fileExists(atPath: selected.path) else {
                presentedIssue = BorealIssue(
                    title: "This installation couldn’t be added",
                    stage: "Validating the selected native macOS game.",
                    recovery: "Choose the installed game’s .app bundle.",
                    technicalDetails: selected.path
                )
                return
            }
            guard let index = storeGames.firstIndex(where: { $0.id == game.id }) else { return }
            storeGames[index].isInstalled = true
            storeGames[index].installPath = selected.path
            storeGames[index].installedPlatform = .nativeMacOS
            storeGames[index].storageBytes = GameStorage.allocatedSize(of: selected)
            save()
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
                let runtime = try await services.runtimeManager.prepareReadyRuntime()
                try Task.checkCancellation()
                updateEnvironmentPreparation("Creating an isolated Windows environment…", fraction: 0.4, key: key, token: token)
                var managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: game.name),
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
                    graphics: runtime.graphicsName,
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
                    graphics: runtime.graphicsName,
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
                    if storeGames[index].compatibility == nil { storeGames[index].compatibility = compatibility }
                }
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
            } catch is CancellationError {
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                let diagnostics = await preserveDiagnosticsAndRemoveFailedEnvironment(createdEnvironment)
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(error.localizedDescription)
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
        storeGameOperations[key] = .installing(initialProgress)
        storeDownloadRecords[key] = StoreDownloadRecord(
            provider: game.provider,
            externalID: game.externalID,
            destinationRootPath: destinationRoot.path,
            platform: platform,
            status: .downloading,
            lastProgress: initialProgress,
            samples: previousRecord?.samples
        )
        save()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let update: @Sendable (StoreGameOperationProgress) async -> Void = { [weak self] progress in
                    await self?.updateStoreDownload(progress, key: key, token: token)
                }
                let root = destinationRoot
                let provider = try services.storeProviders.provider(for: game.provider)
                try await provider.install(game, destinationRoot: root, platform: platform, progress: update)
                try Task.checkCancellation()
                guard storeOperationTokens[key] == token else { return }
                if game.provider == .gog,
                   let index = storeGames.firstIndex(where: { $0.id == game.id }) {
                    guard let installationURL = await provider.installationURL(
                        for: game,
                        destinationRoot: root,
                        platform: platform
                    ) else {
                        throw GOGServiceError.installationIncomplete(platform)
                    }
                    storeGames[index].isInstalled = true
                    storeGames[index].installPath = installationURL.path
                    storeGames[index].installedPlatform = platform
                    storeGames[index].storageBytes = GameStorage.allocatedSize(of: installationURL)
                    save()
                }
                if game.provider == .epic,
                   let index = storeGames.firstIndex(where: { $0.id == game.id }) {
                    storeGames[index].installedPlatform = platform
                    save()
                }
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                storeDownloadRecords[key] = nil
                lastDownloadRecordSave[key] = nil
                save()
                syncLibrary(game.provider)
            } catch is CancellationError {
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(error.localizedDescription)
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                if var record = storeDownloadRecords[key] {
                    record.status = .failed
                    record.lastError = error.localizedDescription
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
        guard game.isInstalled,
              capabilities.contains(action.capability),
              storeGameOperations[key] == nil else { return }
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
                let provider = try services.storeProviders.provider(for: game.provider)
                let update: @Sendable (StoreGameOperationProgress) async -> Void = { [weak self] progress in
                    await self?.updateMaintenanceProgress(progress, key: key, token: token)
                }
                switch action {
                case .update:
                    try await provider.update(game, progress: update)
                case .verify:
                    try await provider.verify(game, progress: update)
                }
                try Task.checkCancellation()
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
                syncLibrary(game.provider)
            } catch is CancellationError {
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(error.localizedDescription)
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
              game.isInstalled,
              storeGameOperations[key] == nil else { return }
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
                let provider = try services.storeProviders.provider(for: game.provider)
                try await provider.uninstall(game)
                guard storeOperationTokens[key] == token else { return }
                if let index = storeGames.firstIndex(where: { $0.id == game.id }) {
                    storeGames[index].isInstalled = false
                    storeGames[index].installPath = nil
                    storeGames[index].installedPlatform = nil
                    storeGames[index].storageBytes = nil
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
                storeGameOperations[key] = .failed(error.localizedDescription)
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
              game.isInstalled,
              linkedApplication(for: game) == nil,
              storeGameOperations[key] == nil else { return }
        let token = UUID()
        let selectedEngine = runtimeEngine ?? recommendedRuntimeEngine(for: game)
        storeOperationTokens[key] = token
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
                let runtime = try await services.runtimeManager.prepareReadyRuntime(preferredEngine: selectedEngine)
                try Task.checkCancellation()
                updateEnvironmentPreparation("Creating an isolated Windows environment…", fraction: 0.25, key: key, token: token)
                var managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: game.name),
                    runtime: runtime
                )
                createdEnvironment = managed
                try Task.checkCancellation()
                updateEnvironmentPreparation("Initializing the Wine prefix…", fraction: 0.5, key: key, token: token)
                try await services.environmentManager.initialize(managed, runtime: runtime)
                managed.state = .ready
                try Task.checkCancellation()
                updateEnvironmentPreparation("Validating the game launch task…", fraction: 0.75, key: key, token: token)
                let provider = try services.storeProviders.provider(for: game.provider)
                let plan = try await provider.launchPlan(for: game, runtime: runtime, environment: managed)
                let environment = WindowsEnvironment(
                    id: managed.id,
                    name: game.name,
                    runtime: runtime.runtimeDescription,
                    graphics: runtime.graphicsName,
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
                    installerPath: game.installPath ?? "",
                    environmentID: managed.id,
                    status: .ready,
                    compatibility: resolvedCompatibility?.tier.rating ?? .unknown,
                    graphics: runtime.graphicsName,
                    iconSymbol: "gamecontroller.fill",
                    lastResult: "Ready to launch through \(game.provider.rawValue)",
                    storeProvider: game.provider,
                    storeExternalID: game.externalID,
                    communityCompatibility: resolvedCompatibility
                )
                environments.append(environment)
                applications.append(app)
                await refreshAuxiliaryExecutables(for: app.id)
                if let resolvedCompatibility,
                   let gameIndex = storeGames.firstIndex(where: { $0.id == game.id }),
                   storeGames[gameIndex].compatibility == nil {
                    storeGames[gameIndex].compatibility = resolvedCompatibility
                }
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = nil
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
            } catch is CancellationError {
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                let diagnostics = await preserveDiagnosticsAndRemoveFailedEnvironment(createdEnvironment)
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(error.localizedDescription)
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
                let runtime = rollbackProfile == nil
                    ? try await services.runtimeManager.prepareReadyRuntime(preferredEngine: engine)
                    : try await prepareRuntime(
                        supporting: compatibilityProfile.graphicsBackend,
                        preferredEngine: engine
                    )
                let currentArchitecture = WindowsExecutableArchitecture.inspect(currentExecutable)
                if currentArchitecture == .x86_64, compatibilityProfile.architecture == .win32 {
                    throw RuntimeManagerError.incompatible64BitExecutable
                }
                if currentArchitecture == .x86, compatibilityProfile.architecture == .win64,
                   runtime.features?.wow64 != true {
                    throw RuntimeManagerError.incompatible32BitExecutable(runtime: runtime.displayName)
                }
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

                let storeProvider = try services.storeProviders.provider(for: provider)
                let plan = try await storeProvider.launchPlan(for: game, runtime: runtime, environment: managed)
                guard FileManager.default.fileExists(atPath: plan.executable.path) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let launchArchitecture = WindowsExecutableArchitecture.inspect(plan.executable)
                if launchArchitecture == .x86_64, compatibilityProfile.architecture == .win32 {
                    throw RuntimeManagerError.incompatible64BitExecutable
                }
                if launchArchitecture == .x86, compatibilityProfile.architecture == .win64,
                   runtime.features?.wow64 != true {
                    throw RuntimeManagerError.incompatible32BitExecutable(runtime: runtime.displayName)
                }
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
                    applications[currentIndex].lastErrorDetail = error.localizedDescription
                }
                storeGameOperations[key] = .failed(error.localizedDescription)
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
        preferredEngine: RuntimeEngine
    ) async throws -> InstalledRuntime {
        let installed = try await services.runtimeManager.installedRuntimes()
        if let runtime = installed.first(where: {
            guard $0.resolvedEngine == preferredEngine else { return false }
            switch backend {
            case .d3dMetal: return $0.features?.d3dmetal == true
            case .dxmt: return $0.features?.dxmt == true
            case .dxvk: return $0.features?.dxvk == true
            case .automatic, .wineD3D: return true
            }
        }) {
            return runtime
        }
        guard backend == .automatic || backend == .wineD3D else {
            throw InstallerServiceError.noRuntimeAvailable
        }
        return try await services.runtimeManager.prepareReadyRuntime(preferredEngine: preferredEngine)
    }

    private func steamWindowsApplication(
        game: StoreLibraryGame,
        executable: URL,
        environmentID: UUID,
        status: ApplicationStatus,
        graphics: String
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
            communityCompatibility: game.compatibility
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
        guard let originalData = try? Data(contentsOf: storageURL),
              let data = Self.removingNonProtonCompatibility(from: originalData),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        applications = state.applications
        environments = state.environments
        let persistedGames = state.storeGames ?? []
        storeGames = persistedGames.filter { $0.provider != .gog }
            + GOGReleaseNormalizer.deduplicate(persistedGames.filter { $0.provider == .gog })
        storeDownloadRecords = state.storeDownloads ?? [:]
        favoriteKeys = Set(state.favoriteKeys ?? [])
        lastAutomaticLibraryRefreshAt = state.lastAutomaticLibraryRefreshAt
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
        storeGames.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !storeDownloadRecords.isEmpty { save() }
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
                try await services.processRunner.forceQuitEnvironment(environment: managed, runtime: runtime)
                requestedStops.remove(id)
                unexpectedLauncherFailures.remove(id)
                markEnvironmentEnded(appID: id)
            }
            catch { present(error, title: "The application couldn’t be force quit", stage: "Stopping the Windows environment") }
        }
    }

    private func auxiliarySearchRoot(for application: WindowsApplication) -> URL {
        if let provider = application.storeProvider,
           let externalID = application.storeExternalID,
           let path = storeGames.first(where: {
               $0.provider == provider && $0.externalID == externalID
           })?.installPath {
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
              !applications[index].isSteamRuntimeHost else { return }
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
            $0.auxiliaryExecutables == nil && !$0.isSteamRuntimeHost
        }.map(\.id)
        guard !applicationIDs.isEmpty else { return }
        for applicationID in applicationIDs {
            await refreshAuxiliaryExecutables(for: applicationID)
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

        do {
            guard let environmentRecord = environment(id: application.environmentID),
                  var managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await runtime(for: environmentRecord) else {
                throw InstallerServiceError.noRuntimeAvailable
            }
            managed.configuration = EnvironmentConfiguration(
                name: environmentRecord.name,
                profile: application.resolvedCompatibilityProfile
            )
            try await services.environmentManager.configure(managed, runtime: runtime)
            let session = try await services.processRunner.run(
                plan: WindowsLaunchPlan(
                    executable: executable,
                    arguments: [],
                    environment: [:],
                    workingDirectory: executable.deletingLastPathComponent()
                ),
                environment: managed,
                runtime: runtime
            )
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

    private func toggleRunningAsync(_ id: UUID) async {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        if applications[index].status == .running {
            requestedStops.insert(id)
            var stopError: Error?
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
            if activeSessions[id] == nil && activeEnvironments[id] == nil {
                markEnvironmentEnded(appID: id)
            } else if let stopError {
                requestedStops.remove(id)
                present(stopError, title: "\(applications[index].name) couldn’t stop", stage: "Requesting a normal application exit")
            }
            return
        }
        guard !applications[index].status.isBusy else { return }
        let usesExistingExecutable = applications[index].installerPath == "existing-installation"
            || applications[index].usesStoreMetadataOnly
        let refreshesExecutableAtLaunch = !usesExistingExecutable && [.epic, .gog].contains(applications[index].storeProvider) && applications[index].storeExternalID != nil
        guard refreshesExecutableAtLaunch || FileManager.default.fileExists(atPath: applications[index].executablePath) else {
            applications[index].status = .unavailable
            applications[index].lastResult = "Executable unavailable"
            applications[index].lastFailureStage = "Checking application files"
            applications[index].lastErrorDetail = "The configured executable no longer exists at \(applications[index].executablePath)."
            save()
            presentedIssue = BorealIssue(
                title: "\(applications[index].name) is unavailable",
                stage: "Boreal couldn’t find the configured application executable.",
                recovery: "Reinstall the application to create a complete environment.",
                technicalDetails: applications[index].executablePath
            )
            return
        }
        applications[index].status = .preparing
        applications[index].lastErrorDetail = nil
        applications[index].lastFailureStage = nil
        do {
            guard let environmentRecord = environment(id: applications[index].environmentID),
                  var managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await services.runtimeManager.installedRuntimes().first(where: { $0.id == environmentRecord.runtimeID }) else {
                throw InstallerServiceError.noRuntimeAvailable
            }
            var profile = compatibilityProfile(for: applications[index])
            if profile.graphicsAPI == nil {
                let executable = URL(fileURLWithPath: applications[index].executablePath)
                profile.graphicsAPI = await Task.detached(priority: .utility) {
                    GraphicsAPIDetector.detect(executable: executable)
                }.value
            }
            let graphicsProfile = GameGraphicsProfiles.profile(for: applications[index])
            let selectedGraphicsAPI = profile.graphicsAPI ?? graphicsProfile?.defaultAPI ?? .automatic
            let graphicsLaunchOption = selectedGraphicsAPI == .automatic ? nil : graphicsProfile?.launchOption(for: selectedGraphicsAPI)
            managed.configuration = EnvironmentConfiguration(name: environmentRecord.name, profile: profile)
            try await services.environmentManager.configure(managed, runtime: runtime)
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
                    let bootstrap = try await services.processRunner.run(
                        plan: SteamWindowsService.bootstrapPlan(steamExecutable: executable),
                        environment: managed,
                        runtime: runtime
                    )
                    Task { _ = try? await services.processRunner.waitForExit(bootstrap) }
                    try await Task.sleep(for: .milliseconds(400))
                    plan = SteamWindowsService.playPlan(appID: appID, steamExecutable: executable)
                case .epic, .gog:
                    guard let game = storeGames.first(where: { $0.provider == provider && $0.externalID == appID }) else {
                        throw GameStoreProviderError.installationMissing(provider)
                    }
                    let storeProvider = try services.storeProviders.provider(for: provider)
                    plan = try await storeProvider.launchPlan(for: game, runtime: runtime, environment: managed)
                }
                applications[index].executablePath = plan.executable.path
                var configuredPlan = GameGraphicsProfiles.applying(
                    graphicsLaunchOption,
                    to: plan,
                    gameDirectory: gameDirectory
                )
                configuredPlan.arguments.append(contentsOf: profile.parsedLaunchArguments)
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
                session = try await services.processRunner.run(plan: configuredPlan, environment: managed, runtime: runtime)
            } else {
                let executable = URL(fileURLWithPath: applications[index].executablePath)
                var configuredPlan = GameGraphicsProfiles.applying(
                    graphicsLaunchOption,
                    to: WindowsLaunchPlan(
                        executable: executable,
                        arguments: [],
                        environment: [:],
                        workingDirectory: executable.deletingLastPathComponent()
                    )
                )
                configuredPlan.arguments.append(contentsOf: profile.parsedLaunchArguments)
                let graphicsPlan = try graphicsCompatibilityManager.apply(
                    configuration: profile,
                    application: applications[index],
                    executable: configuredPlan.executable,
                    environment: managed,
                    runtime: runtime
                )
                configuredPlan = graphicsCompatibilityManager.applying(graphicsPlan, to: configuredPlan)
                session = try await services.processRunner.run(plan: configuredPlan, environment: managed, runtime: runtime)
            }
            applications[index].status = .running
            applications[index].lastOpened = .now
            activeSessions[id] = session
            ControllerManager.shared.activate(for: id)
            performanceLogURLs[id] = session.stderrLog
            activeEnvironments[id] = managed
            activeRuntimes[id] = runtime
            save()
            monitorLauncher(session: session, appID: id)
            monitorEnvironmentSession(environment: managed, runtime: runtime, appID: id)
        } catch {
            applications[index].status = .needsAttention
            applications[index].lastResult = "Couldn’t open"
            applications[index].lastFailureStage = "Starting application"
            applications[index].lastErrorDetail = error.localizedDescription
            save()
            present(error, title: "\(applications[index].name) couldn’t open", stage: "Boreal was preparing or starting the application.", retryApplicationID: id)
        }
    }

    private func removeApplicationAndEnvironment(_ id: UUID) async {
        guard let app = application(id: id) else { return }
        do {
            if let environment = activeEnvironments[id], let runtime = activeRuntimes[id] {
                try? await services.processRunner.forceQuitEnvironment(environment: environment, runtime: runtime)
            }
            let hasOtherApps = applications.contains { $0.id != id && $0.environmentID == app.environmentID }
            if !hasOtherApps, let record = environment(id: app.environmentID), let managed = managedEnvironment(from: record) {
                try await services.environmentManager.remove(managed)
            }
            applications.removeAll { $0.id == id }
            ControllerManager.shared.deactivate(for: id)
            if !hasOtherApps { environments.removeAll { $0.id == app.environmentID } }
            activeSessions[id] = nil
            performanceLogURLs[id] = nil
            activeEnvironments[id] = nil
            activeRuntimes[id] = nil
            environmentSessionStates[app.environmentID] = nil
            environmentMonitorIDs[id] = nil
            save()
        } catch { present(error, title: "The application couldn’t be removed", stage: "Removing application and environment data") }
    }

    private func managedEnvironment(from record: WindowsEnvironment) -> ManagedBorealEnvironment? {
        guard let runtimeID = record.runtimeID, let root = record.rootPath, let prefix = record.prefixPath, let logs = record.logsPath else { return nil }
        return ManagedBorealEnvironment(id: record.id, configuration: EnvironmentConfiguration(name: record.name, windowsVersion: "win11", architecture: record.architecture == "64-bit" ? "win64" : "win32"), runtimeID: runtimeID, rootURL: URL(fileURLWithPath: root), prefixURL: URL(fileURLWithPath: prefix), logsURL: URL(fileURLWithPath: logs), state: .ready)
    }

    private func monitorLauncher(session: WindowsProcessSession, appID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let result = try? await services.processRunner.waitForExit(session)
            guard let index = applications.firstIndex(where: { $0.id == appID }) else { return }
            let wasRequested = requestedStops.contains(appID)
            if let result, result.exitCode != 0, !wasRequested {
                unexpectedLauncherFailures.insert(appID)
                applications[index].lastResult = "Exited unexpectedly"
                applications[index].lastExitCode = result.exitCode
                applications[index].lastFailureStage = "Running application"
                applications[index].lastErrorDetail = "The application process exited with code \(result.exitCode)."
            } else {
                applications[index].lastResult = wasRequested ? "Launcher stopped" : "Launcher exited normally"
                applications[index].lastExitCode = result?.exitCode
            }
            activeSessions[appID] = nil
            save()
        }
    }

    private func monitorEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime, appID: UUID) {
        let monitorID = UUID()
        environmentMonitorIDs[appID] = monitorID
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                guard environmentMonitorIDs[appID] == monitorID else { return }
                switch await services.processRunner.environmentSessionState(environment: environment, runtime: runtime) {
                case .active:
                    environmentSessionStates[environment.id] = .active
                    do {
                        try await services.processRunner.waitForEnvironmentSessionEnd(environment: environment, runtime: runtime)
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
            switch await services.processRunner.environmentSessionState(environment: managed, runtime: installedRuntime) {
            case .active:
                environmentSessionStates[managed.id] = .active
                if let index = applications.firstIndex(where: { $0.id == appID }) { applications[index].status = .running }
                ControllerManager.shared.activate(for: appID)
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

    private func markEnvironmentEnded(appID: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == appID }) else { return }
        let environmentID = applications[index].environmentID
        let wasRequested = requestedStops.remove(appID) != nil
        if unexpectedLauncherFailures.remove(appID) != nil && !wasRequested {
            applications[index].status = .needsAttention
        } else {
            applications[index].status = .ready
            if wasRequested { applications[index].lastResult = "Stopped" }
        }
        environmentSessionStates[environmentID] = .inactive
        activeSessions[appID] = nil
        performanceLogURLs[appID] = nil
        activeEnvironments[appID] = nil
        activeRuntimes[appID] = nil
        ControllerManager.shared.deactivate(for: appID)
        environmentMonitorIDs[appID] = nil
        save()
    }

    private func markEnvironmentUnknown(appID: UUID, detail: String) {
        guard let index = applications.firstIndex(where: { $0.id == appID }) else { return }
        applications[index].status = .needsAttention
        applications[index].lastErrorDetail = detail
        environmentSessionStates[applications[index].environmentID] = .unknown
        environmentMonitorIDs[appID] = nil
        save()
    }

    private func save() {
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
                    engine: runtime.features.d3dmetal ? .gamePortingToolkit : .wine,
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
            let key = update.component == .dxvk ? "automaticDXVKUpdates" : "automaticVKD3DUpdates"
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
        storageURL.deletingLastPathComponent()
            .appending(path: "Games/\(provider == .epic ? "Epic" : provider.rawValue)", directoryHint: .isDirectory)
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
        presentedIssue = BorealIssue(
            title: title,
            stage: stage,
            recovery: "Try again. If the problem continues, open Details for technical information.",
            technicalDetails: diagnostics?.technicalDetails(for: error) ?? error.localizedDescription,
            retryApplicationID: retryApplicationID
        )
    }
}
