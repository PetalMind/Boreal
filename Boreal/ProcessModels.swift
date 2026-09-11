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
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL
    var overlayCompatibleFullscreen = false
    var overlayDisplayID: UInt32? = nil
    var sessionScope: SessionScope = .exclusiveEnvironment
    var processExecutableName: String? = nil
    var processExecutablePath: String? = nil
}

nonisolated enum GameLaunchCompatibilityError: LocalizedError, Sendable {
    case steamAppIDFileUnavailable(URL, underlying: String)
    case unityWinRTShimUnavailable(URL, underlying: String)
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
              let manifest = try? JSONDecoder().decode(DLSSUnlockerManifest.self, from: data),
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
            if let processPath = plan.processExecutablePath {
                return URL(fileURLWithPath: processPath)
            }
            if let gameDirectory {
                return gtaSanAndreasExecutable(in: gameDirectory, fileManager: fileManager)
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
                guard values.isRegularFile != true || values.isSymbolicLink != true else {
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
            restoreOriginalFiles(
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
              let manifest = try? JSONDecoder().decode(DLSSUnlockerManifest.self, from: data) else {
            throw GameLaunchCompatibilityError.dlssUnlockerIncompleteInstallation(managedRoot)
        }
        let disableRegistry = managedRoot.appending(path: "DisableSignatureOverride.reg")
        guard fileManager.isReadableFile(atPath: disableRegistry.path) else {
            throw GameLaunchCompatibilityError.dlssUnlockerIncompleteInstallation(managedRoot)
        }

        try await importRegistry(disableRegistry)
        let originalRoot = managedRoot.appending(path: "original", directoryHint: .isDirectory)
        restoreOriginalFiles(
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
    ) {
        for name in dlssUnlockerFiles {
            let destination = target.appending(path: name)
            if originalFiles.contains(name), fileManager.isReadableFile(atPath: originalRoot.appending(path: name).path) {
                if let data = try? Data(contentsOf: originalRoot.appending(path: name)) {
                    try? data.write(to: destination, options: .atomic)
                }
            } else {
                try? fileManager.removeItem(at: destination)
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

    static func prepare(
        application: WindowsApplication,
        environment: ManagedBorealEnvironment? = nil,
        runtime: InstalledRuntime? = nil
    ) throws {
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
}

nonisolated extension WindowsProcessRunning {
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
