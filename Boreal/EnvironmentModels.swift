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
    var esyncEnabled: Bool = true
    var msyncEnabled: Bool = true
    var retinaModeEnabled: Bool = true
    var fullscreenFSREnabled: Bool = false
    var debugLoggingEnabled: Bool = false

    init(name: String, windowsVersion: String = "win11", architecture: String = "win64", profile: WineCompatibilityProfile? = nil) {
        self.name = name
        self.windowsVersion = profile?.windowsVersion.rawValue ?? windowsVersion
        self.architecture = profile?.architecture.rawValue ?? architecture
        self.graphicsBackend = profile?.graphicsBackend ?? .automatic
        self.esyncEnabled = profile?.esyncEnabled ?? true
        self.msyncEnabled = profile?.msyncEnabled ?? true
        self.retinaModeEnabled = profile?.retinaModeEnabled ?? true
        self.fullscreenFSREnabled = profile?.fullscreenFSREnabled ?? false
        self.debugLoggingEnabled = profile?.debugLoggingEnabled ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case name, windowsVersion, architecture, graphicsBackend, esyncEnabled, msyncEnabled
        case retinaModeEnabled, fullscreenFSREnabled, debugLoggingEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        windowsVersion = try values.decodeIfPresent(String.self, forKey: .windowsVersion) ?? "win11"
        architecture = try values.decodeIfPresent(String.self, forKey: .architecture) ?? "win64"
        graphicsBackend = try values.decodeIfPresent(WineGraphicsBackend.self, forKey: .graphicsBackend) ?? .automatic
        esyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .esyncEnabled) ?? true
        msyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .msyncEnabled) ?? true
        retinaModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .retinaModeEnabled) ?? true
        fullscreenFSREnabled = try values.decodeIfPresent(Bool.self, forKey: .fullscreenFSREnabled) ?? false
        debugLoggingEnabled = try values.decodeIfPresent(Bool.self, forKey: .debugLoggingEnabled) ?? false
    }
}

nonisolated struct ManagedBorealEnvironment: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var configuration: EnvironmentConfiguration
    let runtimeID: String
    let rootURL: URL
    let prefixURL: URL
    let logsURL: URL
    var state: ManagedEnvironmentState
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

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let code, _): "Wine couldn’t initialize the environment (exit code \(code))."
        case .configurationFailed(let code, _): "Wine couldn’t apply the compatibility profile (exit code \(code))."
        case .validationFailed: "The Windows environment is incomplete."
        case .runtimeMismatch: "The selected runtime does not match this environment."
        }
    }
}

nonisolated protocol EnvironmentManaging: Sendable {
    func create(configuration: EnvironmentConfiguration, runtime: InstalledRuntime) async throws -> ManagedBorealEnvironment
    func initialize(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func configure(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func validate(_ environment: ManagedBorealEnvironment) async throws -> EnvironmentValidation
    func preserveFailureDiagnostics(_ environment: ManagedBorealEnvironment) async -> EnvironmentFailureDiagnostics?
    func remove(_ environment: ManagedBorealEnvironment) async throws
}

extension EnvironmentManaging {
    func configure(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws { }
    func preserveFailureDiagnostics(_ environment: ManagedBorealEnvironment) async -> EnvironmentFailureDiagnostics? { nil }
}
