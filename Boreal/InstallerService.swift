import Foundation

nonisolated struct InstallationCommit: Sendable {
    let environment: ManagedBorealEnvironment
    let runtime: InstalledRuntime
    let executable: URL
    let firstLaunch: WindowsProcessSession?
    let installerResult: ProcessExecutionResult
}

nonisolated struct InstallerLaunchCommit: Sendable {
    let environment: ManagedBorealEnvironment
    let runtime: InstalledRuntime
    let installerSession: WindowsProcessSession
}

nonisolated enum InstallerServiceError: LocalizedError, Sendable {
    case noRuntimeAvailable
    case invalidInstaller(URL)
    case executableNotDiscovered
    case firstLaunchFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noRuntimeAvailable: "No compatible Boreal Runtime is available. Install a verified runtime first."
        case .invalidInstaller(let url): "The selected installer is not a readable .exe or .msi file: \(url.path)."
        case .executableNotDiscovered: "The installer finished, but Boreal couldn’t find an application executable."
        case .firstLaunchFailed(let code): "The application exited unexpectedly during its first launch (exit code \(code))."
        }
    }
}

nonisolated protocol Installing: Sendable {
    func install(_ installer: URL, name: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> InstallationCommit
    func install(
        _ installer: URL,
        name: String,
        preferredEngine: RuntimeEngine?,
        progress: @escaping @Sendable (InstallationStage) async -> Void
    ) async throws -> InstallationCommit
    func launchInstaller(
        _ installer: URL,
        name: String,
        preferredEngine: RuntimeEngine,
        progress: @escaping @Sendable (InstallationStage) async -> Void
    ) async throws -> InstallerLaunchCommit
}

extension Installing {
    func install(
        _ installer: URL,
        name: String,
        preferredEngine: RuntimeEngine?,
        progress: @escaping @Sendable (InstallationStage) async -> Void
    ) async throws -> InstallationCommit {
        try await install(installer, name: name, progress: progress)
    }

    func launchInstaller(
        _ installer: URL,
        name: String,
        preferredEngine: RuntimeEngine,
        progress: @escaping @Sendable (InstallationStage) async -> Void
    ) async throws -> InstallerLaunchCommit {
        throw InstallerServiceError.noRuntimeAvailable
    }
}

extension RuntimeManaging {
    func prepareReadyRuntime(
        preferredEngine: RuntimeEngine? = nil,
        executableArchitecture: WindowsExecutableArchitecture? = nil
    ) async throws -> InstalledRuntime {
        let architectures = executableArchitecture.map { [$0] } ?? [.unknown]
        return try await prepareReadyRuntime(for: RuntimeSelectionRequest(
            architectures: architectures,
            requiredEngine: preferredEngine
        ))
    }
}

actor InstallerService: Installing {
    private let runtimeManager: any RuntimeManaging
    private let environmentManager: any EnvironmentManaging
    private let processRunner: any WindowsProcessRunning
    private let discoveryAttempts: Int
    private let discoveryInterval: Duration

    init(
        runtimeManager: any RuntimeManaging,
        environmentManager: any EnvironmentManaging,
        processRunner: any WindowsProcessRunning,
        discoveryAttempts: Int = 30,
        discoveryInterval: Duration = .milliseconds(500)
    ) {
        self.runtimeManager = runtimeManager
        self.environmentManager = environmentManager
        self.processRunner = processRunner
        self.discoveryAttempts = max(1, discoveryAttempts)
        self.discoveryInterval = discoveryInterval
    }

    func install(_ installer: URL, name: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> InstallationCommit {
        try await install(installer, name: name, preferredEngine: nil, progress: progress)
    }

    func install(
        _ installer: URL,
        name: String,
        preferredEngine selectedEngine: RuntimeEngine?,
        progress: @escaping @Sendable (InstallationStage) async -> Void
    ) async throws -> InstallationCommit {
        await progress(.preparingRuntime)
        // The installer is a PE executable. Its architecture constrains the
        // compatible runtime set, but it does not directly choose Wine or GPTK.
        let installerArchitecture = WindowsExecutableArchitecture.inspect(installer)
        // Steam's setup bootstrapper is commonly a 32-bit PE, but the resulting
        // bottle must also host 64-bit Steam games. Keep the shared Steam bottle
        // WoW64-capable instead of deriving its architecture from SteamSetup.exe.
        let runtime = try await readyRuntime(
            preferredEngine: selectedEngine,
            executableArchitecture: installerArchitecture,
            requiredArchitectures: name == "Steam for Windows" ? [.x86, .x86_64] : nil
        )
        let environmentArchitecture = installerArchitecture == .x86 ? "win32" : "win64"
        let prefixMode: WinePrefixMode? = runtime.features?.resolvedArchitectureCapabilities.usesNewWoW64 == true
            ? .wow64
            : (installerArchitecture == .x86 ? .legacyWin32 : .legacyWin64)
        await progress(.creatingEnvironment)
        var environment = try await environmentManager.create(
            configuration: EnvironmentConfiguration(name: name, architecture: environmentArchitecture, prefixMode: prefixMode),
            runtime: runtime
        )
        environment.purpose = name == "Steam for Windows" ? .sharedStore : .game
        do {
            try await environmentManager.initialize(environment, runtime: runtime)
            let driveC = environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory)
            let snapshotBeforeInstallation = ExecutableDiscovery.snapshot(at: driveC)
            await progress(.startingInstaller)
            let installerSession = try await processRunner.run(executable: installer, arguments: [], environment: environment, runtime: runtime)
            let installerResult = try await withTaskCancellationHandler {
                try await processRunner.waitForExit(installerSession)
            } onCancel: {
                Task { try? await self.processRunner.stopApplication(installerSession) }
            }
            try Task.checkCancellation()
            await progress(.detectingApplication)
            let discoveredExecutable = try await discoverInstalledExecutable(
                in: driveC,
                before: snapshotBeforeInstallation,
                applicationName: name
            )
            guard let executable = discoveredExecutable ?? portableExecutable(installer) else {
                throw InstallerServiceError.executableNotDiscovered
            }
            await progress(.verifyingFirstLaunch)
            var preparedEnvironment = environment
            let analysisRoot = environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory)
            let analysis = ExecutableCompatibilityAnalyzer.analyze(
                root: analysisRoot,
                applicationName: name,
                knownPrimary: executable
            )
            let gameProfile: GameGraphicsProfile? = nil
            let userProfile = WineCompatibilityProfile.default
            let resolved = try CompatibilityPreparationResolver.resolve(
                analysis: analysis,
                userProfile: userProfile,
                gameProfile: gameProfile,
                runtime: runtime
            )
            guard resolved.prefixMode == preparedEnvironment.configuration.resolvedPrefixMode(
                runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true
            ) else {
                throw CompatibilityPreparationError.noCompatibleRuntime(
                    "The installed game requires a different prefix architecture than the installer environment."
                )
            }
            preparedEnvironment.configuration.architecture = resolved.executableArchitecture == .x86 ? "win32" : "win64"
            preparedEnvironment.configuration.windowsVersion = resolved.windowsVersion.rawValue
            preparedEnvironment.configuration.graphicsAPI = resolved.directXAPI
            preparedEnvironment.configuration.graphicsBackend = resolved.graphicsStack.backend
            preparedEnvironment.configuration.prefixMode = resolved.prefixMode
            preparedEnvironment.configuration.requiredDependencies = Set(resolved.dependencies)
            // Persist the resolved plan before installing components so a retry
            // or later launch observes the same compatibility decision.
            preparedEnvironment = try await environmentManager.configure(preparedEnvironment, runtime: runtime)
            for dependency in resolved.dependencies {
                try await environmentManager.install(dependency, in: preparedEnvironment, runtime: runtime)
            }
            await progress(.committing)
            let firstLaunch: WindowsProcessSession?
            if name == "Steam for Windows" {
                firstLaunch = try await processRunner.run(executable: executable, arguments: [], environment: preparedEnvironment, runtime: runtime)
            } else {
                firstLaunch = nil
            }
            return InstallationCommit(environment: preparedEnvironment, runtime: runtime, executable: resolved.executable, firstLaunch: firstLaunch, installerResult: installerResult)
        } catch {
            try? await environmentManager.remove(environment)
            throw error
        }
    }

    /// Prepares only the compatibility environment and launches the selected
    /// installer. It intentionally does not inspect the prefix for a game,
    /// launch a detected executable, or commit a game record.
    func launchInstaller(
        _ installer: URL,
        name: String,
        preferredEngine: RuntimeEngine,
        progress: @escaping @Sendable (InstallationStage) async -> Void
    ) async throws -> InstallerLaunchCommit {
        let isRegularFile = (try? installer.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        let extensionIsSupported = ["exe", "msi"].contains(installer.pathExtension.lowercased())
        guard isRegularFile, extensionIsSupported else {
            throw InstallerServiceError.invalidInstaller(installer)
        }

        await progress(.preparingRuntime)
        let installerArchitecture = WindowsExecutableArchitecture.inspect(installer)
        let environmentArchitecture = installerArchitecture == .x86 ? "win32" : "win64"
        let runtime = try await readyRuntime(
            preferredEngine: preferredEngine,
            executableArchitecture: installerArchitecture
        )
        let prefixMode: WinePrefixMode? = runtime.features?.resolvedArchitectureCapabilities.usesNewWoW64 == true
            ? .wow64
            : (installerArchitecture == .x86 ? .legacyWin32 : .legacyWin64)
        await progress(.creatingEnvironment)
        let environment = try await environmentManager.create(
            configuration: EnvironmentConfiguration(name: name, architecture: environmentArchitecture, prefixMode: prefixMode),
            runtime: runtime
        )
        var installerSession: WindowsProcessSession?
        do {
            try await environmentManager.initialize(environment, runtime: runtime)
            await progress(.startingInstaller)
            installerSession = try await processRunner.run(
                executable: installer,
                arguments: [],
                environment: environment,
                runtime: runtime
            )
            try Task.checkCancellation()
            return InstallerLaunchCommit(
                environment: environment,
                runtime: runtime,
                installerSession: installerSession!
            )
        } catch {
            if let installerSession {
                try? await processRunner.stopApplication(installerSession)
            }
            try? await environmentManager.remove(environment)
            throw error
        }
    }

    private func readyRuntime(
        preferredEngine: RuntimeEngine?,
        executableArchitecture: WindowsExecutableArchitecture,
        requiredArchitectures: [WindowsExecutableArchitecture]? = nil
    ) async throws -> InstalledRuntime {
        try await runtimeManager.prepareReadyRuntime(for: RuntimeSelectionRequest(
            architectures: requiredArchitectures ?? [executableArchitecture],
            requiredEngine: preferredEngine
        ))
    }

    private func portableExecutable(_ installer: URL) -> URL? {
        ExecutableDiscovery.isEligibleExecutablePath(installer.lastPathComponent) ? installer : nil
    }

    /// Some bootstrap installers exit their launcher process before a child has
    /// finished moving the application into its final directory. Polling the
    /// pure snapshot diff for a short, bounded window avoids treating that
    /// normal hand-off as a failed installation.
    private func discoverInstalledExecutable(
        in driveC: URL,
        before: ExecutableFilesystemSnapshot,
        applicationName: String
    ) async throws -> URL? {
        for attempt in 0..<discoveryAttempts {
            try Task.checkCancellation()
            let snapshot = ExecutableDiscovery.snapshot(at: driveC)
            if let candidate = ExecutableDiscovery.rankedCandidates(
                before: before,
                after: snapshot,
                applicationName: applicationName
            ).first(where: { $0.score >= ExecutableDiscovery.minimumLaunchCandidateScore }) {
                return candidate.url
            }
            if attempt + 1 < discoveryAttempts {
                try await Task.sleep(for: discoveryInterval)
            }
        }
        return nil
    }

}
