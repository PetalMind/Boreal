import Foundation

nonisolated enum RuntimeArchitecture: String, Codable, Sendable { case x86_64, arm64 }
nonisolated enum RuntimeChannel: String, Codable, Sendable { case stable, devel, staging }
nonisolated enum RuntimeRequirement: String, Codable, Sendable, Hashable { case rosetta2, gStreamerFramework }

nonisolated struct RuntimeFeatures: Codable, Sendable, Hashable {
    var wow64: Bool
    var wineMono: Bool
    var wineGecko: Bool
    var d3dmetal: Bool
    var dxmt: Bool
}

nonisolated struct RuntimeArtifact: Codable, Sendable, Hashable {
    let url: URL
    let sha256: String
    let compressedSize: Int64
}

nonisolated struct BorealRuntime: Codable, Identifiable, Sendable, Hashable {
    let schemaVersion: Int
    let id: String
    let displayName: String
    let wineVersion: String
    let architecture: RuntimeArchitecture
    let minimumMacOS: String
    let channel: RuntimeChannel
    let requirements: Set<RuntimeRequirement>
    let features: RuntimeFeatures
    let artifact: RuntimeArtifact
}

nonisolated struct InstalledRuntime: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let displayName: String
    let wineVersion: String
    let rootURL: URL
    let wineExecutable: URL
    let wineServerExecutable: URL
    let wineBootExecutable: URL
    let architecture: RuntimeArchitecture
    let requirements: Set<RuntimeRequirement>
}

nonisolated struct RuntimeValidation: Sendable, Equatable {
    var detectedWineVersion: String?
    var versionMatchesManifest: Bool
    var missingPaths: [String]
    var unmetRequirements: Set<RuntimeRequirement>
    var executablePaths: [String]
    var isReady: Bool { missingPaths.isEmpty && unmetRequirements.isEmpty && detectedWineVersion != nil && versionMatchesManifest }
}

nonisolated enum RuntimeManagerError: LocalizedError, Sendable {
    case invalidManifest
    case manifestSignatureInvalid
    case alreadyInstalled(String)
    case checksumMismatch(expected: String, actual: String)
    case unsupportedArchive
    case runtimeLayoutNotFound
    case validationFailed(RuntimeValidation)
    case requirementMissing(RuntimeRequirement)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "The runtime manifest is invalid."
        case .manifestSignatureInvalid: "The runtime manifest signature is invalid."
        case .alreadyInstalled(let id): "Runtime \(id) is already installed."
        case .checksumMismatch: "Runtime verification failed because its SHA-256 checksum does not match."
        case .unsupportedArchive: "The runtime archive format is not supported."
        case .runtimeLayoutNotFound: "Boreal couldn’t locate Wine inside the runtime package."
        case .validationFailed: "The installed runtime did not pass validation."
        case .requirementMissing(.rosetta2): "Rosetta 2 is required by this runtime."
        case .requirementMissing(.gStreamerFramework): "GStreamer.framework is required by this development runtime."
        case .downloadFailed(let reason): "Runtime download failed: \(reason)"
        }
    }
}

nonisolated protocol RuntimeManaging: Sendable {
    func availableRuntimes() async throws -> [BorealRuntime]
    func installedRuntimes() async throws -> [InstalledRuntime]
    func install(_ runtime: BorealRuntime) async throws -> InstalledRuntime
    func validate(_ runtime: InstalledRuntime) async throws -> RuntimeValidation
    func remove(_ runtime: InstalledRuntime) async throws
}
