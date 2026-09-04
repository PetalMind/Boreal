import Foundation

actor EnvironmentManager: EnvironmentManaging {
    private let environmentsURL: URL
    private let dependencyToolsURL: URL
    private let processExecutor: any ProcessExecuting
    private let session: URLSession
    private let fileManager = FileManager.default
    private let graphicsBackendManager = GraphicsBackendManager()
    private let prefixInitializationAttempts: Int
    private let prefixInitializationInterval: Duration

    init(
        applicationSupportURL: URL,
        processExecutor: any ProcessExecuting,
        session: URLSession = .shared,
        prefixInitializationAttempts: Int = 120,
        prefixInitializationInterval: Duration = .milliseconds(250)
    ) {
        self.environmentsURL = applicationSupportURL.appending(path: "Environments", directoryHint: .isDirectory)
        self.dependencyToolsURL = applicationSupportURL.appending(path: "Tools/Winetricks/2026-09-04", directoryHint: .isDirectory)
        self.processExecutor = processExecutor
        self.session = session
        self.prefixInitializationAttempts = max(prefixInitializationAttempts, 1)
        self.prefixInitializationInterval = prefixInitializationInterval
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
        try fileManager.createDirectory(at: environment.logsURL, withIntermediateDirectories: true)
        try write(environment)
        return environment
    }

    func initialize(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        guard environment.runtimeID == runtime.id else { throw EnvironmentManagerError.runtimeMismatch }
        var initializing = environment
        initializing.state = .initializing
        try write(initializing)

        let stagingPrefix = environment.rootURL.appending(path: ".prefix-installing", directoryHint: .isDirectory)
        try removePrefixIfPresent(stagingPrefix)
        try removePrefixIfPresent(environment.prefixURL)
        try fileManager.createDirectory(at: stagingPrefix, withIntermediateDirectories: true)
        let stagingEnvironment = ManagedBorealEnvironment(
            id: environment.id,
            configuration: environment.configuration,
            runtimeID: environment.runtimeID,
            rootURL: environment.rootURL,
            prefixURL: stagingPrefix,
            logsURL: environment.logsURL,
            state: .initializing
        )

        do {
            let request = ProcessLaunchRequest(
                executable: runtime.wineBootExecutable,
                arguments: ["-u"],
                environment: wineEnvironment(for: stagingEnvironment, runtime: runtime),
                currentDirectory: environment.rootURL,
                stdoutLog: environment.logsURL.appending(path: "wineboot.stdout.log"),
                stderrLog: environment.logsURL.appending(path: "wineboot.stderr.log")
            )
            let receipt = try await processExecutor.launch(request)
            let result = try await processExecutor.waitForExit(receipt.id)
            let prefixIsComplete = try await waitForPrefixInitialization(stagingPrefix)
            guard prefixIsComplete else {
                let validation = EnvironmentValidation(
                    missingPaths: missingPrefixPaths(at: stagingPrefix),
                    state: .invalid
                )
                if result.exitCode != 0 {
                    throw EnvironmentManagerError.initializationFailed(exitCode: result.exitCode, stderrLog: result.stderrLog)
                }
                throw EnvironmentManagerError.validationFailed(validation)
            }

            // Some Wine and GPTK builds can return a non-zero status after they
            // have committed a usable prefix. Completeness remains the truth.
            try await applyConfiguration(stagingEnvironment, runtime: runtime)
            let missing = missingPrefixPaths(at: stagingPrefix)
            guard missing.isEmpty else {
                throw EnvironmentManagerError.validationFailed(
                    EnvironmentValidation(missingPaths: missing, state: .invalid)
                )
            }

            // Publish only a fully initialized and configured prefix. A retry
            // always starts from a new staging directory.
            try fileManager.moveItem(at: stagingPrefix, to: environment.prefixURL)
            try graphicsBackendManager.prefixDidMove(in: environment, from: stagingPrefix)
            var ready = environment
            ready.state = .ready
            try write(ready)
        } catch {
            try? removePrefixIfPresent(stagingPrefix)
            try? removePrefixIfPresent(environment.prefixURL)
            var invalid = environment
            invalid.state = .invalid
            try? write(invalid)
            throw error
        }
    }

    func configure(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        guard environment.runtimeID == runtime.id else { throw EnvironmentManagerError.runtimeMismatch }
        try await applyConfiguration(environment, runtime: runtime)
        try write(environment)
    }

    private func applyConfiguration(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let winecfg = runtime.wineExecutable.deletingLastPathComponent().appending(path: "winecfg")
        let hasWinecfgLauncher = fileManager.isExecutableFile(atPath: winecfg.path)
        try await runConfigurationCommand(
            executable: hasWinecfgLauncher ? winecfg : runtime.wineExecutable,
            arguments: (hasWinecfgLauncher ? [] : ["winecfg"]) + ["/v", environment.configuration.windowsVersion],
            logName: "winecfg",
            environment: environment,
            runtime: runtime
        )

        // Wine's macOS Retina switch is a persistent Mac Driver registry value.
        // WINE_RETINA_MODE is not part of Wine's public prefix contract, so using
        // only that environment variable left newly-created prefixes unchanged.
        try await runConfigurationCommand(
            executable: runtime.wineExecutable,
            arguments: [
                "reg", "add", #"HKCU\Software\Wine\Mac Driver"#,
                "/v", "RetinaMode", "/t", "REG_SZ", "/d",
                environment.configuration.retinaModeEnabled ? "Y" : "N", "/f"
            ],
            logName: "wine-registry",
            environment: environment,
            runtime: runtime
        )

        // Prefixes imported from older Wine builds may explicitly disable the
        // SDL winebus backend. Normalize the documented WineBus switches so a
        // controller is published through HID, DirectInput and XInput.
        for (name, value) in [
            ("Enable SDL", "1"),
            ("Map Controllers", environment.configuration.forceXInput ? "1" : "0"),
            ("Split Controllers", "0"),
            ("DisableHidraw", "0")
        ] {
            try await runConfigurationCommand(
                executable: runtime.wineExecutable,
                arguments: [
                    "reg", "add", #"HKLM\System\CurrentControlSet\Services\WineBus"#,
                    "/v", name, "/t", "REG_DWORD", "/d", value, "/f"
                ],
                logName: "wine-controller-\(name.replacingOccurrences(of: " ", with: "-").lowercased())",
                environment: environment,
                runtime: runtime
            )
        }

        try await applyGraphicsBackend(environment, runtime: runtime)
    }

    private func applyGraphicsBackend(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let overrideNames = ["d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "d3d12", "dxgi"]
        for name in overrideNames {
            try await runConfigurationCommand(
                executable: runtime.wineExecutable,
                arguments: ["reg", "delete", #"HKCU\Software\Wine\DllOverrides"#, "/v", name, "/f"],
                logName: "graphics-reset-\(name)",
                environment: environment,
                runtime: runtime,
                allowsFailure: true
            )
        }
        do {
            let activation = try graphicsBackendManager.activate(
                environment.configuration.graphicsBackend,
                in: environment,
                runtime: runtime
            )
            for name in activation.dllOverrides {
                try await runConfigurationCommand(
                    executable: runtime.wineExecutable,
                    arguments: ["reg", "add", #"HKCU\Software\Wine\DllOverrides"#, "/v", name, "/t", "REG_SZ", "/d", "native,builtin", "/f"],
                    logName: "graphics-\(name)",
                    environment: environment,
                    runtime: runtime
                )
            }
        } catch {
            try? graphicsBackendManager.reset(environment)
            throw error
        }
    }

    private func runConfigurationCommand(
        executable: URL,
        arguments: [String],
        logName: String,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime,
        allowsFailure: Bool = false
    ) async throws {
        let request = ProcessLaunchRequest(
            executable: executable,
            arguments: arguments,
            environment: wineEnvironment(for: environment, runtime: runtime),
            currentDirectory: environment.rootURL,
            stdoutLog: environment.logsURL.appending(path: "\(logName).stdout.log"),
            stderrLog: environment.logsURL.appending(path: "\(logName).stderr.log")
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 || allowsFailure else {
            throw EnvironmentManagerError.configurationFailed(exitCode: result.exitCode, stderrLog: result.stderrLog)
        }
    }

    func validate(_ environment: ManagedBorealEnvironment) async throws -> EnvironmentValidation {
        let missing = missingPrefixPaths(at: environment.prefixURL)
        let stored = try? load(at: environment.rootURL)
        return EnvironmentValidation(missingPaths: missing, state: stored?.state ?? environment.state)
    }

    func dependencyStatuses(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> [RuntimeDependencyStatus] {
        RuntimeDependency.allCases.map { dependency in
            let marker = environment.prefixURL.appending(path: ".boreal-dependencies/\(dependency.rawValue)")
            let directories = ["system32", "syswow64"].map { environment.prefixURL.appending(path: "drive_c/windows/\($0)") }
            let hasLibraries = dependency.detectionLibraries.contains { library in
                directories.contains { $0.appending(path: library).path.isEmpty == false && fileManager.fileExists(atPath: $0.appending(path: library).path) }
            }
            return RuntimeDependencyStatus(dependency: dependency, state: (hasLibraries || fileManager.fileExists(atPath: marker.path)) ? .installed : .missing, detail: nil)
        }
    }

    func install(_ dependency: RuntimeDependency, in environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        guard environment.runtimeID == runtime.id else { throw EnvironmentManagerError.runtimeMismatch }
        // InstalledRuntime persists the resolved executable URLs, while the
        // package support directory has a stable location in every runtime.
        let packagedInstaller = runtime.rootURL.appending(path: "Support/winetricks")
        let winetricks = fileManager.isExecutableFile(atPath: packagedInstaller.path)
            ? packagedInstaller
            : try await ensureDependencyInstaller()
        let request = ProcessLaunchRequest(
            executable: winetricks,
            arguments: ["--unattended", dependency.winetricksVerb],
            environment: wineEnvironment(for: environment, runtime: runtime),
            currentDirectory: environment.rootURL,
            stdoutLog: environment.logsURL.appending(path: "dependency-\(dependency.rawValue).stdout.log"),
            stderrLog: environment.logsURL.appending(path: "dependency-\(dependency.rawValue).stderr.log")
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 else {
            throw EnvironmentManagerError.dependencyInstallationFailed(dependency: dependency, exitCode: result.exitCode, stderrLog: result.stderrLog)
        }
        let markers = environment.prefixURL.appending(path: ".boreal-dependencies", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: markers, withIntermediateDirectories: true)
        try Data("\(dependency.winetricksVerb)\n".utf8).write(to: markers.appending(path: dependency.rawValue), options: .atomic)
    }

    private func ensureDependencyInstaller() async throws -> URL {
        let installer = dependencyToolsURL.appending(path: "winetricks")
        if fileManager.isExecutableFile(atPath: installer.path) { return installer }
        guard let url = URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks") else {
            throw EnvironmentManagerError.dependencyInstallerMissing(installer)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count > 10_000, data.count < 2_000_000,
              data.starts(with: Data("#!/".utf8)) else {
            throw EnvironmentManagerError.dependencyInstallerDownloadFailed
        }
        try fileManager.createDirectory(at: dependencyToolsURL, withIntermediateDirectories: true)
        try data.write(to: installer, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installer.path)
        return installer
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

            let preferredNames = ["wineboot.stderr.log", "winecfg.stderr.log", "wine-registry.stderr.log"]
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
        let prefixMode = WinePrefixMode.resolve(
            requestedArchitecture: environment.configuration.architecture,
            runtimeSupportsWoW64: runtime.features?.wow64 == true
        )
        if let architecture = prefixMode.explicitWineArchitecture {
            values["WINEARCH"] = architecture
        } else {
            // Modern WoW64 runtimes create a combined prefix automatically and
            // reject a forced 32-bit prefix. Remove an inherited value as well.
            values.removeValue(forKey: "WINEARCH")
        }
        values["WINEESYNC"] = environment.configuration.esyncEnabled ? "1" : "0"
        values["WINEMSYNC"] = environment.configuration.msyncEnabled ? "1" : "0"
        values["WINE_FULLSCREEN_FSR"] = environment.configuration.fullscreenFSREnabled ? "1" : "0"
        values = ControllerWineSupport.applyingEnvironment(to: values)
        values.removeValue(forKey: "WINEDLLOVERRIDES")
        values["WINEDEBUG"] = values["WINEDEBUG"] ?? "-all"
        values["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":" + (values["PATH"] ?? "/usr/bin:/bin")
        values["WINE"] = runtime.wineExecutable.path
        values["WINE64"] = runtime.wineExecutable.path
        return values
    }

    private func waitForPrefixInitialization(_ prefix: URL) async throws -> Bool {
        for _ in 0..<prefixInitializationAttempts {
            try Task.checkCancellation()
            if missingPrefixPaths(at: prefix).isEmpty { return true }
            try await Task.sleep(for: prefixInitializationInterval)
        }
        return false
    }

    private func missingPrefixPaths(at prefix: URL) -> [String] {
        [
            prefix.appending(path: "drive_c", directoryHint: .isDirectory),
            prefix.appending(path: "dosdevices", directoryHint: .isDirectory),
            prefix.appending(path: "system.reg"),
            prefix.appending(path: "user.reg")
        ]
        .filter { !fileManager.fileExists(atPath: $0.path) }
        .map(\.path)
    }

    private func removePrefixIfPresent(_ prefix: URL) throws {
        let environmentRoot = prefix.deletingLastPathComponent().standardizedFileURL
        guard environmentRoot.deletingLastPathComponent() == environmentsURL.standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if fileManager.fileExists(atPath: prefix.path) {
            try fileManager.removeItem(at: prefix)
        }
    }

    private func logExcerpt(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let bounded = data.count > 16_384 ? data.suffix(16_384) : data[...]
        return String(decoding: bounded, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
