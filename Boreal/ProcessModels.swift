import Foundation

nonisolated struct ProcessExecutionResult: Sendable, Equatable {
    let pid: Int32
    let startedAt: Date
    let terminatedAt: Date
    let exitCode: Int32
    let terminationReason: Int
    let stdoutLog: URL
    let stderrLog: URL
}

nonisolated struct WindowsProcessSession: Identifiable, Sendable, Hashable {
    let id: UUID
    let environmentID: UUID
    let launcherPID: Int32
    let startedAt: Date
    let stdoutLog: URL
    let stderrLog: URL
    /// Steam keeps its client and wineserver alive after a game exits, so its
    /// user-visible session must be tracked by the game process group.
    let sessionScope: SessionScope
    let processExecutableName: String?
    let processExecutablePath: String?

    init(
        id: UUID,
        environmentID: UUID,
        launcherPID: Int32,
        startedAt: Date,
        stdoutLog: URL,
        stderrLog: URL,
        sessionScope: SessionScope = .exclusiveEnvironment,
        processExecutableName: String? = nil,
        processExecutablePath: String? = nil
    ) {
        self.id = id
        self.environmentID = environmentID
        self.launcherPID = launcherPID
        self.startedAt = startedAt
        self.stdoutLog = stdoutLog
        self.stderrLog = stderrLog
        self.sessionScope = sessionScope
        self.processExecutableName = processExecutableName
        self.processExecutablePath = processExecutablePath
    }
}

nonisolated struct WindowsLaunchPlan: Sendable, Hashable {
    var traceID: OperationTraceID? = nil
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL
    var overlayCompatibleFullscreen = false
    var overlayDisplayID: UInt32? = nil
    var sessionScope: SessionScope = .exclusiveEnvironment
    var processExecutableName: String? = nil
    var processExecutablePath: String? = nil
    var temporalUpscalingPlan: TemporalUpscalingPlan? = nil
    var configurationFingerprint: String? = nil
}

/// A provider launch is a recipe, not a shell command. The optional wrapper
/// describes a typed parent process (for example a third-party launcher) and
/// is intentionally represented as an executable plus argv/environment only.
/// No arbitrary shell or pre-launch script can enter this model.
nonisolated struct LaunchWrapper: Sendable, Hashable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL
}

nonisolated struct LaunchProcessExpectation: Sendable, Hashable {
    var executableName: String?
    var executablePath: String?
    var requiresParentProcess: Bool

    init(
        executableName: String? = nil,
        executablePath: String? = nil,
        requiresParentProcess: Bool = false
    ) {
        self.executableName = executableName
        self.executablePath = executablePath
        self.requiresParentProcess = requiresParentProcess
    }
}

nonisolated struct LaunchRecipe: Sendable, Hashable {
    var provider: GameLibraryProvider
    var externalID: String
    var main: WindowsLaunchPlan
    var wrapper: LaunchWrapper?
    var processExpectation: LaunchProcessExpectation
    var sessionPolicy: SessionScope

    init(
        provider: GameLibraryProvider,
        externalID: String,
        main: WindowsLaunchPlan,
        wrapper: LaunchWrapper? = nil,
        processExpectation: LaunchProcessExpectation = LaunchProcessExpectation(),
        sessionPolicy: SessionScope? = nil
    ) {
        self.provider = provider
        self.externalID = externalID
        self.main = main
        self.wrapper = wrapper
        self.processExpectation = processExpectation
        self.sessionPolicy = sessionPolicy ?? main.sessionScope
    }

    /// Current process execution is still normalized to a WindowsLaunchPlan.
    /// A future wrapper-aware runner can consume `wrapper` without weakening
    /// the provider contract or reintroducing shell execution.
    var windowsPlan: WindowsLaunchPlan { main }
}

nonisolated enum GameLaunchCompatibilityError: LocalizedError, Sendable {
    case steamAppIDFileUnavailable(URL, underlying: String)
    case unityWinRTShimUnavailable(URL, underlying: String)
    case grimDawnSettingsUnavailable(URL, underlying: String)
    case dlssUnlockerArchiveUnsupported(URL)
    case dlssUnlockerArchiveUnsafe(String)
    case dlssUnlockerMissingFiles([String])
    case dlssUnlockerTargetUnavailable(URL)
    case dlssUnlockerAlreadyInstalled(URL)
    case dlssUnlockerIncompleteInstallation(URL)
    case dlssUnlockerOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .steamAppIDFileUnavailable(let url, let underlying):
            "Boreal couldn’t prepare Torchlight II for direct launch. The file \(url.path) could not be written: \(underlying)"
        case .unityWinRTShimUnavailable(let url, let underlying):
            "Boreal couldn’t prepare Tainted Grail’s Unity runtime compatibility file at \(url.path): \(underlying)"
        case .grimDawnSettingsUnavailable(let url, let underlying):
            "Boreal couldn’t prepare Grim Dawn’s display settings at \(url.path): \(underlying)"
        case .dlssUnlockerArchiveUnsupported(let url):
            "The GTA San Andreas DLSS Unlocker must be supplied as a ZIP archive: \(url.lastPathComponent)."
        case .dlssUnlockerArchiveUnsafe(let path):
            "The DLSS Unlocker archive contains an unsafe path: \(path)"
        case .dlssUnlockerMissingFiles(let files):
            "The DLSS Unlocker archive is incomplete. Missing: \(files.joined(separator: ", "))."
        case .dlssUnlockerTargetUnavailable(let url):
            "Boreal couldn’t find a writable San Andreas executable next to \(url.path)."
        case .dlssUnlockerAlreadyInstalled(let url):
            "The GTA San Andreas DLSS Unlocker is already installed next to \(url.path). Remove it before installing another version."
        case .dlssUnlockerIncompleteInstallation(let url):
            "An incomplete Boreal DLSS Unlocker backup was found at \(url.path). The installation was left untouched for safety."
        case .dlssUnlockerOperationFailed(let detail):
            "Boreal couldn’t complete the GTA San Andreas DLSS Unlocker operation: \(detail)"
        }
    }
}

/// Applies compatibility files that are required by a game's own startup
/// code when the game is launched outside its original store client.
nonisolated enum GameLaunchCompatibility {
    private static let torchlightAppID = "200710"
    private static let taintedGrailIDs: Set<String> = ["1887281589", "1466060"]
    static let gtaSanAndreasDefinitiveEditionSteamAppID = "1547000"
    private static let dlssUnlockerFiles = ["nvngx.dll", "nvngx.ini", "winmm.dll"]
    private static let dlssUnlockerRegistryFiles = ["EnableSignatureOverride.reg", "DisableSignatureOverride.reg"]
    private static let dlssUnlockerDirectoryName = ".boreal-dlss-unlocker"

    private struct DLSSUnlockerManifest: Codable {
        let originalFiles: [String]
        let archiveSHA256: String
        let installedAt: Date
    }

    private struct ToolResult {
        let exitCode: Int32
        let output: String
    }

    /// The linked mod is a game-local DLL wrapper for the Unreal GTA SA
    /// Definitive Edition build. It is intentionally not advertised for the
    /// original 2004 executable or for other GTA titles.
    static func supportsDLSSUnlocker(for application: WindowsApplication) -> Bool {
        if application.storeProvider == .steam,
           application.storeExternalID == gtaSanAndreasDefinitiveEditionSteamAppID {
            return true
        }
        let normalizedName = application.name.lowercased()
        return normalizedName.contains("san andreas")
            && normalizedName.contains("definitive edition")
    }

    static func gtaSanAndreasExecutable(in gameRoot: URL, fileManager: FileManager = .default) -> URL? {
        let candidates = [
            gameRoot.appending(path: "Gameface/Binaries/Win64/SanAndreas.exe"),
            gameRoot.appending(path: "SanAndreas.exe")
        ]
        return candidates.first { fileManager.isReadableFile(atPath: $0.path) }
    }

    static func isDLSSUnlockerInstalled(
        nextTo gameExecutable: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let directory = gameExecutable.deletingLastPathComponent().standardizedFileURL
        let root = directory.appending(path: dlssUnlockerDirectoryName, directoryHint: .isDirectory)
        let manifestURL = root.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? makeDecoder().decode(DLSSUnlockerManifest.self, from: data),
              manifest.originalFiles.allSatisfy({ dlssUnlockerFiles.contains($0) }) else { return false }
        return dlssUnlockerFiles.allSatisfy {
            let values = try? directory.appending(path: $0).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true
        }
    }

    /// Adds the exact runtime behavior required by the mod to a launch plan.
    /// Steam's visible executable is steam.exe, so the real game executable
    /// may come from processExecutablePath or the resolved Steam game root.
    static func applying(
        to plan: WindowsLaunchPlan,
        application: WindowsApplication,
        gameDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> WindowsLaunchPlan {
        guard supportsDLSSUnlocker(for: application) else { return plan }
        let gameExecutable: URL? = {
            if let gameDirectory,
               let executable = gtaSanAndreasExecutable(in: gameDirectory, fileManager: fileManager) {
                return executable
            }
            if let processPath = plan.processExecutablePath {
                return URL(fileURLWithPath: processPath)
            }
            if let executable = gtaSanAndreasExecutable(
                in: plan.executable.deletingLastPathComponent(),
                fileManager: fileManager
            ) {
                return executable
            }
            return plan.executable
        }()
        guard let gameExecutable,
              isDLSSUnlockerInstalled(nextTo: gameExecutable, fileManager: fileManager) else { return plan }

        var configured = plan
        if !configured.arguments.contains(where: { $0.caseInsensitiveCompare("-dx12") == .orderedSame }) {
            configured.arguments.append("-dx12")
        }
        let existing = configured.environment["WINEDLLOVERRIDES"]?
            .split(separator: ";")
            .map(String.init) ?? []
        let preserved = existing.filter {
            let library = $0.split(separator: "=", maxSplits: 1).first.map { $0.lowercased() } ?? ""
            return library != "winmm"
        }
        configured.environment["WINEDLLOVERRIDES"] = (preserved + ["winmm=n,b"]).joined(separator: ";")
        return configured
    }

    static func installDLSSUnlocker(
        from archive: URL,
        nextTo gameExecutable: URL,
        importRegistry: @escaping @Sendable (URL) async throws -> Void,
        fileManager: FileManager = .default
    ) async throws {
        guard archive.pathExtension.caseInsensitiveCompare("zip") == .orderedSame,
              fileManager.isReadableFile(atPath: archive.path) else {
            throw GameLaunchCompatibilityError.dlssUnlockerArchiveUnsupported(archive)
        }
        let target = gameExecutable.deletingLastPathComponent().standardizedFileURL
        guard fileManager.isReadableFile(atPath: gameExecutable.path),
              fileManager.isWritableFile(atPath: target.path) else {
            throw GameLaunchCompatibilityError.dlssUnlockerTargetUnavailable(gameExecutable)
        }

        let managedRoot = target.appending(path: dlssUnlockerDirectoryName, directoryHint: .isDirectory)
        let manifestURL = managedRoot.appending(path: "manifest.json")
        guard !fileManager.fileExists(atPath: manifestURL.path) else {
            throw GameLaunchCompatibilityError.dlssUnlockerAlreadyInstalled(gameExecutable)
        }
        if fileManager.fileExists(atPath: managedRoot.path) {
            throw GameLaunchCompatibilityError.dlssUnlockerIncompleteInstallation(managedRoot)
        }

        let extractionRoot = fileManager.temporaryDirectory
            .appending(path: "boreal-dlss-unlocker-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractionRoot) }

        let listing = try await runTool(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", archive.path]
        )
        guard listing.exitCode == 0 else {
            throw GameLaunchCompatibilityError.dlssUnlockerOperationFailed("The ZIP archive could not be read.")
        }
        for entry in listing.output.split(whereSeparator: \.isNewline).map(String.init) {
            let normalized = entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
            guard !normalized.hasPrefix("/"),
                  !normalized.split(separator: "/").contains(".."),
                  !normalized.contains("\\") else {
                throw GameLaunchCompatibilityError.dlssUnlockerArchiveUnsafe(entry)
            }
        }

        let extraction = try await runTool(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archive.path, extractionRoot.path]
        )
        guard extraction.exitCode == 0 else {
            throw GameLaunchCompatibilityError.dlssUnlockerOperationFailed("The ZIP archive could not be extracted.")
        }

        var sourceFiles: [String: URL] = [:]
        guard let enumerator = fileManager.enumerator(
            at: extractionRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw GameLaunchCompatibilityError.dlssUnlockerOperationFailed("The extracted archive is empty.")
        }
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let name = item.lastPathComponent
            guard let expected = (dlssUnlockerFiles + dlssUnlockerRegistryFiles).first(where: {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }) else { continue }
            guard sourceFiles[expected] == nil else {
                throw GameLaunchCompatibilityError.dlssUnlockerOperationFailed("The archive contains more than one \(expected) file.")
            }
            sourceFiles[expected] = item
        }
        let required = dlssUnlockerFiles + dlssUnlockerRegistryFiles
        let missing = required.filter { sourceFiles[$0] == nil }
        guard missing.isEmpty else { throw GameLaunchCompatibilityError.dlssUnlockerMissingFiles(missing) }

        let archiveSHA256 = try RuntimeSecurity.sha256(of: archive)
        let originalRoot = managedRoot.appending(path: "original", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: originalRoot, withIntermediateDirectories: true)
        var originalFiles: [String] = []
        do {
            for name in dlssUnlockerFiles {
                let destination = target.appending(path: name)
                let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else {
                    throw GameLaunchCompatibilityError.dlssUnlockerOperationFailed("The target file \(name) is a symbolic link.")
                }
                if values.isRegularFile == true {
                    try fileManager.copyItem(at: destination, to: originalRoot.appending(path: name))
                    originalFiles.append(name)
                }
            }
            let backup = DLSSUnlockerManifest(
                originalFiles: originalFiles,
                archiveSHA256: archiveSHA256,
                installedAt: Date()
            )
            try makeEncoder().encode(backup).write(to: managedRoot.appending(path: "backup.json"), options: .atomic)
            try fileManager.copyItem(
                at: sourceFiles["DisableSignatureOverride.reg"]!,
                to: managedRoot.appending(path: "DisableSignatureOverride.reg")
            )

            for name in dlssUnlockerFiles {
                let data = try Data(contentsOf: sourceFiles[name]!)
                try data.write(to: target.appending(path: name), options: .atomic)
            }
            try await importRegistry(sourceFiles["EnableSignatureOverride.reg"]!)
            try makeEncoder().encode(backup).write(to: manifestURL, options: .atomic)
        } catch {
            try restoreOriginalFiles(
                target: target,
                originalRoot: originalRoot,
                originalFiles: originalFiles,
                fileManager: fileManager
            )
            try? fileManager.removeItem(at: managedRoot)
            throw error
        }
    }

    static func uninstallDLSSUnlocker(
        nextTo gameExecutable: URL,
        importRegistry: @escaping @Sendable (URL) async throws -> Void,
        fileManager: FileManager = .default
    ) async throws {
        let target = gameExecutable.deletingLastPathComponent().standardizedFileURL
        let managedRoot = target.appending(path: dlssUnlockerDirectoryName, directoryHint: .isDirectory)
        let manifestURL = managedRoot.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? makeDecoder().decode(DLSSUnlockerManifest.self, from: data) else {
            throw GameLaunchCompatibilityError.dlssUnlockerIncompleteInstallation(managedRoot)
        }
        let disableRegistry = managedRoot.appending(path: "DisableSignatureOverride.reg")
        guard fileManager.isReadableFile(atPath: disableRegistry.path) else {
            throw GameLaunchCompatibilityError.dlssUnlockerIncompleteInstallation(managedRoot)
        }

        try await importRegistry(disableRegistry)
        let originalRoot = managedRoot.appending(path: "original", directoryHint: .isDirectory)
        try restoreOriginalFiles(
            target: target,
            originalRoot: originalRoot,
            originalFiles: manifest.originalFiles,
            fileManager: fileManager
        )
        try fileManager.removeItem(at: managedRoot)
    }

    private static func restoreOriginalFiles(
        target: URL,
        originalRoot: URL,
        originalFiles: [String],
        fileManager: FileManager
    ) throws {
        for name in dlssUnlockerFiles {
            let destination = target.appending(path: name)
            if originalFiles.contains(name), fileManager.isReadableFile(atPath: originalRoot.appending(path: name).path) {
                let data = try Data(contentsOf: originalRoot.appending(path: name))
                try data.write(to: destination, options: .atomic)
            } else {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
            }
        }
    }

    private static func runTool(executable: URL, arguments: [String]) async throws -> ToolResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw GameLaunchCompatibilityError.dlssUnlockerOperationFailed("Required system tool is missing: \(executable.path)")
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = pipe
        process.standardError = pipe
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ToolResult(
                    exitCode: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self)
                ))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GameLaunchCompatibilityError.dlssUnlockerOperationFailed(error.localizedDescription))
            }
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func prepare(
        application: WindowsApplication,
        environment: ManagedBorealEnvironment? = nil,
        runtime: InstalledRuntime? = nil
    ) throws {
        if application.storeProvider == .gog,
           application.storeExternalID == "1449651388",
           let environment {
            try prepareGrimDawnDisplaySettings(in: environment)
        }

        if let externalID = application.storeExternalID,
           taintedGrailIDs.contains(externalID),
           runtime?.resolvedEngine == .gamePortingToolkit,
           let environment {
            try prepareTaintedGrailWinRTShim(in: environment)
        }

        guard application.usesStoreMetadataOnly,
              application.storeProvider == .steam,
              application.storeExternalID == torchlightAppID else { return }

        let executable = URL(fileURLWithPath: application.executablePath)
        guard executable.lastPathComponent.caseInsensitiveCompare("Torchlight2.exe") == .orderedSame else { return }

        let appIDFile = executable.deletingLastPathComponent().appending(path: "steam_appid.txt")
        let expected = Data("\(torchlightAppID)\n".utf8)
        if let existing = try? Data(contentsOf: appIDFile), existing == expected {
            return
        }

        do {
            try expected.write(to: appIDFile, options: .atomic)
        } catch {
            throw GameLaunchCompatibilityError.steamAppIDFileUnavailable(
                appIDFile,
                underlying: error.localizedDescription
            )
        }
    }

    /// Grim Dawn persists its display mode outside the installation directory.
    /// Its exclusive fullscreen path can leave DXVK with a black, non-presenting
    /// surface on macOS. Keep the user's settings intact, but force the game's
    /// supported borderless mode before every launch. The original file is
    /// retained once so this compatibility change is reversible.
    private static func prepareGrimDawnDisplaySettings(
        in environment: ManagedBorealEnvironment,
        fileManager: FileManager = .default
    ) throws {
        let usersRoot = environment.prefixURL
            .appending(path: "drive_c/users", directoryHint: .isDirectory)
        let userDirectories = (try? fileManager.contentsOfDirectory(
            at: usersRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        guard let userDirectory = userDirectories.first(where: { url in
            url.lastPathComponent.caseInsensitiveCompare("Public") != .orderedSame
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }) else {
            throw GameLaunchCompatibilityError.grimDawnSettingsUnavailable(
                usersRoot,
                underlying: "the Wine user directory could not be found"
            )
        }

        let documentsCandidates = ["Documents", "My Documents"].map {
            userDirectory.appending(path: $0, directoryHint: .isDirectory)
        }
        guard let documents = documentsCandidates.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) else {
            throw GameLaunchCompatibilityError.grimDawnSettingsUnavailable(
                userDirectory,
                underlying: "the Wine Documents directory could not be found"
            )
        }
        let settingsDirectory = documents
            .appending(path: "My Games/Grim Dawn/Settings", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        let optionsURL = settingsDirectory.appending(path: "options.txt")
        let backupURL = settingsDirectory.appending(path: "options.txt.boreal-backup")

        do {
            try fileManager.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)
            let existing = try? String(contentsOf: optionsURL, encoding: .utf8)
            if existing != nil, !fileManager.fileExists(atPath: backupURL.path) {
                try existing!.write(to: backupURL, atomically: true, encoding: .utf8)
            }

            var lines = (existing ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let replacement = "screenMode                = 1"
            if let index = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .hasPrefix("screenmode")
            }) {
                lines[index] = replacement
            } else {
                lines.append(replacement)
            }
            let output = lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
            try output.write(to: optionsURL, atomically: true, encoding: .utf8)
        } catch {
            throw GameLaunchCompatibilityError.grimDawnSettingsUnavailable(
                optionsURL,
                underlying: error.localizedDescription
            )
        }
    }

    private static func prepareTaintedGrailWinRTShim(in environment: ManagedBorealEnvironment) throws {
        let system32 = environment.prefixURL.appending(path: "drive_c/windows/system32", directoryHint: .isDirectory)
        let source = system32.appending(path: "combase.dll")
        let destination = system32.appending(path: "api-ms-win-core-winrt-robuffer-l1-1-0.dll")
        do {
            let expected = try Data(contentsOf: source)
            if let existing = try? Data(contentsOf: destination), existing == expected { return }
            try expected.write(to: destination, options: .atomic)
        } catch {
            throw GameLaunchCompatibilityError.unityWinRTShimUnavailable(
                destination,
                underlying: error.localizedDescription
            )
        }
    }
}

nonisolated struct ProcessLaunchRequest: Sendable {
    let executable: URL
    var arguments: [String] = []
    var environment: [String: String] = [:]
    var currentDirectory: URL?
    var standardInput: Data? = nil
    let stdoutLog: URL
    let stderrLog: URL
}

nonisolated struct ProcessLaunchReceipt: Sendable, Hashable {
    let id: UUID
    let pid: Int32
    let startedAt: Date
    let stdoutLog: URL
    let stderrLog: URL
}

nonisolated enum ProcessExecutionState: Sendable, Equatable {
    case running(pid: Int32)
    case terminated(ProcessExecutionResult)
}

nonisolated enum EnvironmentSessionState: Sendable, Equatable {
    case unknown
    case inactive
    case active
}

nonisolated enum SessionScope: String, Codable, Sendable, Hashable {
    case exclusiveEnvironment
    case processGroup
}

nonisolated enum ProcessRunnerError: LocalizedError, Sendable {
    case executableMissing(URL)
    case launchFailed(String)
    case sessionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let url): "Executable not found at \(url.path)."
        case .launchFailed(let reason): "The process couldn’t start: \(reason)"
        case .sessionNotFound: "The process session no longer exists."
        }
    }
}

nonisolated protocol ProcessExecuting: Sendable {
    func launch(_ request: ProcessLaunchRequest) async throws -> ProcessLaunchReceipt
    func waitForExit(_ id: UUID) async throws -> ProcessExecutionResult
    func state(of id: UUID) async throws -> ProcessExecutionState
    func terminate(_ id: UUID) async throws
    func forceTerminate(_ id: UUID) async throws
}

nonisolated protocol WindowsProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession
    func run(plan: WindowsLaunchPlan, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws -> WindowsProcessSession
    func waitForExit(_ session: WindowsProcessSession) async throws -> ProcessExecutionResult
    func state(of session: WindowsProcessSession) async throws -> ProcessExecutionState
    func stopApplication(_ session: WindowsProcessSession) async throws
    func stopProcessGroup(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func forceQuitProcessGroup(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func environmentSessionState(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> EnvironmentSessionState
    func waitForEnvironmentSessionEnd(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func waitForProcessGroupEnd(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func terminateEnvironmentSession(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func forceQuitEnvironment(environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func forceQuit(_ session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func gameProcessIDs(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> [Int32]
}

nonisolated extension WindowsProcessRunning {
    func gameProcessIDs(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> [Int32] { [] }

    /// Runners that do not have a native process-group implementation retain
    /// the old launcher-stop behavior until they can provide one.
    func stopProcessGroup(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        try await stopApplication(session)
    }

    func forceQuitProcessGroup(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        try await forceQuit(session, environment: environment, runtime: runtime)
    }

    /// Preserve the old behavior for runners that do not provide a process
    /// group implementation yet.
    func waitForProcessGroupEnd(session: WindowsProcessSession, environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws {
        try await waitForEnvironmentSessionEnd(environment: environment, runtime: runtime)
    }
}
