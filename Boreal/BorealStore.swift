import Foundation
import Observation

@MainActor
@Observable
final class BorealStore {
    private struct PersistedState: Codable {
        var applications: [WindowsApplication]
        var environments: [WindowsEnvironment]
    }

    var applications: [WindowsApplication] = []
    var environments: [WindowsEnvironment] = []
    var installProgress: Double?
    var installStage = ""
    var errorMessage: String?
    private let storageURL: URL
    private let services: BorealServices
    private var activeSessions: [UUID: WindowsProcessSession] = [:]
    private var activeEnvironments: [UUID: ManagedBorealEnvironment] = [:]
    private var activeRuntimes: [UUID: InstalledRuntime] = [:]

    init(storageURL: URL? = nil, services: BorealServices? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageURL = storageURL ?? base.appending(path: "Boreal/library.json")
        self.services = services ?? .live(applicationSupportURL: (storageURL?.deletingLastPathComponent() ?? base.appending(path: "Boreal")))
        load()
        for index in applications.indices where applications[index].status == .running { applications[index].status = .ready }
    }

    func application(id: UUID) -> WindowsApplication? { applications.first { $0.id == id } }
    func environment(id: UUID) -> WindowsEnvironment? { environments.first { $0.id == id } }
    func applications(in environmentID: UUID) -> [WindowsApplication] { applications.filter { $0.environmentID == environmentID } }

    func install(_ candidate: InstallCandidate) async -> UUID? {
        installProgress = 0.05
        installStage = "Finding a verified Boreal Runtime…"
        do {
            let commit = try await services.installer.install(candidate.url, name: candidate.name)
            installProgress = 0.9
            installStage = "Committing the successful first launch…"
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
                iconSymbol: symbol(for: candidate.name)
            )
            environments.append(environment)
            applications.append(app)
            activeSessions[app.id] = commit.firstLaunch
            activeEnvironments[app.id] = managed
            activeRuntimes[app.id] = commit.runtime
            save()
            installProgress = 1
            installStage = "Running"
            monitor(session: commit.firstLaunch, appID: app.id)
            try? await Task.sleep(for: .milliseconds(200))
            installProgress = nil
            return app.id
        } catch {
            installProgress = nil
            errorMessage = error.localizedDescription
            return nil
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
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func removeEnvironment(_ id: UUID) {
        Task {
            guard applications(in: id).isEmpty else {
                errorMessage = "Remove the apps in this environment first."
                return
            }
            do {
                if let record = environment(id: id), let managed = managedEnvironment(from: record) { try await services.environmentManager.remove(managed) }
                environments.removeAll { $0.id == id }
                save()
            } catch { errorMessage = error.localizedDescription }
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
    }

    func forceQuit(_ id: UUID) {
        Task {
            guard let session = activeSessions[id], let environment = activeEnvironments[id], let runtime = activeRuntimes[id] else { return }
            do { try await services.processRunner.forceQuit(session, environment: environment, runtime: runtime) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func toggleRunningAsync(_ id: UUID) async {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        if applications[index].status == .running {
            guard let session = activeSessions[id], let environment = activeEnvironments[id], let runtime = activeRuntimes[id] else { return }
            do { try await services.processRunner.stop(session, environment: environment, runtime: runtime) }
            catch { errorMessage = error.localizedDescription }
            return
        }
        do {
            guard let environmentRecord = environment(id: applications[index].environmentID),
                  let managed = managedEnvironment(from: environmentRecord),
                  let runtime = try await services.runtimeManager.installedRuntimes().first(where: { $0.id == environmentRecord.runtimeID }) else {
                throw InstallerServiceError.noRuntimeAvailable
            }
            let session = try await services.processRunner.run(executable: URL(fileURLWithPath: applications[index].executablePath), arguments: [], environment: managed, runtime: runtime)
            applications[index].status = .running
            applications[index].lastOpened = .now
            activeSessions[id] = session
            activeEnvironments[id] = managed
            activeRuntimes[id] = runtime
            save()
            monitor(session: session, appID: id)
        } catch { errorMessage = error.localizedDescription }
    }

    private func removeApplicationAndEnvironment(_ id: UUID) async {
        guard let app = application(id: id) else { return }
        do {
            if let session = activeSessions[id], let environment = activeEnvironments[id], let runtime = activeRuntimes[id] {
                try? await services.processRunner.forceQuit(session, environment: environment, runtime: runtime)
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
            save()
        } catch { errorMessage = error.localizedDescription }
    }

    private func managedEnvironment(from record: WindowsEnvironment) -> ManagedBorealEnvironment? {
        guard let runtimeID = record.runtimeID, let root = record.rootPath, let prefix = record.prefixPath, let logs = record.logsPath else { return nil }
        return ManagedBorealEnvironment(id: record.id, configuration: EnvironmentConfiguration(name: record.name, windowsVersion: "win11", architecture: record.architecture == "64-bit" ? "win64" : "win32"), runtimeID: runtimeID, rootURL: URL(fileURLWithPath: root), prefixURL: URL(fileURLWithPath: prefix), logsURL: URL(fileURLWithPath: logs), state: .ready)
    }

    private func monitor(session: WindowsProcessSession, appID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await services.processRunner.waitForExit(session)
            guard let index = applications.firstIndex(where: { $0.id == appID }) else { return }
            applications[index].status = .ready
            activeSessions[appID] = nil
            activeEnvironments[appID] = nil
            activeRuntimes[appID] = nil
            save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(PersistedState(applications: applications, environments: environments))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            errorMessage = "Boreal couldn’t save your Library. \(error.localizedDescription)"
        }
    }
}
