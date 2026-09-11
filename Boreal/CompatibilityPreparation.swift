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
        executables.filter { [.game, .launcher].contains($0.role) }
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

        return ExecutableAnalysis(executables: descriptors, primaryExecutable: primary)
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

nonisolated struct ResolvedCompatibilityConfiguration: Codable, Hashable, Sendable {
    let executable: URL
    let executableArchitecture: WindowsExecutableArchitecture
    let launcherArchitectures: [WindowsExecutableArchitecture]
    let prefixMode: WinePrefixMode
    let windowsVersion: WineWindowsVersion
    let directXAPI: GraphicsAPI
    let graphicsStack: GraphicsStack
    let dependencies: [RuntimeDependency]
    let runtimeID: String
}

nonisolated enum CompatibilityPreparationResolver {
    static func directXAPI(
        executable: URL,
        userProfile: WineCompatibilityProfile,
        gameProfile: GameGraphicsProfile?
    ) -> GraphicsAPI {
        if let enforced = gameProfile?.enforcedAPI, enforced != .automatic { return enforced }
        if let user = userProfile.graphicsAPI, user != .automatic { return user }
        if let preferred = gameProfile?.defaultAPI, preferred != .automatic { return preferred }
        return GraphicsAPIDetector.detect(executable: executable) ?? .automatic
    }

    static func resolve(
        analysis: ExecutableAnalysis,
        userProfile: WineCompatibilityProfile,
        gameProfile: GameGraphicsProfile?,
        runtime: InstalledRuntime
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
        let resolution = GraphicsBackendResolver.resolve(
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

        var dependencies = Set(userProfile.requiredDependencies)
        for executable in analysis.importantExecutables {
            let required = RuntimeDependencyResolver.resolve(executableURL: executable.url)
                .compactMap { entry in entry.value.0 == .required ? entry.key : nil }
            dependencies.formUnion(required)
        }

        return ResolvedCompatibilityConfiguration(
            executable: primary.url,
            executableArchitecture: primary.architecture,
            launcherArchitectures: analysis.launcherArchitectures,
            prefixMode: prefixMode,
            windowsVersion: userProfile.windowsVersion,
            directXAPI: api,
            graphicsStack: resolution.stack,
            dependencies: dependencies.sorted { $0.rawValue < $1.rawValue },
            runtimeID: runtime.id
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
        let resolution = GraphicsBackendResolver.resolve(
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
        score += GraphicsBackendResolver.resolve(
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
            let imported = try await importLocalRuntime(candidate)
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
