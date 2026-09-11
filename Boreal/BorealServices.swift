import Foundation

nonisolated struct BorealServices: Sendable {
    let runtimeManager: any RuntimeManaging
    let environmentManager: any EnvironmentManaging
    let processRunner: any WindowsProcessRunning
    let gameSessionCoordinator: any GameSessionCoordinating
    let launchCoordinator: any LaunchCoordinating
    let installer: any Installing
    let installationService: any GameInstallationManaging
    let activityService: ActivityService
    let steamLibrary: any SteamLibraryLoading
    let steamWindows: any SteamWindowsProviding
    let epicLibrary: any EpicLibraryProviding
    let gogLibrary: any GOGLibraryProviding
    let storeProviders: GameStoreProviderRegistry
    let communityCompatibility: any CommunityCompatibilityLoading
    let discoveryCatalog: any DiscoveryCatalogLoading
    let gogRevivedCatalog: any GOGRevivedCatalogLoading
    let discoveryPricing: any DiscoveryPricingLoading
    let compatibilityResolver: CompatibilityResolver
    let dependencyAnalyzer: DependencyAnalyzer
    let launchFailureAnalyzer: LaunchFailureAnalyzer
    let environmentSnapshotManager: EnvironmentSnapshotManager
    let gameSaveManager: GameSaveManager
    let advancedConfigurationStore: GameAdvancedConfigurationStore
    let storageAnalyzer: StorageAnalyzer
    let shaderCacheManager: any ShaderCacheManaging
    let compatibilityReports: any CompatibilityReportProviding
    let gameUpscalerAnalyzer: GameUpscalerAnalyzer
    let dlsstweaksManager: DLSSTweaksManager
    let optiScalerManager: OptiScalerManager
    let dlssRuntimeManager: DLSSRuntimeManager
    let temporalUpscalingResolver: TemporalUpscalingResolver

    init(
        runtimeManager: any RuntimeManaging,
        environmentManager: any EnvironmentManaging,
        processRunner: any WindowsProcessRunning,
        gameSessionCoordinator: (any GameSessionCoordinating)? = nil,
        installer: any Installing,
        launchCoordinator: (any LaunchCoordinating)? = nil,
        installationService: any GameInstallationManaging = InstallationService(),
        activityService: ActivityService = ActivityService(),
        steamLibrary: any SteamLibraryLoading,
        steamWindows: any SteamWindowsProviding,
        epicLibrary: any EpicLibraryProviding,
        gogLibrary: any GOGLibraryProviding,
        storeProviders: GameStoreProviderRegistry? = nil,
        communityCompatibility: any CommunityCompatibilityLoading = ProtonStoreCompatibilityService(),
        discoveryCatalog: any DiscoveryCatalogLoading = AppleGamingWikiDiscoveryService(),
        gogRevivedCatalog: any GOGRevivedCatalogLoading = GOGRevivedCatalogService(),
        discoveryPricing: any DiscoveryPricingLoading = ITADPriceService(),
        applicationSupportURL: URL? = nil,
        compatibilityResolver: CompatibilityResolver = CompatibilityResolver(),
        dependencyAnalyzer: DependencyAnalyzer = DependencyAnalyzer(),
        launchFailureAnalyzer: LaunchFailureAnalyzer = LaunchFailureAnalyzer(),
        environmentSnapshotManager: EnvironmentSnapshotManager? = nil,
        gameSaveManager: GameSaveManager? = nil,
        advancedConfigurationStore: GameAdvancedConfigurationStore? = nil,
        storageAnalyzer: StorageAnalyzer = StorageAnalyzer(),
        shaderCacheManager: any ShaderCacheManaging = FileSystemShaderCacheManager(),
        compatibilityReports: (any CompatibilityReportProviding)? = nil,
        gameUpscalerAnalyzer: GameUpscalerAnalyzer? = nil,
        dlsstweaksManager: DLSSTweaksManager? = nil,
        optiScalerManager: OptiScalerManager? = nil,
        dlssRuntimeManager: DLSSRuntimeManager? = nil,
        temporalUpscalingResolver: TemporalUpscalingResolver? = nil
    ) {
        self.runtimeManager = runtimeManager
        self.environmentManager = environmentManager
        self.processRunner = processRunner
        self.gameSessionCoordinator = gameSessionCoordinator ?? GameSessionCoordinator(processRunner: processRunner)
        self.launchCoordinator = launchCoordinator ?? LaunchCoordinator(processRunner: processRunner)
        self.installer = installer
        self.installationService = installationService
        self.activityService = activityService
        self.steamLibrary = steamLibrary
        self.steamWindows = steamWindows
        self.epicLibrary = epicLibrary
        self.gogLibrary = gogLibrary
        self.storeProviders = storeProviders ?? GameStoreProviderRegistry([
            SteamGameStoreProvider(libraryService: steamLibrary),
            EpicGameStoreProvider(service: epicLibrary),
            GOGGameStoreProvider(service: gogLibrary),
        ])
        self.communityCompatibility = communityCompatibility
        self.discoveryCatalog = discoveryCatalog
        self.gogRevivedCatalog = gogRevivedCatalog
        self.discoveryPricing = discoveryPricing
        self.compatibilityResolver = compatibilityResolver
        self.dependencyAnalyzer = dependencyAnalyzer
        self.launchFailureAnalyzer = launchFailureAnalyzer
        let supportURL = applicationSupportURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appending(path: "Boreal")
        self.environmentSnapshotManager = environmentSnapshotManager ?? EnvironmentSnapshotManager(applicationSupportURL: supportURL)
        self.gameSaveManager = gameSaveManager ?? GameSaveManager(applicationSupportURL: supportURL)
        self.advancedConfigurationStore = advancedConfigurationStore ?? GameAdvancedConfigurationStore(applicationSupportURL: supportURL)
        self.storageAnalyzer = storageAnalyzer
        self.shaderCacheManager = shaderCacheManager
        self.compatibilityReports = compatibilityReports ?? CompatibilityReportStore(applicationSupportURL: supportURL)
        let temporalComponentStore = ManagedTemporalComponentStore(applicationSupportURL: supportURL)
        self.gameUpscalerAnalyzer = gameUpscalerAnalyzer ?? GameUpscalerAnalyzer()
        self.dlsstweaksManager = dlsstweaksManager ?? DLSSTweaksManager(store: temporalComponentStore)
        self.optiScalerManager = optiScalerManager ?? OptiScalerManager(store: temporalComponentStore)
        self.dlssRuntimeManager = dlssRuntimeManager ?? DLSSRuntimeManager(store: temporalComponentStore)
        self.temporalUpscalingResolver = temporalUpscalingResolver ?? TemporalUpscalingResolver()
    }

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
            gogLibrary: GOGService(applicationSupportURL: applicationSupportURL),
            communityCompatibility: ProtonStoreCompatibilityService(),
            discoveryCatalog: AppleGamingWikiDiscoveryService(applicationSupportURL: applicationSupportURL),
            gogRevivedCatalog: GOGRevivedCatalogService(applicationSupportURL: applicationSupportURL),
            discoveryPricing: ITADPriceService(applicationSupportURL: applicationSupportURL),
            applicationSupportURL: applicationSupportURL
        )
    }
}
