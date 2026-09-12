import CoreGraphics
import Foundation

nonisolated enum WineLaunchArguments {
    static func make(
        for plan: WindowsLaunchPlan,
        environmentID: UUID,
        displayWidth: Int,
        displayHeight: Int,
        prefixURL: URL? = nil
    ) -> [String] {
        let executablePath = prefixURL.map { windowsPath(for: plan.executable, prefixURL: $0) } ?? plan.executable.path
        if plan.executable.pathExtension.lowercased() == "msi" {
            return ["msiexec", "/i", executablePath] + plan.arguments
        }
        guard plan.overlayCompatibleFullscreen else {
            return [executablePath] + plan.arguments
        }
        let width = max(displayWidth, 1)
        let height = max(displayHeight, 1)
        let desktopName = "Boreal-\(environmentID.uuidString.prefix(6))"
        return [
            "explorer",
            "/desktop=\(desktopName),\(width)x\(height)",
            executablePath,
        ] + plan.arguments
    }

    static func windowsPath(for executable: URL, prefixURL: URL) -> String {
        let executablePath = executable.standardizedFileURL.path
        let driveCPath = prefixURL.appending(path: "drive_c", directoryHint: .isDirectory).standardizedFileURL.path
        let separator = "\\"

        if executablePath == driveCPath {
            return "C:\\"
        }
        if executablePath.hasPrefix(driveCPath + "/") {
            let relativePath = String(executablePath.dropFirst(driveCPath.count + 1))
            return "C:\\" + relativePath.replacingOccurrences(of: "/", with: separator)
        }

        // Wine's default Z: drive maps to the macOS filesystem root. This is
        // required for imported games that remain outside the managed prefix.
        let absolutePath = executablePath.hasPrefix("/") ? String(executablePath.dropFirst()) : executablePath
        return "Z:\\" + absolutePath.replacingOccurrences(of: "/", with: separator)
    }
}

actor WindowsProcessRunner: WindowsProcessRunning {
    private static let metalHUDEnvironmentKeys = [
        "MTL_HUD_ENABLED",
        "MTL_HUD_LOG_ENABLED",
        "MTL_HUD_ELEMENTS",
        "MTL_HUD_OPACITY",
        "MTL_HUD_DISABLE_MENU_BAR"
    ]
    // Xcode injects Metal/GPUTools validation into the app process when it is
    // launched from a scheme with GPU diagnostics enabled. Wine inherits the
    // parent environment, so forwarding these variables would also enable
    // Apple's MTLTools validation inside the Windows game process. D3DMetal
    // can then abort on resources still referenced by a command buffer while
    // the game is loading a save.
    private static let developerToolsEnvironmentKeys = [
        "GPUTOOLS_LOAD_GTMTLCAPTURE",
        "GPUTOOLS_XCODE_DEVELOPER_PATH",
        "MTL_DEBUG_LAYER",
        "MTL_DEBUG_LAYER_VALIDATE_LOAD_ACTIONS",
        "MTL_DEBUG_LAYER_VALIDATE_STORE_ACTIONS",
        "METAL_LOAD_INTERPOSER",
        "MTLCAPTURE_DESTINATION_DEVELOPER_TOOLS_ENABLE",
        "DYMTL_TOOLS_DYLIB_PATH",
        "DYLD_INSERT_LIBRARIES",
        "DYLD_LIBRARY_PATH",
        "DYLD_FRAMEWORK_PATH",
        "__XPC_DYLD_LIBRARY_PATH",
        "__XPC_DYLD_FRAMEWORK_PATH"
    ]
    private let processExecutor: any ProcessExecuting
    private let probeObservationWindow: Duration
    private var executorIDs: [UUID: UUID] = [:]
    private var directDrawRestorations: [UUID: DirectDrawShimRestoration] = [:]

    init(processExecutor: any ProcessExecuting, probeObservationWindow: Duration = .milliseconds(250)) {
        self.processExecutor = processExecutor
        self.probeObservationWindow = probeObservationWindow
    }

    /// Returns the currently running process(es) belonging to the launched
    /// game. The overlay uses these IDs for process-scoped CPU and memory
    /// instead of presenting the Wine launcher as if it were the game.
    func gameProcessIDs(
        session: WindowsProcessSession,
        environment: ManagedBorealEnvironment,
        runtime: InstalledRuntime
    ) async -> [Int32] {
        await runningGameProcessIDs(session: session, environment: environment)
    }

    func run(executable: URL, arguments: [String], environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession {
        let plan = WindowsLaunchPlan(
            executable: executable,
            arguments: arguments,
            environment: [:],
            workingDirectory: executable.deletingLastPathComponent()
        )
        return try await run(plan: plan, environment: environment, runtime: runtime)
    }

    func run(plan: WindowsLaunchPlan, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession {
        let sessionID = UUID()
        let traceSegment = plan.traceID?.description ?? sessionID.uuidString.lowercased()
        let stem = "launch-\(traceSegment)"
        let displayID = plan.overlayDisplayID.flatMap {
            let candidate = CGDirectDisplayID($0)
            let bounds = CGDisplayBounds(candidate)
            return CGDisplayIsOnline(candidate) != 0 && !bounds.isEmpty ? candidate : nil
        } ?? CGMainDisplayID()
        var launchPlan = plan
        if Heroes3DirectDrawCompatibility.usesWineBuiltinDirectDraw(for: plan.executable) {
            // The virtual explorer desktop keeps the legacy DirectDraw
            // frontbuffer alive but does not expose the resulting window on
            // this runtime. Let Heroes 3 create its own Wine window instead.
            launchPlan.overlayCompatibleFullscreen = false
        }
        if plan.executable.lastPathComponent.caseInsensitiveCompare("BoundByFlame.exe") == .orderedSame {
            // Bound by Flame remains alive inside the virtual explorer
            // desktop but does not expose its game window on this runtime.
            // Always use Wine's native window path, including for older
            // persisted profiles that still have overlay enabled.
            launchPlan.overlayCompatibleFullscreen = false
        }
        let wineArguments = WineLaunchArguments.make(
            for: launchPlan,
            environmentID: environment.id,
            displayWidth: Int(CGDisplayBounds(displayID).width),
            displayHeight: Int(CGDisplayBounds(displayID).height),
            prefixURL: environment.prefixURL
        )
        var processEnvironment = wineEnvironment(for: environment, runtime: runtime)
        processEnvironment.merge(plan.environment) { _, providerValue in providerValue }
        Self.removeDeveloperToolsEnvironment(from: &processEnvironment)
        if environment.configuration.graphicsConfiguration.capabilities(runtime: runtime).metalHUD != true {
            // A provider launch plan must not be able to opt into an
            // unverified HUD path after the managed environment sanitized it.
            for key in Self.metalHUDEnvironmentKeys {
                processEnvironment.removeValue(forKey: key)
            }
        }
        let prefixArchitecture = environment.configuration.resolvedPrefixArchitecture(
            runtimeSupportsWoW64: runtime.features?.resolvedArchitectureCapabilities.usesNewWoW64 == true
        )
        var fullscreenFSRConfiguration = environment.configuration.graphicsConfiguration
        fullscreenFSRConfiguration.overlayCompatibleFullscreen = launchPlan.overlayCompatibleFullscreen
        // Wine Fullscreen FSR1 is spatial and remains a separate setting. Do
        // not activate it on the same launch when the resolved temporal path
        // owns upscaling for the game.
        if launchPlan.temporalUpscalingPlan?.isActive == true {
            fullscreenFSRConfiguration.fullscreenFSREnabled = false
        }
        processEnvironment.removeValue(forKey: "WINE_FULLSCREEN_FSR")
        processEnvironment.removeValue(forKey: "WINE_FULLSCREEN_FSR_MODE")
        processEnvironment.removeValue(forKey: "WINE_FULLSCREEN_FSR_STRENGTH")
        processEnvironment.removeValue(forKey: "WINE_FULLSCREEN_FSR_CUSTOM_MODE")
        processEnvironment.removeValue(forKey: "D3DM_ENABLE_METALFX")
        processEnvironment.merge(fullscreenFSRConfiguration.launchEnvironment(runtime: runtime, architecture: prefixArchitecture)) { _, configured in configured }
        // The launch plan is the source of truth here. A per-game profile may
        // select D3DMetal even when the shared environment's persisted
        // renderer is different; using the environment alone would silently
        // skip the bridge for that launch.
        let resolvedGraphicsBackend = launchPlan.temporalUpscalingPlan?.effective == .metalFXBridge
            ? GraphicsBackend.d3dMetal
            : environment.configuration.graphicsConfiguration.resolvedBackend(
                runtime: runtime,
                architecture: prefixArchitecture
            )
        if launchPlan.temporalUpscalingPlan?.effective == .metalFXBridge,
           resolvedGraphicsBackend == .d3dMetal {
            applyMetalFXBridge(to: &processEnvironment, runtime: runtime)
        }
        if environment.configuration.graphicsBackend == .wineD3D,
           environment.configuration.graphicsFallback == .wineD3DVulkan {
            // The prefix may still contain a previously activated DXVK
            // DLL. Force Wine builtin D3D for this process as well, so the
            // first retry works even before the next environment reconfigure
            // has restored the managed prefix files.
            processEnvironment["WINED3D_RENDERER"] = "vulkan"
            let libraries = Set(RendererLaunchFailureDetector.builtinDLLOverrides(for: environment.configuration.graphicsAPI))
            let existing = processEnvironment["WINEDLLOVERRIDES"]?.split(separator: ";").map(String.init) ?? []
            let preserved = existing.filter { entry in
                let library = entry.split(separator: "=", maxSplits: 1).first.map { $0.lowercased() } ?? ""
                return !libraries.contains(library)
            }
            processEnvironment["WINEDLLOVERRIDES"] = (preserved + libraries.sorted().map { "\($0)=b" }).joined(separator: ";")
        }
        if environment.configuration.graphicsConfiguration.resolvedBackend(runtime: runtime, architecture: prefixArchitecture) == .dxvk,
           plan.executable.lastPathComponent.caseInsensitiveCompare("Darksiders2.exe") == .orderedSame {
            let configuration = environment.rootURL.appending(path: "Darksiders2-dxvk.conf")
            // Darksiders II renders its 3D scene correctly at ultrawide
            // resolutions, but its minimap markers are positioned against the
            // full 21:9 surface instead of the circular map. Expose only 16:9
            // D3D9 modes so fullscreen keeps the HUD geometry intact.
            try "d3d9.presentInterval = 0\ndxvk.tearFree = True\nd3d9.maxFrameLatency = 1\nd3d9.forceAspectRatio = \"16:9\"\n"
                .write(to: configuration, atomically: true, encoding: .utf8)
            processEnvironment["DXVK_CONFIG_FILE"] = configuration.path
        }
        if Heroes3DirectDrawCompatibility.usesWineBuiltinDirectDraw(for: plan.executable) {
            // Heroes 3 uses DirectDraw for its 2D surfaces and Bink videos.
            // WineD3D's GL/Vulkan paths leave its palettized menu surfaces
            // partially composed on this runtime. GDI preserves the old
            // DirectDraw blit and palette semantics needed by the menu/video
            // frontbuffer.
            // Keep this renderer override scoped to Heroes 3 only.
            processEnvironment["WINED3D_RENDERER"] = "gdi"
        }
        // The managed environment always owns these values. Provider metadata
        // cannot redirect a launch into another prefix or runtime search path.
        processEnvironment["WINEPREFIX"] = environment.prefixURL.path
        processEnvironment["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        let prefixMode = environment.configuration.resolvedPrefixMode(runtimeSupportsWoW64: runtime.features?.resolvedArchitectureCapabilities.usesNewWoW64 == true)
        if let architecture = prefixMode.explicitWineArchitecture {
            processEnvironment["WINEARCH"] = architecture
        } else {
            processEnvironment.removeValue(forKey: "WINEARCH")
        }
        let request = ProcessLaunchRequest(
            executable: runtime.wineExecutable,
            arguments: wineArguments,
            environment: processEnvironment,
            currentDirectory: plan.workingDirectory,
            stdoutLog: environment.logsURL.appending(path: "\(stem).stdout.log"),
            stderrLog: environment.logsURL.appending(path: "\(stem).stderr.log")
        )
        var directDrawRestoration: DirectDrawShimRestoration?
        do {
            directDrawRestoration = try Heroes3DirectDrawCompatibility.prepareIfNeeded(
                executable: plan.executable,
                environment: environment
            )
            let receipt = try await processExecutor.launch(request)
            executorIDs[sessionID] = receipt.id
            if let directDrawRestoration {
                directDrawRestorations[sessionID] = directDrawRestoration
            }
            return WindowsProcessSession(
                id: sessionID,
                environmentID: environment.id,
                launcherPID: receipt.pid,
                startedAt: receipt.startedAt,
                stdoutLog: receipt.stdoutLog,
                stderrLog: receipt.stderrLog,
                sessionScope: plan.sessionScope,
                processExecutableName: plan.processExecutableName,
                processExecutablePath: plan.processExecutablePath
            )
        } catch {
            if let directDrawRestoration { try? Heroes3DirectDrawCompatibility.restore(directDrawRestoration) }
            throw error
        }
    }

    func waitForExit(_ session: WindowsProcessSession) async throws -> ProcessExecutionResult {
        guard let id = executorIDs[session.id] else { throw ProcessRunnerError.sessionNotFound(session.id) }
        defer {
            executorIDs[session.id] = nil
            if let restoration = directDrawRestorations.removeValue(forKey: session.id) {
                try? Heroes3DirectDrawCompatibility.restore(restoration)
            }
        }
        return try await processExecutor.waitForExit(id)
    }

    func state(of session: WindowsProcessSession) async throws -> ProcessExecutionState {
        guard let id = executorIDs[session.id] else { throw ProcessRunnerError.sessionNotFound(session.id) }
        return try await processExecutor.state(of: id)
    }

    func stopApplication(_ session: WindowsProcessSession) async throws {
        guard let processID = executorIDs[session.id] else { throw ProcessRunnerError.sessionNotFound(session.id) }
        try await processExecutor.terminate(processID)
    }

    func environmentSessionState(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> EnvironmentSessionState {
        let request = controlRequest(
            executable: runtime.wineServerExecutable,
            arguments: ["-w"],
            name: "session-probe",
            environment: environment,
            runtime: runtime
        )
        guard let receipt = try? await processExecutor.launch(request) else { return .unknown }

        do {
            try await Task.sleep(for: probeObservationWindow)
            switch try await processExecutor.state(of: receipt.id) {
            case .terminated(let result):
                return result.exitCode == 0 ? .inactive : .unknown
            case .running:
                // This terminates only the local `wineserver -w` observer. It does
                // not send a control command to the environment's wineserver.
                await stopProbeObserver(receipt.id)
                return .active
            }
        } catch is CancellationError {
            await stopProbeObserver(receipt.id)
            return .unknown
        } catch {
            await stopProbeObserver(receipt.id)
            return .unknown
        }
    }

    func waitForEnvironmentSessionEnd(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let request = controlRequest(
            executable: runtime.wineServerExecutable,
            arguments: ["-w"],
            name: "session-wait",
            environment: environment,
            runtime: runtime
        )
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 else {
            throw ProcessRunnerError.launchFailed("wineserver -w exited with code \(result.exitCode).")
        }
    }

    func waitForProcessGroupEnd(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(120)
        var observedGameProcess = false
        while clock.now < deadline {
            try Task.checkCancellation()
            if await !runningGameProcessIDs(session: session, environment: environment).isEmpty {
                observedGameProcess = true
            } else if observedGameProcess {
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        // A Steam client can be slow to spawn the game or can have already
        // exited before monitoring starts. Do not leave playtime running
        // forever when the process list never provided positive evidence.
    }

    func stopProcessGroup(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        try await signalProcessGroup(
            session: session,
            environment: environment,
            signal: "-TERM",
            failureMessage: "The Steam game process could not be stopped."
        )
    }

    func forceQuitProcessGroup(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        try await signalProcessGroup(
            session: session,
            environment: environment,
            signal: "-KILL",
            failureMessage: "The Steam game process could not be force quit."
        )
    }

    private func signalProcessGroup(
        session: WindowsProcessSession,
        environment: ManagedBorealEnvironment,
        signal: String,
        failureMessage: String
    ) async throws {
        let processIDs = await runningGameProcessIDs(session: session, environment: environment)
        if processIDs.isEmpty {
            // The Steam launch request can still be the only observable
            // process while Steam is handing the request to an already-running
            // client. Stop that request, but never terminate the shared Wine
            // environment here.
            try? await stopApplication(session)
            return
        }

        for processID in processIDs {
            let request = ProcessLaunchRequest(
                executable: URL(fileURLWithPath: "/bin/kill"),
                arguments: [signal, String(processID)],
                environment: ProcessInfo.processInfo.environment,
                currentDirectory: environment.rootURL,
                stdoutLog: environment.logsURL.appending(path: "process-group-stop-\(processID).stdout.log"),
                stderrLog: environment.logsURL.appending(path: "process-group-stop-\(processID).stderr.log")
            )
            guard let receipt = try? await processExecutor.launch(request),
                  let result = try? await processExecutor.waitForExit(receipt.id),
                  result.exitCode == 0 else {
                throw ProcessRunnerError.launchFailed("\(failureMessage) (PID \(processID)).")
            }
        }
    }

    func terminateEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let request = controlRequest(executable: runtime.wineBootExecutable, arguments: ["--end-session"], name: "stop", environment: environment, runtime: runtime)
        if let receipt = try? await processExecutor.launch(request) { _ = try? await processExecutor.waitForExit(receipt.id) }
    }

    func forceQuitEnvironment(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        let request = controlRequest(executable: runtime.wineServerExecutable, arguments: ["-k"], name: "force-quit", environment: environment, runtime: runtime)
        let receipt = try await processExecutor.launch(request)
        let result = try await processExecutor.waitForExit(receipt.id)
        guard result.exitCode == 0 else {
            throw ProcessRunnerError.launchFailed("wineserver -k exited with code \(result.exitCode).")
        }
    }

    func forceQuit(_ session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        try await forceQuitEnvironment(environment: environment, runtime: runtime)
        if let processID = executorIDs[session.id] {
            try await processExecutor.forceTerminate(processID)
            _ = try? await processExecutor.waitForExit(processID)
        }
        if let restoration = directDrawRestorations.removeValue(forKey: session.id) {
            try? Heroes3DirectDrawCompatibility.restore(restoration)
        }
    }

    private func stopProbeObserver(_ id: UUID) async {
        try? await processExecutor.terminate(id)
        for _ in 0..<20 {
            if case .terminated = try? await processExecutor.state(of: id) { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        try? await processExecutor.forceTerminate(id)
    }

    private func runningGameProcessIDs(session: WindowsProcessSession, environment: ManagedBorealEnvironment) async -> [Int32] {
        let request = ProcessLaunchRequest(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,command="],
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: environment.rootURL,
            stdoutLog: environment.logsURL.appending(path: "process-group-\(session.id.uuidString).stdout.log"),
            stderrLog: environment.logsURL.appending(path: "process-group-\(session.id.uuidString).stderr.log")
        )
        guard let receipt = try? await processExecutor.launch(request),
              let result = try? await processExecutor.waitForExit(receipt.id),
              result.exitCode == 0,
              let output = try? String(contentsOf: result.stdoutLog, encoding: .utf8) else {
            return []
        }

        let executableName = session.processExecutableName?.lowercased()
        let executablePathHints = processPathHints(session.processExecutablePath, prefixURL: environment.prefixURL)
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard let pid = fields.first.flatMap({ Int32($0) }), fields.count > 1 else { return nil }
            let command = String(fields[1]).lowercased()
            if let executableName {
                guard command.contains(executableName) else { return nil }
                if !executablePathHints.isEmpty,
                   command.contains(":\\") || command.contains(":/") {
                    guard executablePathHints.contains(where: command.contains) else { return nil }
                }
                return pid
            }
            let excluded = ["steam.exe", "steamwebhelper.exe", "wineserver", "services.exe", "plugplay.exe", "explorer.exe"]
            guard command.contains(".exe"), !excluded.contains(where: command.contains) else { return nil }
            return pid
        }
    }

    private func processPathHints(_ unixPath: String?, prefixURL: URL) -> [String] {
        guard let unixPath else { return [] }
        let normalizedPath = URL(fileURLWithPath: unixPath).standardizedFileURL.path
        let driveCPath = prefixURL.appending(path: "drive_c", directoryHint: .isDirectory).standardizedFileURL.path
        let windowsPath: String
        if normalizedPath.hasPrefix(driveCPath + "/") {
            let relative = String(normalizedPath.dropFirst(driveCPath.count + 1))
            windowsPath = "c:\\" + relative.replacingOccurrences(of: "/", with: "\\")
        } else if normalizedPath.hasPrefix(prefixURL.standardizedFileURL.path + "/") {
            let relative = String(normalizedPath.dropFirst(prefixURL.standardizedFileURL.path.count + 1))
            windowsPath = "z:\\" + relative.replacingOccurrences(of: "/", with: "\\")
        } else {
            return []
        }
        return [windowsPath, windowsPath.replacingOccurrences(of: "\\", with: "/")]
    }

    private func controlRequest(executable: URL, arguments: [String], name: String, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) -> ProcessLaunchRequest {
        ProcessLaunchRequest(
            executable: executable,
            arguments: arguments,
            environment: wineEnvironment(for: environment, runtime: runtime),
            currentDirectory: environment.rootURL,
            stdoutLog: environment.logsURL.appending(path: "\(name).stdout.log"),
            stderrLog: environment.logsURL.appending(path: "\(name).stderr.log")
        )
    }

    private func applyMetalFXBridge(to values: inout [String: String], runtime: InstalledRuntime) {
        guard runtime.resolvedEngine == .gamePortingToolkit else { return }
        let componentStoreRoot = runtime.rootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Components", directoryHint: .isDirectory)
        let componentStore = GraphicsComponentStore(rootURL: componentStoreRoot)
        let version = "gptk-" + runtime.id
        guard let reference = componentStore.upscalingReference(for: .ngxToMetalFX, version: version),
              componentStore.contains(reference) else { return }
        let bridgeDirectory = componentStore
            .upscalingComponentURL(.ngxToMetalFX, version: reference.version)
            .appending(path: "x64-windows", directoryHint: .isDirectory)
        let requiredFiles = ["nvngx.dll", "nvapi64.dll"]
        guard requiredFiles.allSatisfy({ FileManager.default.isReadableFile(atPath: bridgeDirectory.appending(path: $0).path) }) else { return }

        values["D3DM_ENABLE_METALFX"] = "1"
        let existingPaths = values["WINEDLLPATH"]?.split(separator: ":").map(String.init) ?? []
        values["WINEDLLPATH"] = ([bridgeDirectory.path] + existingPaths).joined(separator: ":")
        let bridgeOverrides = ["nvngx=n", "nvapi64=n"]
        let existingOverrides = values["WINEDLLOVERRIDES"]?.split(separator: ";").map(String.init) ?? []
        let preserved = existingOverrides.filter { entry in
            let library = entry.split(separator: "=", maxSplits: 1).first.map { $0.lowercased() } ?? ""
            return !["nvngx", "nvapi64"].contains(library)
        }
        values["WINEDLLOVERRIDES"] = (preserved + bridgeOverrides).joined(separator: ";")
    }

    private func wineEnvironment(for environment: ManagedBorealEnvironment, runtime: InstalledRuntime) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        Self.removeDeveloperToolsEnvironment(from: &values)
        values["WINEPREFIX"] = environment.prefixURL.path
        let prefixMode = environment.configuration.resolvedPrefixMode(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true)
        if let architecture = prefixMode.explicitWineArchitecture {
            values["WINEARCH"] = architecture
        } else {
            // A current WoW64 runtime owns the prefix architecture. Also clear
            // any value inherited from Boreal's parent process.
            values.removeValue(forKey: "WINEARCH")
        }
        values.removeValue(forKey: "WINEESYNC")
        values.removeValue(forKey: "WINEMSYNC")
        values.removeValue(forKey: "WINE_FULLSCREEN_FSR")
        values.removeValue(forKey: "WINE_FULLSCREEN_FSR_MODE")
        values.removeValue(forKey: "WINE_FULLSCREEN_FSR_STRENGTH")
        values.removeValue(forKey: "WINE_FULLSCREEN_FSR_CUSTOM_MODE")
        values.removeValue(forKey: "D3DM_ENABLE_METALFX")
        values.removeValue(forKey: "WINEDLLPATH")
        if runtime.features?.esync == true { values["WINEESYNC"] = environment.configuration.esyncEnabled ? "1" : "0" }
        if runtime.features?.msync == true { values["WINEMSYNC"] = environment.configuration.msyncEnabled ? "1" : "0" }
        let prefixArchitecture = environment.configuration.resolvedPrefixArchitecture(runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true)
        let resolvedGraphicsBackend = environment.configuration.graphicsConfiguration.resolvedBackend(
            runtime: runtime,
            architecture: prefixArchitecture
        )
        if resolvedGraphicsBackend == .dxmt {
            let componentStoreRoot = runtime.rootURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Components", directoryHint: .isDirectory)
            let componentStore = GraphicsComponentStore(rootURL: componentStoreRoot)
            let dxmtUnixLibraries = environment.configuration.graphicsComponentReferences
                .first(where: { $0.component == .dxmt })
                .map { componentStore.componentURL(.dxmt, version: $0.version).appending(path: "x64-unix", directoryHint: .isDirectory) }
                ?? runtime.rootURL.appending(path: "GraphicsComponents/DXMT/x64-unix", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: dxmtUnixLibraries.appending(path: "winemetal.so").path) {
                values["WINEDLLPATH"] = dxmtUnixLibraries.path
            }
        }
        if resolvedGraphicsBackend == .dxvk {
            // MoltenVK dynamically grows exhausted descriptor pools. Its warning
            // for every allocation can otherwise write megabytes per minute.
            values["MVK_CONFIG_LOG_LEVEL"] = "0"
        }
        // winebus can use its bundled SDL backend to expose macOS controllers
        // as Windows HID/XInput devices. These also keep hot-plug events alive
        // after the Wine window becomes the foreground application.
        if runtime.features?.wineBusControllerMapping == true {
            values = ControllerWineSupport.applyingEnvironment(to: values)
        }
        // Prefix registry state owns renderer overrides. Clear only inherited
        // parent state here; a per-game launch plan may intentionally add a
        // legacy-wrapper override after this base environment is built.
        values.removeValue(forKey: "WINEDLLOVERRIDES")
        // FPS telemetry is high-frequency. Keeping Wine's broad warning channels
        // enabled can produce hundreds of megabytes per session and push the most
        // recent FPS record out of the sampler's bounded read window.
        // Keep Wine's error class even when verbose diagnostics are disabled.
        // Otherwise an early loader failure such as D3DMetal/dxgi status
        // c0000142 produces empty launch logs and Boreal reports a normal exit.
        var debugChannels = environment.configuration.debugLoggingEnabled ? "+all" : (values["WINEDEBUG"] ?? "-all")
        if !environment.configuration.debugLoggingEnabled && !debugChannels.contains("err+all") {
            debugChannels += ",err+all"
        }
        values["WINEDEBUG"] = debugChannels.contains("+fps") ? debugChannels : debugChannels + ",+fps"
        // Never inherit Metal HUD settings from Boreal's parent process. HUD
        // creates MTLTools resources and is unsafe when the selected runtime
        // has not explicitly declared support for it.
        for key in Self.metalHUDEnvironmentKeys {
            values.removeValue(forKey: key)
        }
        if environment.configuration.graphicsConfiguration.capabilities(runtime: runtime).metalHUD == true {
            // D3DMetal does not pass its presents through Wine's +fps channel.
            // Ask Metal HUD to emit per-frame present intervals to macOS's
            // unified log. The native HUD stays transparent because Boreal
            // renders those metrics in its own overlay.
            values["MTL_HUD_ENABLED"] = "1"
            values["MTL_HUD_LOG_ENABLED"] = "1"
            values["MTL_HUD_ELEMENTS"] = "fps,frameinterval"
            values["MTL_HUD_OPACITY"] = "0.0"
            values["MTL_HUD_DISABLE_MENU_BAR"] = "1"
        }
        values["PATH"] = runtime.wineExecutable.deletingLastPathComponent().path + ":" + (values["PATH"] ?? "/usr/bin:/bin")
        return values
    }

    private static func removeDeveloperToolsEnvironment(from values: inout [String: String]) {
        for key in developerToolsEnvironmentKeys {
            values.removeValue(forKey: key)
        }
    }
}
