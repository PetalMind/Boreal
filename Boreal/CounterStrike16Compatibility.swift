import Foundation

/// Launch the GoldSrc engine directly from its installation directory.
nonisolated enum CounterStrike16Compatibility {
    static func needsLegacyHost(executable: URL, arguments: [String], runtime: InstalledRuntime) -> Bool {
        targetsCounterStrike(arguments) && isPatchedEngine(executable) && (
            hostContains("wine-11.16", runtime: runtime)
                || hostContains("wine-11.17", runtime: runtime)
        )
    }

    static func legacyRuntime(in runtimes: [InstalledRuntime]) -> InstalledRuntime? {
        runtimes.first { isLegacyHost($0) && $0.features?.resolvedArchitectureCapabilities.canRunX86 == true }
    }

    static func launchAnalysis(_ analysis: ExecutableAnalysis, arguments: [String]) -> ExecutableAnalysis {
        guard targetsCounterStrike(arguments), let primary = analysis.primaryExecutable,
              isPatchedEngine(primary), let engine = engineExecutable(for: primary),
              analysis.executables.contains(where: { $0.url.standardizedFileURL == engine.standardizedFileURL }) else { return analysis }
        // The native hl.exe path does not execute the bundled .NET launchers.
        // Keep the engine's DLL dependencies, without installing dotnet48 for
        // those unused wrappers during preparation of its fresh prefix.
        return ExecutableAnalysis(
            executables: analysis.executables.filter { $0.url.standardizedFileURL == engine.standardizedFileURL },
            primaryExecutable: engine,
            relatedFiles: analysis.relatedFiles.filter {
                $0.pathExtension.lowercased() != "exe" || $0.standardizedFileURL == engine.standardizedFileURL
            }
        )
    }

    static func engineExecutable(for executable: URL, fileManager: FileManager = .default) -> URL? {
        let names: Set<String> = ["hl.exe", "cstrike.exe", "counter-strike 1.6.exe"]
        guard names.contains(executable.lastPathComponent.lowercased()) else { return nil }
        let root = executable.deletingLastPathComponent()
        let engine = root.appending(path: "hl.exe")
        guard [engine, root.appending(path: "hw.dll"), root.appending(path: "cstrike/liblist.gam")]
            .allSatisfy({ fileManager.isReadableFile(atPath: $0.path) }),
              WindowsExecutableArchitecture.inspect(engine) == .x86 else { return nil }
        return engine
    }

    static func applying(to plan: WindowsLaunchPlan, runtime: InstalledRuntime) -> WindowsLaunchPlan {
        guard let engine = engineExecutable(for: plan.executable) else { return plan }
        guard targetsCounterStrike(plan.arguments) else { return plan }
        var result = plan
        result.executable = engine
        result.workingDirectory = engine.deletingLastPathComponent()
        result.processExecutableName = engine.lastPathComponent
        result.processExecutablePath = engine.standardizedFileURL.path
        result.overlayCompatibleFullscreen = false
        let arguments = Set(result.arguments.map { $0.lowercased() })
        if !arguments.contains("-game") { result.arguments += ["-game", "cstrike"] }
        if arguments.isDisjoint(with: ["-gl", "-d3d", "-soft", "-software"]) {
            result.arguments.append("-gl")
        }
        if isPatchedEngine(engine), isLegacyHost(runtime) {
            // This host loads the patched GoldSrc engine, but its CoreAudio
            // initialization aborts on the current macOS. Scope the temporary
            // silent fallback to this engine and host, keeping other games intact.
            let overrides = result.environment["WINEDLLOVERRIDES"] ?? ""
            if !overrides.split(separator: ";").contains("winecoreaudio.drv=") {
                result.environment["WINEDLLOVERRIDES"] = overrides.isEmpty
                    ? "winecoreaudio.drv=" : overrides + ";winecoreaudio.drv="
            }
            for argument in ["-nosound", "-nojoy"] where !arguments.contains(argument) {
                result.arguments.append(argument)
            }
            if arguments.isDisjoint(with: ["-windowed", "-window", "-sw", "-startwindowed", "-full", "-fullscreen"]) {
                result.arguments += ["-windowed", "-w", "800", "-h", "600"]
            }
        }
        return result
    }

    private static func targetsCounterStrike(_ arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(where: { $0.lowercased() == "-game" }) else { return true }
        return arguments.indices.contains(index + 1) && arguments[index + 1].lowercased() == "cstrike"
    }

    private static func isPatchedEngine(_ executable: URL) -> Bool {
        guard let engine = engineExecutable(for: executable),
              let data = try? Data(contentsOf: engine.deletingLastPathComponent().appending(path: "hw.dll"), options: [.mappedIfSafe]) else { return false }
        return data.range(of: Data("hwpatcher.dll".utf8)) != nil
            && data.range(of: Data("_PatchEngine@4".utf8)) != nil
    }

    private static func isLegacyHost(_ runtime: InstalledRuntime) -> Bool {
        hostContains("wine-7.7 (Game Porting Toolkit 1.1)", runtime: runtime)
    }

    private static func hostContains(_ version: String, runtime: InstalledRuntime) -> Bool {
        // Imported GPTK bundle versions do not identify the embedded Wine host.
        let library = runtime.wineExecutable.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "lib/wine/x86_64-unix/ntdll.so")
        guard let data = try? Data(contentsOf: library, options: [.mappedIfSafe]) else { return false }
        return data.range(of: Data(version.utf8)) != nil
    }
}
