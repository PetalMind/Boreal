import Foundation
import Observation

@MainActor
@Observable
final class BorealStore {
    private struct PersistedState: Codable {
        var applications: [WindowsApplication]
        var environments: [WindowsEnvironment]
        var storeGames: [StoreLibraryGame]?
    }

    var applications: [WindowsApplication] = []
    var environments: [WindowsEnvironment] = []
    var storeGames: [StoreLibraryGame] = []
    var librarySyncState: LibrarySyncState = .idle
    var epicConnectionState: EpicConnectionState = .checking
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
    private var activeEnvironments: [UUID: ManagedBorealEnvironment] = [:]
    private var activeRuntimes: [UUID: InstalledRuntime] = [:]
    private var requestedStops: Set<UUID> = []
    private var unexpectedLauncherFailures: Set<UUID> = []
    private var environmentSessionStates: [UUID: EnvironmentSessionState] = [:]
    private var environmentMonitorIDs: [UUID: UUID] = [:]

    init(storageURL: URL? = nil, services: BorealServices? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageURL = storageURL ?? base.appending(path: "Boreal/library.json")
        self.services = services ?? .live(applicationSupportURL: (storageURL?.deletingLastPathComponent() ?? base.appending(path: "Boreal")))
        load()
        for index in applications.indices where applications[index].status != .running && !FileManager.default.fileExists(atPath: applications[index].executablePath) {
            applications[index].status = .unavailable
            applications[index].lastResult = "Executable unavailable"
            applications[index].lastFailureStage = "Checking application files"
            applications[index].lastErrorDetail = "The configured executable no longer exists at \(applications[index].executablePath)."
        }
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
    func linkedApplication(for game: StoreLibraryGame) -> WindowsApplication? {
        applications.first { $0.storeProvider == game.provider && $0.storeExternalID == game.externalID }
    }
    func environment(id: UUID) -> WindowsEnvironment? { environments.first { $0.id == id } }
    func applications(in environmentID: UUID) -> [WindowsApplication] { applications.filter { $0.environmentID == environmentID } }

    func install(_ candidate: InstallCandidate) async -> UUID? {
        installation = InstallationProgress(state: .installing, stage: .preparingRuntime)
        do {
            let commit = try await services.installer.install(candidate.url, name: candidate.name) { [weak self] stage in
                await self?.updateInstallation(stage)
            }
            let managed = commit.environment
            let environment = WindowsEnvironment(
                id: managed.id,
                name: managed.configuration.name,
                windowsVersion: "Windows 11",
                architecture: managed.configuration.architecture == "win64" ? "64-bit" : "32-bit",
                runtime: "\(commit.runtime.displayName) · Wine \(commit.runtime.wineVersion)",
                graphics: "WineD3D",
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
                compatibility: .unknown,
                graphics: "WineD3D",
                lastOpened: .now,
                iconSymbol: symbol(for: candidate.name),
                lastResult: "First launch verified"
            )
            environments.append(environment)
            applications.append(app)
            activeSessions[app.id] = commit.firstLaunch
            activeEnvironments[app.id] = managed
            activeRuntimes[app.id] = commit.runtime
            save()
            installation.completedStages = Set(InstallationStage.allCases)
            installation.state = .succeeded(app.id)
            monitorLauncher(session: commit.firstLaunch, appID: app.id)
            monitorEnvironmentSession(environment: managed, runtime: commit.runtime, appID: app.id)
            await refreshRuntimeStatuses()
            return app.id
        } catch {
            installation.state = .failed
            installation.failureMessage = error.localizedDescription
            installation.rollbackCompleted = installation.stage != .preparingRuntime
            return nil
        }
    }

    func resetInstallation() { installation = InstallationProgress() }

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
                        if let existing = existingGames[game.externalID] { value.id = existing.id }
                        return value
                    }
                    storeGames.removeAll { $0.provider == .epic }
                    storeGames.append(contentsOf: normalized)
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

    func installEpicGame(_ game: StoreLibraryGame) {
        guard game.provider == .epic, storeGameOperations[game.externalID] == nil else { return }
        storeGameOperations[game.externalID] = .installing
        Task {
            do {
                try await services.epicLibrary.install(appID: game.externalID)
                storeGameOperations[game.externalID] = nil
                syncEpicLibrary()
            } catch {
                storeGameOperations[game.externalID] = .failed(error.localizedDescription)
                present(error, title: "\(game.name) couldn’t be installed", stage: "Downloading the Windows build from Epic")
            }
        }
    }

    func clearStoreGameOperation(for externalID: String) {
        storeGameOperations[externalID] = nil
    }

    func prepareEpicGame(_ game: StoreLibraryGame) {
        guard game.provider == .epic,
              game.isInstalled,
              linkedApplication(for: game) == nil,
              storeGameOperations[game.externalID] == nil else { return }
        storeGameOperations[game.externalID] = .preparingEnvironment
        Task {
            var createdEnvironment: ManagedBorealEnvironment?
            do {
                var selectedRuntime: InstalledRuntime?
                for candidate in try await services.runtimeManager.installedRuntimes() {
                    if (try? await services.runtimeManager.validate(candidate).isReady) == true {
                        selectedRuntime = candidate
                        break
                    }
                }
                guard let runtime = selectedRuntime else { throw InstallerServiceError.noRuntimeAvailable }
                var managed = try await services.environmentManager.create(
                    configuration: EnvironmentConfiguration(name: game.name),
                    runtime: runtime
                )
                createdEnvironment = managed
                try await services.environmentManager.initialize(managed, runtime: runtime)
                managed.state = .ready
                let plan = try await services.epicLibrary.launchPlan(appID: game.externalID, runtime: runtime, environment: managed)
                let environment = WindowsEnvironment(
                    id: managed.id,
                    name: game.name,
                    runtime: "\(runtime.displayName) · Wine \(runtime.wineVersion)",
                    graphics: "WineD3D",
                    runtimeID: runtime.id,
                    rootPath: managed.rootURL.path,
                    prefixPath: managed.prefixURL.path,
                    logsPath: managed.logsURL.path
                )
                let app = WindowsApplication(
                    name: game.name,
                    publisher: game.developer ?? game.provider.rawValue,
                    executablePath: plan.executable.path,
                    installerPath: game.installPath ?? "",
                    environmentID: managed.id,
                    status: .ready,
                    compatibility: game.compatibility?.tier.rating ?? .unknown,
                    graphics: "WineD3D",
                    iconSymbol: "gamecontroller.fill",
                    lastResult: "Ready to launch through Epic",
                    storeProvider: .epic,
                    storeExternalID: game.externalID
                )
                environments.append(environment)
                applications.append(app)
                storeGameOperations[game.externalID] = nil
                save()
            } catch {
                if let createdEnvironment { try? await services.environmentManager.remove(createdEnvironment) }
                storeGameOperations[game.externalID] = .failed(error.localizedDescription)
                present(error, title: "\(game.name) couldn’t be prepared", stage: "Creating its isolated Windows environment")
            }
        }
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
                environments.append(WindowsEnvironment(id: managed.id, name: name, runtime: "\(runtime.displayName) · Wine \(runtime.wineVersion)", graphics: "WineD3D", runtimeID: runtime.id, rootPath: managed.rootURL.path, prefixPath: managed.prefixURL.path, logsPath: managed.logsURL.path))
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
        guard let data = try? Data(contentsOf: storageURL), let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        applications = state.applications
        environments = state.environments
        storeGames = state.storeGames ?? []
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
            do {
                if let session = activeSessions[id] {
                    try await services.processRunner.stopApplication(session)
                } else if let environment = activeEnvironments[id], let runtime = activeRuntimes[id] {
                    try await services.processRunner.terminateEnvironmentSession(environment: environment, runtime: runtime)
                }
            }
            catch {
                requestedStops.remove(id)
                present(error, title: "\(applications[index].name) couldn’t stop", stage: "Requesting a normal application exit")
            }
            return
        }
        guard !applications[index].status.isBusy else { return }
        let refreshesExecutableAtLaunch = applications[index].storeProvider == .epic && applications[index].storeExternalID != nil
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
            if applications[index].storeProvider == .epic, let appID = applications[index].storeExternalID {
                let plan = try await services.epicLibrary.launchPlan(appID: appID, runtime: runtime, environment: managed)
                applications[index].executablePath = plan.executable.path
                session = try await services.processRunner.run(plan: plan, environment: managed, runtime: runtime)
            } else {
                session = try await services.processRunner.run(executable: URL(fileURLWithPath: applications[index].executablePath), arguments: [], environment: managed, runtime: runtime)
            }
            applications[index].status = .running
            applications[index].lastOpened = .now
            activeSessions[id] = session
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
            let data = try JSONEncoder().encode(PersistedState(applications: applications, environments: environments, storeGames: storeGames))
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
                    origin: runtime.origin
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
                    source: .catalog
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
