import Foundation

nonisolated struct InstallationCommit: Sendable {
    let environment: ManagedBorealEnvironment
    let runtime: InstalledRuntime
    let executable: URL
    let firstLaunch: WindowsProcessSession
    let installerResult: ProcessExecutionResult
}

nonisolated enum InstallerServiceError: LocalizedError, Sendable {
    case noRuntimeAvailable
    case executableNotDiscovered
    case firstLaunchFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noRuntimeAvailable: "No compatible Boreal Runtime is available. Install a verified runtime first."
        case .executableNotDiscovered: "The installer finished, but Boreal couldn’t find an application executable."
        case .firstLaunchFailed(let code): "The application exited unexpectedly during its first launch (exit code \(code))."
        }
    }
}

nonisolated protocol Installing: Sendable {
    func install(_ installer: URL, name: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> InstallationCommit
}

extension RuntimeManaging {
    func prepareReadyRuntime() async throws -> InstalledRuntime {
        for runtime in try await installedRuntimes() {
            try Task.checkCancellation()
            if try await validate(runtime).isReady { return runtime }
        }

        if let local = await localRuntimeCandidates().first {
            try Task.checkCancellation()
            return try await importLocalRuntime(local)
        }

        guard let available = try await availableRuntimes().first else {
            throw InstallerServiceError.noRuntimeAvailable
        }
        try Task.checkCancellation()
        return try await install(available)
    }
}

actor InstallerService: Installing {
    private let runtimeManager: any RuntimeManaging
    private let environmentManager: any EnvironmentManaging
    private let processRunner: any WindowsProcessRunning

    init(runtimeManager: any RuntimeManaging, environmentManager: any EnvironmentManaging, processRunner: any WindowsProcessRunning) {
        self.runtimeManager = runtimeManager
        self.environmentManager = environmentManager
        self.processRunner = processRunner
    }

    func install(_ installer: URL, name: String, progress: @escaping @Sendable (InstallationStage) async -> Void) async throws -> InstallationCommit {
        await progress(.preparingRuntime)
        let runtime = try await readyRuntime()
        await progress(.creatingEnvironment)
        let environment = try await environmentManager.create(configuration: EnvironmentConfiguration(name: name), runtime: runtime)
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
            let snapshotAfterInstallation = ExecutableDiscovery.snapshot(at: driveC)
            let discoveredExecutable = ExecutableDiscovery.rankedCandidates(
                before: snapshotBeforeInstallation,
                after: snapshotAfterInstallation,
                applicationName: name
            ).first?.url
            guard let executable = discoveredExecutable ?? portableExecutable(installer) else {
                throw InstallerServiceError.executableNotDiscovered
            }
            await progress(.verifyingFirstLaunch)
            let firstLaunch = try await processRunner.run(executable: executable, arguments: [], environment: environment, runtime: runtime)
            try await withTaskCancellationHandler {
                try await Task.sleep(for: .milliseconds(750))
            } onCancel: {
                Task { try? await self.processRunner.stopApplication(firstLaunch) }
            }
            if case .terminated(let result) = try await processRunner.state(of: firstLaunch), result.exitCode != 0 {
                throw InstallerServiceError.firstLaunchFailed(result.exitCode)
            }
            await progress(.committing)
            return InstallationCommit(environment: environment, runtime: runtime, executable: executable, firstLaunch: firstLaunch, installerResult: installerResult)
        } catch {
            try? await environmentManager.remove(environment)
            throw error
        }
    }

    private func readyRuntime() async throws -> InstalledRuntime {
        try await runtimeManager.prepareReadyRuntime()
    }

    private func portableExecutable(_ installer: URL) -> URL? {
        ExecutableDiscovery.isEligibleExecutablePath(installer.lastPathComponent) ? installer : nil
    }

}
