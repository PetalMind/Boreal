import Foundation

nonisolated enum ManagedEnvironmentState: String, Codable, Sendable { case created, initializing, ready, invalid }

nonisolated enum WinePrefixMode: String, Codable, Sendable, Equatable {
    case wow64
    case legacyWin32
    case legacyWin64

    static func resolve(requestedArchitecture: String, runtimeSupportsWoW64: Bool) -> Self {
        if runtimeSupportsWoW64 { return .wow64 }
        return requestedArchitecture == WinePrefixArchitecture.win32.rawValue ? .legacyWin32 : .legacyWin64
    }

    var explicitWineArchitecture: String? {
        switch self {
        case .wow64: nil
        case .legacyWin32: WinePrefixArchitecture.win32.rawValue
        case .legacyWin64: WinePrefixArchitecture.win64.rawValue
        }
    }
}

nonisolated struct EnvironmentConfiguration: Codable, Sendable, Hashable {
    var name: String
    var windowsVersion: String = "win11"
    var architecture: String = "win64"
    var graphicsBackend: WineGraphicsBackend = .automatic
    var graphicsAPI: GraphicsAPI = .automatic
    var esyncEnabled: Bool = true
    var msyncEnabled: Bool = true
    var retinaModeEnabled: Bool = true
    var fullscreenFSREnabled: Bool = false
    var debugLoggingEnabled: Bool = false
    var forceXInput: Bool = true

    var graphicsConfiguration: GraphicsBackendConfiguration {
        GraphicsBackendConfiguration(backend: graphicsBackend, api: graphicsAPI, fullscreenFSREnabled: fullscreenFSREnabled)
    }

    init(name: String, windowsVersion: String = "win11", architecture: String = "win64", profile: WineCompatibilityProfile? = nil) {
        self.name = name
        self.windowsVersion = profile?.windowsVersion.rawValue ?? windowsVersion
        self.architecture = profile?.architecture.rawValue ?? architecture
        self.graphicsBackend = profile?.graphicsBackend ?? .automatic
        self.graphicsAPI = profile?.graphicsAPI ?? .automatic
        self.esyncEnabled = profile?.esyncEnabled ?? true
        self.msyncEnabled = profile?.msyncEnabled ?? true
        self.retinaModeEnabled = profile?.retinaModeEnabled ?? true
        self.fullscreenFSREnabled = profile?.fullscreenFSREnabled ?? false
        self.debugLoggingEnabled = profile?.debugLoggingEnabled ?? false
        self.forceXInput = profile?.forceXInput ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case name, windowsVersion, architecture, graphicsBackend, graphicsAPI, esyncEnabled, msyncEnabled
        case retinaModeEnabled, fullscreenFSREnabled, debugLoggingEnabled, forceXInput
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        windowsVersion = try values.decodeIfPresent(String.self, forKey: .windowsVersion) ?? "win11"
        architecture = try values.decodeIfPresent(String.self, forKey: .architecture) ?? "win64"
        graphicsBackend = try values.decodeIfPresent(WineGraphicsBackend.self, forKey: .graphicsBackend) ?? .automatic
        graphicsAPI = try values.decodeIfPresent(GraphicsAPI.self, forKey: .graphicsAPI) ?? .automatic
        esyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .esyncEnabled) ?? true
        msyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .msyncEnabled) ?? true
        retinaModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .retinaModeEnabled) ?? true
        fullscreenFSREnabled = try values.decodeIfPresent(Bool.self, forKey: .fullscreenFSREnabled) ?? false
        debugLoggingEnabled = try values.decodeIfPresent(Bool.self, forKey: .debugLoggingEnabled) ?? false
        forceXInput = try values.decodeIfPresent(Bool.self, forKey: .forceXInput) ?? true
    }
}

nonisolated struct ManagedBorealEnvironment: Codable, Identifiable, Sendable, Hashable {
    var schemaVersion: Int = BorealStorageSchema.current
    let id: UUID
    var configuration: EnvironmentConfiguration
    let runtimeID: String
    let rootURL: URL
    let prefixURL: URL
    let logsURL: URL
    var state: ManagedEnvironmentState

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, configuration, runtimeID, rootURL, prefixURL, logsURL, state
    }

    init(
        schemaVersion: Int = BorealStorageSchema.current,
        id: UUID,
        configuration: EnvironmentConfiguration,
        runtimeID: String,
        rootURL: URL,
        prefixURL: URL,
        logsURL: URL,
        state: ManagedEnvironmentState
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.configuration = configuration
        self.runtimeID = runtimeID
        self.rootURL = rootURL
        self.prefixURL = prefixURL
        self.logsURL = logsURL
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= BorealStorageSchema.current else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported environment schema version")
        }
        id = try values.decode(UUID.self, forKey: .id)
        configuration = try values.decode(EnvironmentConfiguration.self, forKey: .configuration)
        runtimeID = try values.decode(String.self, forKey: .runtimeID)
        rootURL = try values.decode(URL.self, forKey: .rootURL)
        prefixURL = try values.decode(URL.self, forKey: .prefixURL)
        logsURL = try values.decode(URL.self, forKey: .logsURL)
        state = try values.decode(ManagedEnvironmentState.self, forKey: .state)
    }
}

nonisolated struct EnvironmentValidation: Sendable, Equatable {
    var missingPaths: [String]
    var state: ManagedEnvironmentState
    var isReady: Bool { missingPaths.isEmpty && state == .ready }
}

nonisolated struct EnvironmentFailureDiagnostics: Sendable, Equatable {
    let directoryURL: URL
    let logURL: URL?
    let logExcerpt: String?

    func technicalDetails(for error: Error) -> String {
        var sections = [error.localizedDescription, "Diagnostics saved at: \(directoryURL.path)"]
        if let logURL { sections.append("Diagnostic log: \(logURL.path)") }
        if let logExcerpt, !logExcerpt.isEmpty {
            sections.append("Log excerpt:\n\(logExcerpt)")
        }
        return sections.joined(separator: "\n\n")
    }
}

nonisolated enum EnvironmentManagerError: LocalizedError, Sendable {
    case initializationFailed(exitCode: Int32, stderrLog: URL)
    case configurationFailed(exitCode: Int32, stderrLog: URL)
    case validationFailed(EnvironmentValidation)
    case runtimeMismatch
    case dependencyInstallerMissing(URL)
    case dependencyInstallerDownloadFailed
    case dependencyInstallationFailed(dependency: RuntimeDependency, exitCode: Int32, stderrLog: URL)

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let code, _): "Wine couldn’t initialize the environment (exit code \(code))."
        case .configurationFailed(let code, _): "Wine couldn’t apply the compatibility profile (exit code \(code))."
        case .validationFailed: "The Windows environment is incomplete."
        case .runtimeMismatch: "The selected runtime does not match this environment."
        case .dependencyInstallerMissing: "This runtime package does not contain Boreal's dependency installer."
        case .dependencyInstallerDownloadFailed: "Boreal could not download its dependency installer from the official source."
        case .dependencyInstallationFailed(let dependency, let code, _): "\(dependency.displayName) could not be installed (exit code \(code))."
        }
    }
}

nonisolated protocol EnvironmentManaging: Sendable {
    func create(configuration: EnvironmentConfiguration, runtime: InstalledRuntime) async throws -> ManagedBorealEnvironment
    func initialize(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func configure(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func validate(_ environment: ManagedBorealEnvironment) async throws -> EnvironmentValidation
    func dependencyStatuses(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> [RuntimeDependencyStatus]
    func install(_ dependency: RuntimeDependency, in environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func preserveFailureDiagnostics(_ environment: ManagedBorealEnvironment) async -> EnvironmentFailureDiagnostics?
    func remove(_ environment: ManagedBorealEnvironment) async throws
}

extension EnvironmentManaging {
    func configure(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws { }
    func preserveFailureDiagnostics(_ environment: ManagedBorealEnvironment) async -> EnvironmentFailureDiagnostics? { nil }
    func dependencyStatuses(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async -> [RuntimeDependencyStatus] { [] }
    func install(_ dependency: RuntimeDependency, in environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws { throw CocoaError(.featureUnsupported) }
}
