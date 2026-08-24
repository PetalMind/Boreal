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

    var errorDescription: String? {
        switch self {
        case .noRuntimeAvailable: "No compatible Boreal Runtime is available. Install a verified runtime first."
        case .executableNotDiscovered: "The installer finished, but Boreal couldn’t find an application executable."
        }
    }
}

nonisolated protocol Installing: Sendable {
    func install(_ installer: URL, name: String) async throws -> InstallationCommit
}

actor InstallerService: Installing {
    private let runtimeManager: any RuntimeManaging
    private let environmentManager: any EnvironmentManaging
    private let processRunner: any WindowsProcessRunning
    private let fileManager = FileManager.default

    init(runtimeManager: any RuntimeManaging, environmentManager: any EnvironmentManaging, processRunner: any WindowsProcessRunning) {
        self.runtimeManager = runtimeManager
        self.environmentManager = environmentManager
        self.processRunner = processRunner
    }

    func install(_ installer: URL, name: String) async throws -> InstallationCommit {
        let runtime = try await readyRuntime()
        let environment = try await environmentManager.create(configuration: EnvironmentConfiguration(name: name), runtime: runtime)
        do {
            try await environmentManager.initialize(environment, runtime: runtime)
            let installerSession = try await processRunner.run(executable: installer, arguments: [], environment: environment, runtime: runtime)
            let installerResult = try await processRunner.waitForExit(installerSession)
            guard let executable = discoverExecutable(in: environment) ?? portableExecutable(installer) else {
                throw InstallerServiceError.executableNotDiscovered
            }
            let firstLaunch = try await processRunner.run(executable: executable, arguments: [], environment: environment, runtime: runtime)
            return InstallationCommit(environment: environment, runtime: runtime, executable: executable, firstLaunch: firstLaunch, installerResult: installerResult)
        } catch {
            try? await environmentManager.remove(environment)
            throw error
        }
    }

    private func readyRuntime() async throws -> InstalledRuntime {
        for runtime in try await runtimeManager.installedRuntimes() {
            if try await runtimeManager.validate(runtime).isReady { return runtime }
        }
        guard let candidate = try await runtimeManager.availableRuntimes().first else { throw InstallerServiceError.noRuntimeAvailable }
        return try await runtimeManager.install(candidate)
    }

    private func portableExecutable(_ installer: URL) -> URL? {
        installer.pathExtension.lowercased() == "exe" ? installer : nil
    }

    private func discoverExecutable(in environment: ManagedBorealEnvironment) -> URL? {
        let driveC = environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory)
        guard let enumerator = fileManager.enumerator(at: driveC, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        var candidates: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "exe" {
            let lower = url.path.lowercased()
            guard !lower.contains("/windows/"), !lower.contains("unins"), !lower.contains("uninstall"), !lower.contains("/update") else { continue }
            candidates.append(url)
        }
        return candidates.sorted { score($0) > score($1) }.first
    }

    private func score(_ url: URL) -> Int {
        let lower = url.path.lowercased()
        var value = 0
        if lower.contains("program files") { value += 10 }
        if lower.contains("/bin/") { value += 2 }
        if lower.contains("helper") || lower.contains("crash") || lower.contains("service") { value -= 8 }
        return value
    }
}
