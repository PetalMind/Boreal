import Foundation
import Testing
@testable import Boreal

struct P0SessionRecoveryTests {
    @Test func environmentProbeIsBoundedAndDoesNotAlterActiveSession() async throws {
        let fixture = try SessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let executor = SystemProcessExecutor()
        let runner = WindowsProcessRunner(processExecutor: executor, probeObservationWindow: .milliseconds(100))

        try Data().write(to: fixture.activeMarker)
        #expect(await runner.environmentSessionState(environment: fixture.environment, runtime: fixture.runtime) == .active)
        #expect(FileManager.default.fileExists(atPath: fixture.activeMarker.path))
        #expect(await runner.environmentSessionState(environment: fixture.environment, runtime: fixture.runtime) == .active)
        #expect(FileManager.default.fileExists(atPath: fixture.activeMarker.path))

        try await runner.forceQuitEnvironment(environment: fixture.environment, runtime: fixture.runtime)
        #expect(await runner.environmentSessionState(environment: fixture.environment, runtime: fixture.runtime) == .inactive)
    }

    @Test func environmentWaitCompletesOnlyAfterSessionEnds() async throws {
        let fixture = try SessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = WindowsProcessRunner(processExecutor: SystemProcessExecutor(), probeObservationWindow: .milliseconds(50))
        let completion = CompletionFlag()

        try Data().write(to: fixture.activeMarker)
        let waiter = Task {
            try await runner.waitForEnvironmentSessionEnd(environment: fixture.environment, runtime: fixture.runtime)
            await completion.markComplete()
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(await completion.isComplete == false)
        try FileManager.default.removeItem(at: fixture.activeMarker)
        try await waiter.value
        #expect(await completion.isComplete)
    }

    @MainActor
    @Test func persistedRunningEnvironmentRecoversAndForceQuitsWithoutLauncherSession() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-store-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runtime = TestRuntime.make(root: root)
        let environmentID = UUID()
        let applicationID = UUID()
        let managedRoot = root.appending(path: "environment")
        let managed = ManagedBorealEnvironment(
            id: environmentID,
            configuration: EnvironmentConfiguration(name: "Recovery"),
            runtimeID: runtime.id,
            rootURL: managedRoot,
            prefixURL: managedRoot.appending(path: "prefix"),
            logsURL: managedRoot.appending(path: "Logs"),
            state: .ready
        )
        let environment = WindowsEnvironment(
            id: environmentID,
            name: "Recovery",
            runtime: runtime.displayName,
            runtimeID: runtime.id,
            rootPath: managed.rootURL.path,
            prefixPath: managed.prefixURL.path,
            logsPath: managed.logsURL.path
        )
        let application = WindowsApplication(
            id: applicationID,
            name: "Recovery App",
            publisher: "Test",
            executablePath: managed.prefixURL.appending(path: "app.exe").path,
            installerPath: "",
            environmentID: environmentID,
            status: .running,
            compatibility: .unknown,
            storeProvider: .gog,
            storeExternalID: "recovery-game"
        )
        let sessionStart = Date().addingTimeInterval(-120)
        let game = StoreLibraryGame(
            provider: .gog,
            externalID: "recovery-game",
            name: "Recovery App",
            borealPlaytimeSeconds: 30,
            playSessions: [GamePlaySession(
                startedAt: sessionStart,
                endedAt: nil,
                measuredDurationSeconds: 30,
                lastCheckpointAt: sessionStart.addingTimeInterval(30)
            )]
        )
        try FileManager.default.createDirectory(at: managed.prefixURL, withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: application.executablePath))
        let storageURL = root.appending(path: "library.json")
        try JSONEncoder().encode(TestPersistedState(
            applications: [application],
            environments: [environment],
            storeGames: [game]
        )).write(to: storageURL)

        let runner = RecoveryProcessRunner()
        let services = BorealServices(
            runtimeManager: TestRuntimeManager(runtime: runtime),
            environmentManager: UnusedEnvironmentManager(),
            processRunner: runner,
            installer: UnusedInstaller(),
            steamLibrary: SteamLibraryService(),
            steamWindows: UnusedSteamWindows(),
            epicLibrary: UnusedEpicLibrary(),
            gogLibrary: UnusedGOGLibrary()
        )
        let store = BorealStore(storageURL: storageURL, services: services)

        try await waitUntil { store.application(id: applicationID)?.status == .running }
        #expect(await runner.probeCount >= 1)

        store.forceQuit(applicationID)
        try await waitUntil { store.application(id: applicationID)?.status == .ready }
        #expect(await runner.forceQuitCount == 1)
        let recoveredGame = try #require(store.storeGames.first)
        #expect(recoveredGame.activePlaySession == nil)
        #expect(recoveredGame.completedPlaySessions.count == 1)
        #expect(recoveredGame.measuredPlaytime >= 30)
    }

    @MainActor
    @Test func interruptedStoreDownloadRecoversAsResumableWithoutDiscardingProgress() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "boreal-download-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let game = StoreLibraryGame(
            provider: .gog,
            externalID: "12345",
            name: "Recoverable Game",
            supportsWindows: true
        )
        let progress = StoreGameOperationProgress(
            message: "Downloading game files",
            fractionCompleted: 0.42,
            phase: .downloading,
            transferRate: "18.2 MiB/s"
        )
        let key = "GOG::12345"
        let record = StoreDownloadRecord(
            provider: .gog,
            externalID: game.externalID,
            destinationRootPath: root.appending(path: "Games/GOG").path,
            platform: .windows,
            status: .downloading,
            lastProgress: progress
        )
        let storageURL = root.appending(path: "library.json")
        try JSONEncoder().encode(TestPersistedState(
            applications: [],
            environments: [],
            storeGames: [game],
            storeDownloads: [key: record]
        )).write(to: storageURL)
        let services = BorealServices(
            runtimeManager: TestRuntimeManager(runtime: TestRuntime.make(root: root)),
            environmentManager: UnusedEnvironmentManager(),
            processRunner: RecoveryProcessRunner(),
            installer: UnusedInstaller(),
            steamLibrary: SteamLibraryService(),
            steamWindows: UnusedSteamWindows(),
            epicLibrary: UnusedEpicLibrary(),
            gogLibrary: UnusedGOGLibrary()
        )

        let store = BorealStore(storageURL: storageURL, services: services)
        let recoveredGame = try #require(store.storeGames.first)
        guard case .paused(let recoveredProgress, let reason) = store.storeGameOperation(for: recoveredGame) else {
            Issue.record("Expected a paused, resumable download")
            return
        }

        #expect(recoveredProgress.fractionCompleted == 0.42)
        #expect(recoveredProgress.transferRate == "18.2 MiB/s")
        #expect(reason.contains("closed during this download"))
        #expect(store.canResumeStoreGameOperation(recoveredGame))

        let saved = try JSONDecoder().decode(TestPersistedState.self, from: Data(contentsOf: storageURL))
        #expect(saved.storeDownloads?[key]?.status == .paused)
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for recovered Store state")
    }
}

private actor CompletionFlag {
    private(set) var isComplete = false
    func markComplete() { isComplete = true }
}

private struct SessionFixture {
    let root: URL
    let activeMarker: URL
    let environment: ManagedBorealEnvironment
    let runtime: InstalledRuntime

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "boreal-session-fixture-\(UUID().uuidString)")
        let bin = root.appending(path: "runtime/bin")
        let environmentRoot = root.appending(path: "environment")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: environmentRoot.appending(path: "prefix"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: environmentRoot.appending(path: "Logs"), withIntermediateDirectories: true)
        activeMarker = environmentRoot.appending(path: "prefix/.active")
        let wineserver = bin.appending(path: "wineserver")
        try Data(Self.wineserverScript.utf8).write(to: wineserver)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wineserver.path)
        runtime = InstalledRuntime(
            id: "test-runtime",
            displayName: "Test Runtime",
            wineVersion: "test",
            rootURL: root.appending(path: "runtime"),
            wineExecutable: bin.appending(path: "wine"),
            wineServerExecutable: wineserver,
            wineBootExecutable: bin.appending(path: "wineboot"),
            architecture: .x86_64,
            requirements: []
        )
        environment = ManagedBorealEnvironment(
            id: UUID(),
            configuration: EnvironmentConfiguration(name: "Probe"),
            runtimeID: runtime.id,
            rootURL: environmentRoot,
            prefixURL: environmentRoot.appending(path: "prefix"),
            logsURL: environmentRoot.appending(path: "Logs"),
            state: .ready
        )
    }

    private static let wineserverScript = """
    #!/bin/sh
    case "$1" in
      -w)
        if [ ! -f "$WINEPREFIX/.active" ]; then exit 0; fi
        trap 'exit 143' TERM INT
        while [ -f "$WINEPREFIX/.active" ]; do /bin/sleep 0.05; done
        exit 0
        ;;
      -k)
        /bin/rm -f "$WINEPREFIX/.active"
        exit 0
        ;;
      *) exit 64 ;;
    esac
    """
}

private struct TestPersistedState: Codable {
    var applications: [WindowsApplication]
    var environments: [WindowsEnvironment]
    var storeGames: [StoreLibraryGame]? = nil
    var storeDownloads: [String: StoreDownloadRecord]? = nil
}

private enum TestRuntime {
    static func make(root: URL) -> InstalledRuntime {
        InstalledRuntime(
            id: "recovery-runtime",
            displayName: "Recovery Runtime",
            wineVersion: "test",
            rootURL: root.appending(path: "runtime"),
            wineExecutable: root.appending(path: "runtime/wine"),
            wineServerExecutable: root.appending(path: "runtime/wineserver"),
            wineBootExecutable: root.appending(path: "runtime/wineboot"),
            architecture: .x86_64,
            requirements: []
        )
    }
}

private struct TestRuntimeManager: RuntimeManaging {
    let runtime: InstalledRuntime
    func availableRuntimes() async throws -> [BorealRuntime] { [] }
    func installedRuntimes() async throws -> [InstalledRuntime] { [runtime] }
    func localRuntimeCandidates() async -> [LocalRuntimeCandidate] { [] }
    func importLocalRuntime(_ candidate: LocalRuntimeCandidate) async throws -> InstalledRuntime { runtime }
    func install(_ runtime: BorealRuntime) async throws -> InstalledRuntime { self.runtime }
    func validate(_ runtime: InstalledRuntime) async throws -> RuntimeValidation {
        RuntimeValidation(detectedWineVersion: runtime.wineVersion, versionMatchesManifest: true, missingPaths: [], unmetRequirements: [], executablePaths: [])
    }
    func remove(_ runtime: InstalledRuntime) async throws {}
}

private struct UnusedEnvironmentManager: EnvironmentManaging {
    func create(configuration: EnvironmentConfiguration, runtime: InstalledRuntime) async throws -> ManagedBorealEnvironment { throw CocoaError(.featureUnsupported) }
    func initialize(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws { throw CocoaError(.featureUnsupported) }
    func validate(_ environment: ManagedBorealEnvironment) async throws -> EnvironmentValidation { throw CocoaError(.featureUnsupported) }
    func remove(_ environment: ManagedBorealEnvironment) async throws {}
}

private struct UnusedInstaller: Installing {
    func install(_ installer: URL, name: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> InstallationCommit {
        throw CocoaError(.featureUnsupported)
    }
}

private struct UnusedEpicLibrary: EpicLibraryProviding {
    func connectionState() async -> EpicConnectionState { .supportNotInstalled }
    func prepareSupport() async throws { throw CocoaError(.featureUnsupported) }
    func authenticate(authorizationCode: String) async throws -> String? { throw CocoaError(.featureUnsupported) }
    func loadLibrary() async throws -> [StoreLibraryGame] { throw CocoaError(.featureUnsupported) }
    func install(appID: String, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws { throw CocoaError(.featureUnsupported) }
    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan { throw CocoaError(.featureUnsupported) }
    func disconnect() async throws { throw CocoaError(.featureUnsupported) }
}

private struct UnusedSteamWindows: SteamWindowsProviding {
    func prepareClient(progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> SteamWindowsClientCommit {
        throw CocoaError(.featureUnsupported)
    }
}

private struct UnusedGOGLibrary: GOGLibraryProviding {
    func connectionState() async -> GOGConnectionState { .supportNotInstalled }
    func prepareSupport() async throws { throw CocoaError(.featureUnsupported) }
    func authenticate(authorizationCode: String) async throws -> String? { throw CocoaError(.featureUnsupported) }
    func loadLibrary() async throws -> [StoreLibraryGame] { throw CocoaError(.featureUnsupported) }
    func install(appID: String, progress: @escaping @Sendable (StoreGameOperationProgress) async -> Void) async throws { throw CocoaError(.featureUnsupported) }
    func launchPlan(appID: String, runtime: InstalledRuntime, environment: ManagedBorealEnvironment) async throws -> WindowsLaunchPlan { throw CocoaError(.featureUnsupported) }
    func disconnect() async throws { throw CocoaError(.featureUnsupported) }
}

private actor RecoveryProcessRunner: WindowsProcessRunning {
    private(set) var probeCount = 0
    private(set) var forceQuitCount = 0
    private var environmentState: EnvironmentSessionState = .active

    func run(executable: URL, arguments: [String], environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession { throw CocoaError(.featureUnsupported) }
    func run(plan: WindowsLaunchPlan, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession { throw CocoaError(.featureUnsupported) }
    func waitForExit(_ session: WindowsProcessSession) async throws -> ProcessExecutionResult { throw CocoaError(.featureUnsupported) }
    func state(of session: WindowsProcessSession) async throws -> ProcessExecutionState { throw CocoaError(.featureUnsupported) }
    func stopApplication(_ session: WindowsProcessSession) async throws { throw CocoaError(.featureUnsupported) }
    func environmentSessionState(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> EnvironmentSessionState {
        probeCount += 1
        return environmentState
    }
    func waitForEnvironmentSessionEnd(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        while environmentState == .active { try await Task.sleep(for: .milliseconds(10)) }
    }
    func terminateEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws { environmentState = .inactive }
    func forceQuitEnvironment(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        forceQuitCount += 1
        environmentState = .inactive
    }
    func forceQuit(_ session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        try await forceQuitEnvironment(environment: environment, runtime: runtime)
    }
}
