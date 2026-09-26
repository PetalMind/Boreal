import Foundation

// MARK: - Automatic compatibility preparation

nonisolated enum CompatibilityPreparationState: String, Codable, Sendable, Hashable {
    case idle
    case analyzing
    case preparingRuntime
    case creatingPrefix
    case installingDependencies
    case configuringGraphics
    case validating
    case ready
    case failed

    var userMessage: String {
        switch self {
        case .idle: ""
        case .analyzing: "Analyzing game…"
        case .preparingRuntime: "Preparing Wine…"
        case .creatingPrefix: "Creating environment…"
        case .installingDependencies: "Installing required components…"
        case .configuringGraphics: "Configuring graphics…"
        case .validating: "Validating compatibility…"
        case .ready: "Compatibility ready"
        case .failed: "Compatibility preparation failed"
        }
    }
}

nonisolated enum CompatibilityExecutableRole: String, Codable, Sendable, Hashable {
    case game
    case launcher
    case installer
    case updater
    case helper
    case uninstaller
    case unknown
}

/// Bounded, read-only inventory used by compatibility analysis. The analyzer
/// needs PE files and media assets, but should not read every large archive or
/// video in a game installation.
nonisolated enum CompatibilityFileInventory {
    private static let relevantExtensions: Set<String> = [
        "exe", "dll", "sys", "wmv", "asf", "wma", "avi", "mp4", "bik", "bk2", "xml", "json", "ini"
    ]
    private static let mediaExtensions: Set<String> = ["wmv", "asf", "wma", "avi", "mp4"]

    static func relatedFiles(
        in root: URL,
        excluding excludedURL: URL? = nil,
        fileManager: FileManager = .default,
        limit: Int = 512
    ) -> [URL] {
        let normalizedExcluded = excludedURL?.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: root.standardizedFileURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [(URL, Int)] = []
        for case let url as URL in enumerator {
            let normalized = url.standardizedFileURL
            guard normalized != normalizedExcluded,
                  relevantExtensions.contains(normalized.pathExtension.lowercased()),
                  let values = try? normalized.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= 16 * 1_024 * 1_024 else { continue }
            let ext = normalized.pathExtension.lowercased()
            let priority = ext == "exe" || ext == "dll" || ext == "sys" ? 0 : (mediaExtensions.contains(ext) ? 1 : 2)
            candidates.append((normalized, priority))
        }

        return candidates
            .sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                return $0.0.path.localizedStandardCompare($1.0.path) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    static func logFiles(
        in directory: URL?,
        fileManager: FileManager = .default,
        limit: Int = 32
    ) -> [URL] {
        guard let directory,
              let enumerator = fileManager.enumerator(
                  at: directory.standardizedFileURL,
                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.pathExtension.caseInsensitiveCompare("log") == .orderedSame,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= 2 * 1_024 * 1_024 else { return nil }
            return url.standardizedFileURL
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        .suffix(limit)
        .reversed()
        .map { $0 }
    }
}

nonisolated struct AnalyzedExecutable: Codable, Hashable, Sendable, Identifiable {
    let id: URL
    let url: URL
    let architecture: WindowsExecutableArchitecture
    let role: CompatibilityExecutableRole
    let discoveryScore: Int
}

nonisolated struct ExecutableAnalysis: Codable, Hashable, Sendable {
    let executables: [AnalyzedExecutable]
    let primaryExecutable: URL?
    let relatedFiles: [URL]

    init(executables: [AnalyzedExecutable], primaryExecutable: URL?, relatedFiles: [URL] = []) {
        self.executables = executables
        self.primaryExecutable = primaryExecutable
        self.relatedFiles = relatedFiles
    }

    var gameExecutable: AnalyzedExecutable? {
        guard let primaryExecutable else { return nil }
        return executables.first { $0.url.standardizedFileURL == primaryExecutable.standardizedFileURL }
    }

    var launcherArchitectures: [WindowsExecutableArchitecture] {
        uniqueArchitectures(for: .launcher)
    }

    var gameArchitectures: [WindowsExecutableArchitecture] {
        executables
            .filter { [.game, .unknown].contains($0.role) }
            .map(\.architecture)
            .filter { $0 != .unknown }
            .deduplicated()
    }

    var requiredArchitectures: [WindowsExecutableArchitecture] {
        (gameArchitectures + launcherArchitectures).deduplicated()
    }

    var importantExecutables: [AnalyzedExecutable] {
        // An executable that cannot be confidently named as a game is still
        // relevant when it is part of the installation. Unreal's bootstrap
        // executable is often accompanied by a nested *-Win64-Shipping.exe;
        // that binary owns the actual VC++ imports while its role may remain
        // `.unknown` after discovery scoring.
        executables.filter { [.game, .launcher, .unknown].contains($0.role) }
    }

    private func uniqueArchitectures(for role: CompatibilityExecutableRole) -> [WindowsExecutableArchitecture] {
        executables
            .filter { $0.role == role }
            .map(\.architecture)
            .filter { $0 != .unknown }
            .deduplicated()
    }
}

nonisolated enum ExecutableCompatibilityAnalyzer {
    static func analyze(
        root: URL,
        applicationName: String,
        knownPrimary: URL? = nil
    ) -> ExecutableAnalysis {
        let snapshot = ExecutableDiscovery.snapshot(at: root)
        let ranked = ExecutableDiscovery.rankedCandidates(
            before: ExecutableFilesystemSnapshot(rootURL: root, entries: []),
            after: snapshot,
            applicationName: applicationName
        )
        let scoreByPath = Dictionary(uniqueKeysWithValues: ranked.map { ($0.url.standardizedFileURL.path.lowercased(), $0.score) })
        let descriptors = snapshot.entries.compactMap { entry -> AnalyzedExecutable? in
            let url = root.appending(path: entry.relativePath).standardizedFileURL
            guard url.pathExtension.caseInsensitiveCompare("exe") == .orderedSame else { return nil }
            let role = role(for: url.lastPathComponent)
            let score = scoreByPath[url.path.lowercased()] ?? -1_000
            return AnalyzedExecutable(
                id: url,
                url: url,
                architecture: WindowsExecutableArchitecture.inspect(url),
                role: role == .unknown && score >= ExecutableDiscovery.minimumLaunchCandidateScore ? .game : role,
                discoveryScore: score
            )
        }
        .sorted {
            if $0.role != $1.role { return rolePriority($0.role) < rolePriority($1.role) }
            if $0.discoveryScore != $1.discoveryScore { return $0.discoveryScore > $1.discoveryScore }
            return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }

        let primary = knownPrimary.flatMap { known in
            descriptors.first {
                $0.url.standardizedFileURL == known.standardizedFileURL && $0.role == .game
            }?.url
        }
        ?? descriptors.first(where: { $0.role == .game })?.url
        ?? knownPrimary.flatMap { known in
            descriptors.first {
                $0.url.standardizedFileURL == known.standardizedFileURL && $0.role == .launcher
            }?.url
        }
        ?? descriptors.first(where: { $0.role == .launcher })?.url

        let relatedRoot: URL
        if root.lastPathComponent.caseInsensitiveCompare("drive_c") == .orderedSame,
           let primary {
            relatedRoot = primary.deletingLastPathComponent()
        } else {
            relatedRoot = root
        }
        let relatedFiles = CompatibilityFileInventory.relatedFiles(in: relatedRoot, excluding: primary)
        return ExecutableAnalysis(executables: descriptors, primaryExecutable: primary, relatedFiles: relatedFiles)
    }

    private static func role(for filename: String) -> CompatibilityExecutableRole {
        let name = (filename as NSString).deletingPathExtension.lowercased()
        let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let joined = words.joined()
        func has(_ value: String) -> Bool { words.contains(value) || joined.contains(value) }

        if has("uninstall") || has("uninstaller") || has("unins") { return .uninstaller }
        if has("updater") || has("update") { return .updater }
        if has("launcher") || has("launch") { return .launcher }
        if has("installer") || has("install") || has("setup") { return .installer }
        if has("helper") || has("crashhandler") || has("crashreport") { return .helper }
        if has("config") || has("configuration") || has("settings") || has("options") { return .helper }
        return .unknown
    }

    private static func rolePriority(_ role: CompatibilityExecutableRole) -> Int {
        switch role {
        case .game: 0
        case .launcher: 1
        case .unknown: 2
        case .helper: 3
        case .installer: 4
        case .updater: 5
        case .uninstaller: 6
        }
    }
}

nonisolated enum AutomaticRuntimeDependencyDetection {
    static func requiredDependencies(in analysis: ExecutableAnalysis) -> Set<RuntimeDependency> {
        var dependencies: Set<RuntimeDependency> = []
        for executable in analysis.importantExecutables {
            let required = RuntimeDependencyResolver.resolve(executableURL: executable.url)
                .compactMap { entry in entry.value.0 == .required ? entry.key : nil }
            dependencies.formUnion(required)
        }
        // Related PE files can own the actual imports while the selected
        // launcher remains a thin redirector. Media assets deliberately do
        // not become automatic installs: they are recommendations until a
        // PE import or runtime log confirms that Windows media is required.
        for file in analysis.relatedFiles where ["exe", "dll", "sys"].contains(file.pathExtension.lowercased()) {
            let required = RuntimeDependencyResolver.resolve(executableURL: file)
                .compactMap { entry in entry.value.0 == .required ? entry.key : nil }
            dependencies.formUnion(required)
        }
        return dependencies
    }

    static func mediaCapabilities(in analysis: ExecutableAnalysis) -> Set<MediaCompatibilityCapability> {
        let mediaFoundationLibraries: Set<String> = ["mf.dll", "mfplat.dll", "mfreadwrite.dll", "mfplay.dll", "wmvcore.dll", "wmv9vcm.dll"]
        let directShowLibraries: Set<String> = ["quartz.dll", "qasf.dll", "qedit.dll", "amstream.dll"]
        let files = analysis.importantExecutables.map(\.url) + analysis.relatedFiles.filter {
            ["exe", "dll", "sys"].contains($0.pathExtension.lowercased())
        }
        var capabilities: Set<MediaCompatibilityCapability> = []
        for file in files {
            let imports = WindowsPEInspection.inspect(file).imports
            if !mediaFoundationLibraries.isDisjoint(with: imports) { capabilities.insert(.mediaFoundation) }
            if !directShowLibraries.isDisjoint(with: imports) { capabilities.insert(.directShow) }
        }
        return capabilities
    }
}

nonisolated struct RuntimeSelectionRequest: Sendable, Hashable {
    var architectures: [WindowsExecutableArchitecture]
    /// Nil means automatic prefix selection with WoW64 preferred.
    var prefixMode: WinePrefixMode?
    var requestedBackend: GraphicsBackend
    var directXAPI: GraphicsAPI
    var gameProfile: GameGraphicsProfile?
    var requiredEngine: RuntimeEngine?
    var runtimeIDOverride: String?

    init(
        architectures: [WindowsExecutableArchitecture],
        prefixMode: WinePrefixMode? = nil,
        requestedBackend: GraphicsBackend = .automatic,
        directXAPI: GraphicsAPI = .automatic,
        gameProfile: GameGraphicsProfile? = nil,
        requiredEngine: RuntimeEngine? = nil,
        runtimeIDOverride: String? = nil
    ) {
        self.architectures = architectures.deduplicated()
        self.prefixMode = prefixMode
        self.requestedBackend = requestedBackend
        self.directXAPI = directXAPI
        self.gameProfile = gameProfile
        self.requiredEngine = requiredEngine
        self.runtimeIDOverride = runtimeIDOverride
    }
}

nonisolated enum CompatibilityPreparationError: LocalizedError, Sendable {
    case noGameExecutable(URL)
    case noCompatibleRuntime(String)
    case incompatibleGraphics(String)

    var errorDescription: String? {
        switch self {
        case .noGameExecutable(let root): "Boreal could not identify a game executable under \(root.path)."
        case .noCompatibleRuntime(let detail): "No compatible runtime is available. \(detail)"
        case .incompatibleGraphics(let detail): "The graphics configuration is unavailable. \(detail)"
        }
    }
}

nonisolated struct GameCompatibilityFacts: Codable, Hashable, Sendable {
    let executableArchitecture: WindowsExecutableArchitecture
    let detectedDirectXAPI: GraphicsAPI
    let detectedDependencies: [RuntimeDependency]
}

nonisolated struct GameCompatibilityRules: Codable, Hashable, Sendable {
    let supportedAPIs: [GraphicsAPI]
    let defaultAPI: GraphicsAPI
    let enforcedAPI: GraphicsAPI?
    let preferredBackend: WineGraphicsBackend?
    let enforcedBackend: WineGraphicsBackend?

    init(profile: GameGraphicsProfile?) {
        supportedAPIs = profile?.availableAPIs ?? []
        defaultAPI = profile?.defaultAPI ?? .automatic
        enforcedAPI = profile?.enforcedAPI
        preferredBackend = profile?.preferredBackend
        enforcedBackend = profile?.enforcedBackend
    }
}

nonisolated struct LaunchOnlyCompatibilityOverrides: Codable, Hashable, Sendable {
    let arguments: [String]
    let overlayCompatibleFullscreen: Bool
    let displayID: UInt32?
    let loggingLevel: WineLoggingLevel
    let temporalUpscaling: TemporalUpscalingConfiguration
}

/// Immutable output of compatibility resolution. User intent is kept
/// separate from evidence, game-owned rules, the environment specification,
/// and settings consumed only when a process starts.
nonisolated struct ResolvedCompatibilityPlan: Codable, Hashable, Sendable {
    let executable: URL
    let executableArchitecture: WindowsExecutableArchitecture
    let launcherArchitectures: [WindowsExecutableArchitecture]
    let prefixMode: WinePrefixMode
    let windowsVersion: WineWindowsVersion
    let directXAPI: GraphicsAPI
    let graphicsStack: GraphicsStack
    let dependencies: [RuntimeDependency]
    let runtimeID: String
    let facts: GameCompatibilityFacts
    let rules: GameCompatibilityRules
    let environmentSpecification: EnvironmentConfiguration
    let launchOverrides: LaunchOnlyCompatibilityOverrides
}

typealias ResolvedCompatibilityConfiguration = ResolvedCompatibilityPlan

nonisolated enum CompatibilityPreparationResolver {
    static func directXAPI(
        executable: URL,
        userProfile: WineCompatibilityProfile,
        gameProfile: GameGraphicsProfile?
    ) -> GraphicsAPI {
        if let enforced = gameProfile?.enforcedAPI, enforced != .automatic { return enforced }
        if let user = userProfile.graphicsAPI,
           user != .automatic,
           gameProfile?.selectableLaunchOptions.contains(where: { $0.api == user }) == true {
            return user
        }
        if let preferred = gameProfile?.defaultAPI, preferred != .automatic { return preferred }
        return GraphicsAPIDetector.detect(executable: executable) ?? .automatic
    }

    static func graphicsResolution(
        api: GraphicsAPI,
        requestedBackend: WineGraphicsBackend,
        gameProfile: GameGraphicsProfile?,
        runtime: InstalledRuntime,
        architecture: WinePrefixArchitecture,
        fallback: WineGraphicsFallback = .none
    ) -> GraphicsStackResolution {
        GraphicsBackendResolver.resolve(
            api: api,
            requestedBackend: requestedBackend,
            gameProfile: gameProfile,
            runtime: runtime,
            architecture: architecture,
            fallback: fallback
        )
    }

    static func resolve(
        analysis: ExecutableAnalysis,
        userProfile: WineCompatibilityProfile,
        gameProfile: GameGraphicsProfile?,
        runtime: InstalledRuntime,
        environmentName: String? = nil
    ) throws -> ResolvedCompatibilityConfiguration {
        guard let primary = analysis.gameExecutable else {
            throw CompatibilityPreparationError.noGameExecutable(URL(fileURLWithPath: "."))
        }
        let prefixMode = WinePrefixMode.resolve(
            requestedMode: userProfile.prefixMode,
            requestedArchitecture: primary.architecture == .x86 ? WinePrefixArchitecture.win32.rawValue : WinePrefixArchitecture.win64.rawValue,
            runtimeSupportsWoW64: runtime.features?.supportsWoW64 == true
        )
        let prefixArchitecture = prefixMode == .legacyWin32 ? WinePrefixArchitecture.win32 : .win64
        let api = directXAPI(executable: primary.url, userProfile: userProfile, gameProfile: gameProfile)
        let resolution = graphicsResolution(
            api: api,
            requestedBackend: userProfile.graphicsBackend,
            gameProfile: gameProfile,
            runtime: runtime,
            architecture: prefixArchitecture,
            fallback: userProfile.graphicsFallback
        )
        guard resolution.isAvailable else {
            throw CompatibilityPreparationError.incompatibleGraphics(resolution.reasons.joined(separator: "; "))
        }

        let detectedDependencies = AutomaticRuntimeDependencyDetection.requiredDependencies(in: analysis)
        var dependencies = Set(userProfile.dependencyOverrides)
        dependencies.formUnion(detectedDependencies)

        var environmentSpecification = EnvironmentConfiguration(
            name: environmentName ?? primary.url.deletingLastPathComponent().lastPathComponent,
            profile: userProfile
        )
        environmentSpecification.windowsVersion = userProfile.windowsVersion.rawValue
        environmentSpecification.architecture = (primary.architecture == .x86 ? WinePrefixArchitecture.win32 : .win64).rawValue
        environmentSpecification.prefixMode = prefixMode
        environmentSpecification.graphicsBackend = resolution.stack.backend
        environmentSpecification.graphicsAPI = api
        environmentSpecification.requiredDependencies = dependencies
        environmentSpecification.requiredMediaCapabilities = AutomaticRuntimeDependencyDetection.mediaCapabilities(in: analysis)

        let detectedAPI = GraphicsAPIDetector.detect(executable: primary.url) ?? .automatic

        return ResolvedCompatibilityPlan(
            executable: primary.url,
            executableArchitecture: primary.architecture,
            launcherArchitectures: analysis.launcherArchitectures,
            prefixMode: prefixMode,
            windowsVersion: userProfile.windowsVersion,
            directXAPI: api,
            graphicsStack: resolution.stack,
            dependencies: dependencies.sorted { $0.rawValue < $1.rawValue },
            runtimeID: runtime.id,
            facts: GameCompatibilityFacts(
                executableArchitecture: primary.architecture,
                detectedDirectXAPI: detectedAPI,
                detectedDependencies: detectedDependencies.sorted { $0.rawValue < $1.rawValue }
            ),
            rules: GameCompatibilityRules(profile: gameProfile),
            environmentSpecification: environmentSpecification,
            launchOverrides: LaunchOnlyCompatibilityOverrides(
                arguments: userProfile.parsedLaunchArguments,
                overlayCompatibleFullscreen: userProfile.overlayCompatibleFullscreen,
                displayID: userProfile.overlayDisplayID,
                loggingLevel: userProfile.wineLoggingLevel,
                temporalUpscaling: userProfile.temporalUpscaling
            )
        )
    }

    static func runtimeSatisfies(_ runtime: InstalledRuntime, request: RuntimeSelectionRequest) -> Bool {
        let features = runtime.features
        let capabilities = features?.resolvedArchitectureCapabilities ?? .unknown
        let supports32 = features?.supportsWin32Execution ?? capabilities.canRunX86
        let supports64 = features?.supportsWin64Execution ?? capabilities.canRunX86_64
        if request.architectures.contains(.x86), !supports32 { return false }
        if request.architectures.contains(.x86_64), !supports64 { return false }
        if let mode = request.prefixMode {
            switch mode {
            case .wow64 where !capabilities.usesNewWoW64:
                return false
            case .legacyWin32 where !capabilities.supportsLegacyWin32Prefix:
                return false
            case .legacyWin64 where !supports64 || capabilities.usesNewWoW64:
                return false
            default:
                break
            }
        }
        if let requiredEngine = request.requiredEngine, runtime.resolvedEngine != requiredEngine { return false }
        if let runtimeIDOverride = request.runtimeIDOverride, runtime.id != runtimeIDOverride { return false }

        let prefixArchitecture: WinePrefixArchitecture
        switch request.prefixMode {
        case .legacyWin32:
            prefixArchitecture = .win32
        case .wow64, .legacyWin64:
            prefixArchitecture = .win64
        case nil:
            prefixArchitecture = request.architectures.contains(.x86_64) || capabilities.usesNewWoW64 ? .win64 : .win32
        }
        let resolution = graphicsResolution(
            api: request.directXAPI,
            requestedBackend: request.requestedBackend,
            gameProfile: request.gameProfile,
            runtime: runtime,
            architecture: prefixArchitecture
        )
        return resolution.isAvailable
    }

    static func score(_ runtime: InstalledRuntime, request: RuntimeSelectionRequest) -> Int {
        guard runtimeSatisfies(runtime, request: request) else { return Int.min }
        var score = 0
        if runtime.id == request.runtimeIDOverride { score += 10_000 }
        if request.prefixMode == nil, runtime.features?.resolvedArchitectureCapabilities.usesNewWoW64 == true { score += 500 }
        if runtime.origin == .localImport { score += 50 }
        let prefixArchitecture: WinePrefixArchitecture = request.prefixMode == .legacyWin32 ? .win32 : .win64
        score += graphicsResolution(
            api: request.directXAPI,
            requestedBackend: request.requestedBackend,
            gameProfile: request.gameProfile,
            runtime: runtime,
            architecture: prefixArchitecture
        ).score
        return score
    }
}

nonisolated extension RuntimeManaging {
    func prepareReadyRuntime(for request: RuntimeSelectionRequest) async throws -> InstalledRuntime {
        let installed = try await installedRuntimes()
        let ordered = installed
            .filter { CompatibilityPreparationResolver.runtimeSatisfies($0, request: request) }
            .sorted { CompatibilityPreparationResolver.score($0, request: request) > CompatibilityPreparationResolver.score($1, request: request) }
        for runtime in ordered {
            if try await validate(runtime).isReady { return runtime }
        }

        guard request.runtimeIDOverride == nil else {
            throw RuntimeManagerError.noCompatibleRuntime("The selected runtime does not satisfy the executable, prefix, or graphics constraints.")
        }

        let localCandidates = await localRuntimeCandidates()
        for candidate in localCandidates {
            guard candidate.features.resolvedArchitectureCapabilities.canRunX86 || !request.architectures.contains(.x86) else { continue }
            guard request.requiredEngine == nil || candidate.engine == request.requiredEngine else { continue }
            let imported: InstalledRuntime
            if candidate.engine == .gamePortingToolkit {
                imported = try await importSelectedGPTKRuntime(from: candidate.appURL)
            } else {
                imported = try await importLocalRuntime(candidate)
            }
            if CompatibilityPreparationResolver.runtimeSatisfies(imported, request: request), try await validate(imported).isReady {
                return imported
            }
        }

        for available in try await availableRuntimes() {
            guard request.requiredEngine == nil || available.engine == request.requiredEngine else { continue }
            let installed = try await install(available)
            if CompatibilityPreparationResolver.runtimeSatisfies(installed, request: request), try await validate(installed).isReady {
                return installed
            }
        }

        throw RuntimeManagerError.noCompatibleRuntime("No verified runtime supports all required executable architectures and graphics capabilities.")
    }
}

private extension Array where Element: Equatable {
    func deduplicated() -> [Element] {
        reduce(into: []) { result, element in
            if !result.contains(element) { result.append(element) }
        }
    }
}
