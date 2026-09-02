import Foundation

actor EnvironmentManager: EnvironmentManaging {
    private let environmentsURL: URL
    private let processExecutor: any ProcessExecuting
    private let fileManager = FileManager.default
    private let prefixInitializationAttempts: Int
    private let prefixInitializationInterval: Duration

    init(
        applicationSupportURL: URL,
        processExecutor: any ProcessExecuting,
        prefixInitializationAttempts: Int = 120,
        prefixInitializationInterval: Duration = .milliseconds(250)
    ) {
        self.environmentsURL = applicationSupportURL.appending(path: "Environments", directoryHint: .isDirectory)
        self.processExecutor = processExecutor
        self.prefixInitializationAttempts = max(prefixInitializationAttempts, 1)
        self.prefixInitializationInterval = prefixInitializationInterval
    }

    func create(configuration: EnvironmentConfiguration, runtime: InstalledRuntime) async throws -> ManagedBorealEnvironment {
        let id = UUID()
        let root = environmentsURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        var resolvedConfiguration = configuration
        if resolvedConfiguration.architecture == WinePrefixArchitecture.win32.rawValue,
           runtime.features?.wow64 == true {
            // Current Wine WoW64 builds host both PE32 and PE32+ processes in a
            // 64-bit prefix and explicitly reject WINEARCH=win32.
            resolvedConfiguration.architecture = WinePrefixArchitecture.win64.rawValue
        }
        let environment = ManagedBorealEnvironment(
            id: id,
            configuration: resolvedConfiguration,
            runtimeID: runtime.id,
            rootURL: root,
            prefixURL: root.appending(path: "prefix", directoryHint: .isDirectory),
            logsURL: root.appending(path: "Logs", directoryHint: .isDirectory),
            state: .created
        )
        try fileManager.createDirectory(at: environment.prefixURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: environment.logsURL, withIntermediateDirectories: true)
        try write(environment)
        return environment
    }

    func initialize(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        guard environment.runtimeID == runtime.id else { throw EnvironmentManagerError.runtimeMismatch }
        var initializing = environment
        initializing.state = .initializing
        try write(initializing)

        let request = ProcessLaunchRequest(
            executable: runtime.wineBootExecutable,
            arguments: ["--init"],
            environment: wineEnvironment(for: environment, runtime: runtime),
            currentDirectory: environment.rootURL,
            stdoutLog: environment.logsURL.appending(path: "wineboot.stdout.log"),
            stderrLog: environment.logsURL.appending(path: "wineboot.stderr.log")
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        let prefixIsComplete = try await waitForPrefixInitialization(environment.prefixURL)
        guard prefixIsComplete else {
            var invalid = environment
            invalid.state = .invalid
            try? write(invalid)
            let validation = try await validate(invalid)
            if result.exitCode != 0 {
                throw EnvironmentManagerError.initializationFailed(exitCode: result.exitCode, stderrLog: result.stderrLog)
            }
            throw EnvironmentManagerError.validationFailed(validation)
        }

        // Some Wine and GPTK builds can return a non-zero status after they have
        // already committed a usable prefix. The prefix contents and the final
        // validation are the source of truth; the process status remains useful
        // only when the prefix is incomplete.
        var ready = environment
        ready.state = .ready
        try write(ready)
        let validation = try await validate(ready)
        guard validation.isReady else {
            var invalid = environment
            invalid.state = .invalid
            try? write(invalid)
            throw EnvironmentManagerError.validationFailed(validation)
        }
    }

    func configure(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        guard environment.runtimeID == runtime.id else { throw EnvironmentManagerError.runtimeMismatch }
        let request = ProcessLaunchRequest(
            executable: runtime.wineExecutable,
            arguments: ["winecfg", "-v", environment.configuration.windowsVersion],
            environment: wineEnvironment(for: environment, runtime: runtime),
            currentDirectory: environment.rootURL,
            stdoutLog: environment.logsURL.appending(path: "winecfg.stdout.log"),
            stderrLog: environment.logsURL.appending(path: "winecfg.stderr.log")
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 else {
            throw EnvironmentManagerError.configurationFailed(exitCode: result.exitCode, stderrLog: result.stderrLog)
        }
    }

    func validate(_ environment: ManagedBorealEnvironment) async throws -> EnvironmentValidation {
        let expected = [
            environment.prefixURL.appending(path: "drive_c", directoryHint: .isDirectory),
            environment.prefixURL.appending(path: "dosdevices", directoryHint: .isDirectory),
            environment.prefixURL.appending(path: "system.reg"),
            environment.prefixURL.appending(path: "user.reg")
        ]
        let missing = expected.filter { !fileManager.fileExists(atPath: $0.path) }.map(\.path)
        let stored = try? load(at: environment.rootURL)
        return EnvironmentValidation(missingPaths: missing, state: stored?.state ?? environment.state)
    }

    func preserveFailureDiagnostics(_ environment: ManagedBorealEnvironment) async -> EnvironmentFailureDiagnostics? {
        let destination = environmentsURL
            .deletingLastPathComponent()
            .appending(path: "Logs/EnvironmentFailures", directoryHint: .isDirectory)
            .appending(path: "\(environment.id.uuidString)-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let copiedLogs = destination.appending(path: "Logs", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: environment.logsURL.path) {
                try fileManager.copyItem(at: environment.logsURL, to: copiedLogs)
            }
            let descriptor = environment.rootURL.appending(path: "environment.json")
            if fileManager.fileExists(atPath: descriptor.path) {
                try fileManager.copyItem(at: descriptor, to: destination.appending(path: "environment.json"))
            }

            let preferredNames = ["wineboot.stderr.log", "winecfg.stderr.log"]
            var diagnosticLog = preferredNames
                .map { copiedLogs.appending(path: $0) }
                .first { fileManager.fileExists(atPath: $0.path) }
            if diagnosticLog == nil,
               let children = try? fileManager.contentsOfDirectory(
                    at: copiedLogs,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
               ) {
                diagnosticLog = children
                    .filter { $0.lastPathComponent.hasSuffix(".stderr.log") }
                    .sorted {
                        let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return lhs > rhs
                    }
                    .first
            }
            return EnvironmentFailureDiagnostics(
                directoryURL: destination,
                logURL: diagnosticLog,
                logExcerpt: diagnosticLog.flatMap(logExcerpt(from:))
            )
        } catch {
            return nil
        }
    }

    func remove(_ environment: ManagedBorealEnvironment) async throws {
        let root = environment.rootURL.standardizedFileURL
        guard root.deletingLastPathComponent() == environmentsURL.standardizedFileURL else { throw CocoaError(.fileWriteNoPermission) }
        if fileManager.fileExists(atPath: root.path) { try fileManager.removeItem(at: root) }
    }

    func load(at root: URL) throws -> ManagedBorealEnvironment {
        let data = try Data(contentsOf: root.appending(path: "environment.json"))
        return try JSONDecoder().decode(ManagedBorealEnvironment.self, from: data)
    }

    private func write(_ environment: ManagedBorealEnvironment) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(environment).write(to: environment.rootURL.appending(path: "environment.json"), options: .atomic)
    }

    private func wineEnvironment(for environment: ManagedBorealEnvironment, runtime: InstalledRuntime) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["WINEPREFIX"] = environment.prefixURL.path
        values["WINEARCH"] = environment.configuration.architecture
        values["WINEESYNC"] = environment.configuration.esyncEnabled ? "1" : "0"
        values["WINEMSYNC"] = environment.configuration.msyncEnabled ? "1" : "0"
        values["WINE_FULLSCREEN_FSR"] = environment.configuration.fullscreenFSREnabled ? "1" : "0"
        values["WINE_RETINA_MODE"] = environment.configuration.retinaModeEnabled ? "1" : "0"
        values["WINEDEBUG"] = values["WINEDEBUG"] ?? "-all"
        values["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":" + (values["PATH"] ?? "/usr/bin:/bin")
        return values
    }

    private func waitForPrefixInitialization(_ prefix: URL) async throws -> Bool {
        let expected = [
            prefix.appending(path: "drive_c", directoryHint: .isDirectory),
            prefix.appending(path: "dosdevices", directoryHint: .isDirectory),
            prefix.appending(path: "system.reg"),
            prefix.appending(path: "user.reg")
        ]
        for _ in 0..<prefixInitializationAttempts {
            try Task.checkCancellation()
            if expected.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) { return true }
            try await Task.sleep(for: prefixInitializationInterval)
        }
        return false
    }

    private func logExcerpt(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let bounded = data.count > 16_384 ? data.suffix(16_384) : data[...]
        return String(decoding: bounded, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
