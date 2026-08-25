import Foundation

nonisolated struct BorealServices: Sendable {
    let runtimeManager: any RuntimeManaging
    let environmentManager: any EnvironmentManaging
    let processRunner: any WindowsProcessRunning
    let installer: any Installing
    let steamLibrary: any SteamLibraryLoading
    let steamWindows: any SteamWindowsProviding
    let epicLibrary: any EpicLibraryProviding
    let gogLibrary: any GOGLibraryProviding

    @MainActor static func live(applicationSupportURL: URL) -> BorealServices {
        let executor = SystemProcessExecutor()
        let requirements = RuntimeRequirementChecker(processExecutor: executor)
        // Production catalog URLs and the embedded Ed25519 public key are intentionally
        // not invented here. Until Boreal publishes them, only already installed or
        // explicitly injected development runtimes can be executed.
        let catalog: any RuntimeCatalogLoading
        #if DEBUG
        if let localPath = ProcessInfo.processInfo.environment["BOREAL_RUNTIME_CATALOG"], !localPath.isEmpty {
            catalog = LocalDevelopmentRuntimeCatalog(url: URL(fileURLWithPath: localPath))
        } else {
            catalog = EmptyRuntimeCatalog()
        }
        #else
        catalog = EmptyRuntimeCatalog()
        #endif
        let runtimeManager = RuntimeManager(
            applicationSupportURL: applicationSupportURL,
            catalog: catalog,
            processExecutor: executor,
            requirementChecker: requirements
        )
        let environmentManager = EnvironmentManager(applicationSupportURL: applicationSupportURL, processExecutor: executor)
        let runner = WindowsProcessRunner(processExecutor: executor)
        let installer = InstallerService(runtimeManager: runtimeManager, environmentManager: environmentManager, processRunner: runner)
        return BorealServices(
            runtimeManager: runtimeManager,
            environmentManager: environmentManager,
            processRunner: runner,
            installer: installer,
            steamLibrary: SteamLibraryService(),
            steamWindows: SteamWindowsService(applicationSupportURL: applicationSupportURL, installer: installer),
            epicLibrary: LegendaryEpicService(applicationSupportURL: applicationSupportURL),
            gogLibrary: GOGService(applicationSupportURL: applicationSupportURL)
        )
    }
}
