import Foundation

actor EnvironmentManager: EnvironmentManaging {
    private let environmentsURL: URL
    private let processExecutor: any ProcessExecuting
    private let fileManager = FileManager.default

    init(applicationSupportURL: URL, processExecutor: any ProcessExecuting) {
        self.environmentsURL = applicationSupportURL.appending(path: "Environments", directoryHint: .isDirectory)
        self.processExecutor = processExecutor
    }

    func create(configuration: EnvironmentConfiguration, runtime: InstalledRuntime) async throws -> ManagedBorealEnvironment {
        let id = UUID()
        let root = environmentsURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        let environment = ManagedBorealEnvironment(
            id: id,
            configuration: configuration,
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
        guard result.exitCode == 0 else {
            var invalid = environment
            invalid.state = .invalid
            try? write(invalid)
            throw EnvironmentManagerError.initializationFailed(exitCode: result.exitCode, stderrLog: result.stderrLog)
        }
        var ready = environment
        ready.state = .ready
        try write(ready)
        let validation = try await validate(ready)
        guard validation.isReady else { throw EnvironmentManagerError.validationFailed(validation) }
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
        values["WINEDEBUG"] = values["WINEDEBUG"] ?? "-all"
        values["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":" + (values["PATH"] ?? "/usr/bin:/bin")
        return values
    }
}

