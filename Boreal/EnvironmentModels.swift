import Foundation

nonisolated enum ManagedEnvironmentState: String, Codable, Sendable { case created, initializing, ready, invalid }

nonisolated struct EnvironmentConfiguration: Codable, Sendable, Hashable {
    var name: String
    var windowsVersion: String = "win11"
    var architecture: String = "win64"
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

nonisolated enum EnvironmentManagerError: LocalizedError, Sendable {
    case initializationFailed(exitCode: Int32, stderrLog: URL)
    case validationFailed(EnvironmentValidation)
    case runtimeMismatch

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let code, _): "Wine couldn’t initialize the environment (exit code \(code))."
        case .validationFailed: "The Windows environment is incomplete."
        case .runtimeMismatch: "The selected runtime does not match this environment."
        }
    }
}

nonisolated protocol EnvironmentManaging: Sendable {
    func create(configuration: EnvironmentConfiguration, runtime: InstalledRuntime) async throws -> ManagedBorealEnvironment
    func initialize(_ environment: ManagedBorealEnvironment, runtime: InstalledRuntime) async throws
    func validate(_ environment: ManagedBorealEnvironment) async throws -> EnvironmentValidation
    func remove(_ environment: ManagedBorealEnvironment) async throws
}
