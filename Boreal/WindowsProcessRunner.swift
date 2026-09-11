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

    private static func windowsPath(for executable: URL, prefixURL: URL) -> String {
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
    private let processExecutor: any ProcessExecuting
    private let probeObservationWindow: Duration
    private var executorIDs: [UUID: UUID] = [:]
    private var directDrawRestorations: [UUID: DirectDrawShimRestoration] = [:]

    init(processExecutor: any ProcessExecuting, probeObservationWindow: Duration = .milliseconds(250)) {
        self.processExecutor = processExecutor
        self.probeObservationWindow = probeObservationWindow
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
        let stem = "launch-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(sessionID.uuidString.prefix(8))"
        let displayID = plan.overlayDisplayID.flatMap {
            let candidate = CGDirectDisplayID($0)
            let bounds = CGDisplayBounds(candidate)
            return CGDisplayIsOnline(candidate) != 0 && !bounds.isEmpty ? candidate : nil
        } ?? CGMainDisplayID()
        var launchPlan = plan
        if plan.executable.lastPathComponent.caseInsensitiveCompare("Grim Dawn.exe") == .orderedSame {
            // Grim Dawn's D3D9 fullscreen swap chain is not compatible with
            // the virtual explorer desktop used to keep Boreal's overlay
            // visible. Native Wine fullscreen presents correctly with DXVK.
            launchPlan.overlayCompatibleFullscreen = false
        }
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
        let prefixArchitecture = environment.configuration.resolvedPrefixArchitecture(runtimeSupportsWoW64: runtime.features?.wow64 == true)
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
        let prefixMode = environment.configuration.resolvedPrefixMode(runtimeSupportsWoW64: runtime.features?.wow64 == true)
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
            return WindowsProcessSession(id: sessionID, environmentID: environment.id, launcherPID: receipt.pid, startedAt: receipt.startedAt, stdoutLog: receipt.stdoutLog, stderrLog: receipt.stderrLog)
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

    private func wineEnvironment(for environment: ManagedBorealEnvironment, runtime: InstalledRuntime) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["WINEPREFIX"] = environment.prefixURL.path
        let prefixMode = environment.configuration.resolvedPrefixMode(runtimeSupportsWoW64: runtime.features?.wow64 == true)
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
        if runtime.features?.esync == true { values["WINEESYNC"] = environment.configuration.esyncEnabled ? "1" : "0" }
        if runtime.features?.msync == true { values["WINEMSYNC"] = environment.configuration.msyncEnabled ? "1" : "0" }
        values.merge(environment.configuration.graphicsConfiguration.environment(runtime: runtime)) { _, configured in configured }
        let prefixArchitecture = environment.configuration.resolvedPrefixArchitecture(runtimeSupportsWoW64: runtime.features?.wow64 == true)
        if environment.configuration.graphicsConfiguration.resolvedBackend(runtime: runtime, architecture: prefixArchitecture) == .dxvk {
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
        let debugChannels = environment.configuration.debugLoggingEnabled ? "+all" : (values["WINEDEBUG"] ?? "-all")
        values["WINEDEBUG"] = debugChannels.contains("+fps") ? debugChannels : debugChannels + ",+fps"
        if environment.configuration.graphicsConfiguration.capabilities(runtime: runtime).metalHUD == true {
            // D3DMetal does not pass its presents through Wine's +fps channel.
            // Ask Metal HUD to emit per-frame present intervals to the launch
            // console instead. The native HUD stays transparent because Boreal
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
}
