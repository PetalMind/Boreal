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
    private let storageURL: URL
    private let services: BorealServices
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
        Task { await refreshRuntimeStatuses() }
    }

    func application(id: UUID) -> WindowsApplication? { applications.first { $0.id == id } }
    func storeGame(id: UUID) -> StoreLibraryGame? { storeGames.first { $0.id == id } }
    func isFavorite(key: String) -> Bool { favoriteKeys.contains(key) }

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
            switch game.provider {
            case .gog:
                estimate = try await services.gogLibrary.loadSizeEstimate(appID: game.externalID, platform: platform)
            case .epic:
                estimate = try await services.epicLibrary.loadSizeEstimate(appID: game.externalID, platform: platform)
            case .steam:
                estimate = await services.steamLibrary.loadDetails(for: game).sizeEstimate
            }
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
            let app = WindowsApplication(
                name: candidate.name,
                publisher: "Windows application",
                executablePath: commit.executable.path,
                installerPath: candidate.url.path,
                environmentID: environment.id,
                status: .running,
                compatibility: communityProfile?.tier.rating ?? .unknown,
                graphics: commit.runtime.graphicsName,
                lastOpened: .now,
                iconSymbol: symbol(for: candidate.name),
                lastResult: "First launch verified",
                communityCompatibility: communityProfile
            )
            environments.append(environment)
            applications.append(app)
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
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                installation.state = .failed
                installation.failureMessage = error.localizedDescription
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
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(error.localizedDescription)
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                present(error, title: "\(game.name) couldn’t be added", stage: "Preparing the existing Windows installation")
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
                switch game.provider {
                case .epic: try await services.epicLibrary.install(appID: game.externalID, destinationRoot: root, platform: platform, progress: update)
                case .gog: try await services.gogLibrary.install(appID: game.externalID, destinationRoot: root, platform: platform, progress: update)
                case .steam: return
                }
                try Task.checkCancellation()
                guard storeOperationTokens[key] == token else { return }
                if game.provider == .gog,
                   let index = storeGames.firstIndex(where: { $0.id == game.id }) {
                    guard let installationURL = await services.gogLibrary.installationURL(
                        appID: game.externalID,
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
                switch game.provider {
                case .epic:
                    try await services.epicLibrary.uninstall(appID: game.externalID)
                case .gog:
                    guard let path = game.installPath else { throw CocoaError(.fileNoSuchFile) }
                    let installationURL = URL(fileURLWithPath: path).standardizedFileURL
                    guard FileManager.default.fileExists(atPath: installationURL.path) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    _ = try FileManager.default.trashItem(at: installationURL, resultingItemURL: nil)
                case .steam:
                    return
                }
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
                let plan: WindowsLaunchPlan
                switch game.provider {
                case .epic: plan = try await services.epicLibrary.launchPlan(appID: game.externalID, runtime: runtime, environment: managed)
                case .gog:
                    let installationURL = game.installPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                        ?? defaultGameInstallationRoot(for: .gog).appending(path: game.externalID, directoryHint: .isDirectory)
                    plan = try await services.gogLibrary.launchPlan(
                        appID: game.externalID,
                        installationURL: installationURL,
                        runtime: runtime,
                        environment: managed
                    )
                case .steam: return
                }
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
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                guard storeOperationTokens[key] == token else { return }
                storeGameOperations[key] = .failed(error.localizedDescription)
                storeOperationTasks[key] = nil
                present(error, title: "\(game.name) couldn’t be prepared", stage: "Creating its isolated Windows environment")
            }
        }
        storeOperationTasks[key] = task
    }

    func recreateEnvironment(_ applicationID: UUID, with engine: RuntimeEngine, launchWhenReady: Bool = false) {
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
                let runtime = try await services.runtimeManager.prepareReadyRuntime(preferredEngine: engine)
                try Task.checkCancellation()
                updateEnvironmentPreparation("Creating a new isolated prefix…", fraction: 0.3, key: key, token: token)
                var managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: game.name),
                    runtime: runtime
                )
                replacement = managed
                try await services.environmentManager.initialize(managed, runtime: runtime)
                managed.state = .ready
                try Task.checkCancellation()
                updateEnvironmentPreparation("Validating the game launch plan…", fraction: 0.75, key: key, token: token)

                let plan: WindowsLaunchPlan
                switch provider {
                case .epic:
                    plan = try await services.epicLibrary.launchPlan(appID: externalID, runtime: runtime, environment: managed)
                case .gog:
                    let installationURL = game.installPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                        ?? defaultGameInstallationRoot(for: .gog).appending(path: externalID, directoryHint: .isDirectory)
                    plan = try await services.gogLibrary.launchPlan(
                        appID: externalID,
                        installationURL: installationURL,
                        runtime: runtime,
                        environment: managed
                    )
                case .steam:
                    return
                }
                guard FileManager.default.fileExists(atPath: plan.executable.path) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                if WindowsExecutableArchitecture.inspect(plan.executable) == .x86,
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
                    runtime: runtime.runtimeDescription,
                    graphics: runtime.graphicsName,
                    runtimeID: runtime.id,
                    rootPath: managed.rootURL.path,
                    prefixPath: managed.prefixURL.path,
                    logsPath: managed.logsURL.path
                ))
                applications[currentIndex].environmentID = managed.id
                applications[currentIndex].executablePath = plan.executable.path
                applications[currentIndex].graphics = runtime.graphicsName
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
                    applications[currentIndex].status = previousStatus
                    applications[currentIndex].lastResult = "Environment migration cancelled"
                }
                finishCancelledStoreOperation(key: key, token: token)
            } catch {
                if let replacement { try? await services.environmentManager.remove(replacement) }
                guard storeOperationTokens[key] == token else { return }
                if let currentIndex = applications.firstIndex(where: { $0.id == applicationID }) {
                    applications[currentIndex].status = previousStatus
                    applications[currentIndex].lastResult = "Environment migration failed"
                    applications[currentIndex].lastFailureStage = "Recreating environment"
                    applications[currentIndex].lastErrorDetail = error.localizedDescription
                }
                storeGameOperations[key] = .failed(error.localizedDescription)
                storeOperationTasks[key] = nil
                storeOperationTokens[key] = nil
                save()
                present(error, title: "\(game.name) couldn’t switch runtime", stage: "Creating and validating a new \(engine.displayName) environment")
            }
        }
        storeOperationTasks[key] = task
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
                  let managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await services.runtimeManager.installedRuntimes().first(where: { $0.id == environmentRecord.runtimeID }) else {
                throw InstallerServiceError.noRuntimeAvailable
            }
            applications[index].status = .starting
            let session: WindowsProcessSession
            if !usesExistingExecutable,
               let provider = applications[index].storeProvider,
               [.steam, .epic, .gog].contains(provider),
               let appID = applications[index].storeExternalID {
                let plan: WindowsLaunchPlan
                switch provider {
                case .steam:
                    let executable = URL(fileURLWithPath: applications[index].executablePath)
                    guard SteamWindowsService.installedGameDirectory(appID: appID, in: managed) != nil else {
                        throw SteamWindowsError.gameNotInstalled(appID)
                    }
                    let bootstrap = try await services.processRunner.run(
                        plan: SteamWindowsService.bootstrapPlan(steamExecutable: executable),
                        environment: managed,
                        runtime: runtime
                    )
                    Task { _ = try? await services.processRunner.waitForExit(bootstrap) }
                    try await Task.sleep(for: .milliseconds(400))
                    plan = SteamWindowsService.playPlan(appID: appID, steamExecutable: executable)
                case .epic: plan = try await services.epicLibrary.launchPlan(appID: appID, runtime: runtime, environment: managed)
                case .gog: plan = try await services.gogLibrary.launchPlan(appID: appID, runtime: runtime, environment: managed)
                }
                applications[index].executablePath = plan.executable.path
                session = try await services.processRunner.run(plan: plan, environment: managed, runtime: runtime)
            } else {
                session = try await services.processRunner.run(executable: URL(fileURLWithPath: applications[index].executablePath), arguments: [], environment: managed, runtime: runtime)
            }
            applications[index].status = .running
            applications[index].lastOpened = .now
            activeSessions[id] = session
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
                favoriteKeys: Array(favoriteKeys).sorted()
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
        } catch {
            runtimeStatuses = []
            localRuntimeCandidates = await services.runtimeManager.localRuntimeCandidates()
            runtimeDiscoveryState = .failed(runtimeCatalogDetails(error: error))
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

    private func present(_ error: Error, title: String, stage: String, retryApplicationID: UUID? = nil) {
        presentedIssue = BorealIssue(
            title: title,
            stage: stage,
            recovery: "Try again. If the problem continues, open Details for technical information.",
            technicalDetails: error.localizedDescription,
            retryApplicationID: retryApplicationID
        )
    }
}
