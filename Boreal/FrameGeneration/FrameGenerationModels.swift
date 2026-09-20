import Foundation

/// Frame Generation is an in-process Windows rendering feature. The host
/// never captures the game window and never presents a second overlay surface.
nonisolated enum FrameGenerationState: Equatable, Sendable {
    case inactive
    case preparing
    case injected
    case waitingForUpscaler
    case frameGenerationAvailable
    case optiFGInitialized
    case active
    case degraded(String)
    case failed(String)
}

nonisolated enum FrameGenerationError: LocalizedError, Sendable {
    case optiScalerNotConfigured
    case optiScalerLogUnavailable

    var errorDescription: String? {
        switch self {
        case .optiScalerNotConfigured:
            "OptiFG is not enabled for this game."
        case .optiScalerLogUnavailable:
            "OptiScaler was injected, but its diagnostic log could not be read."
        }
    }
}

nonisolated enum FrameGenerationInstallationState: String, Codable, Sendable, Hashable {
    case managed
    case notManaged
    case modified
    case unknown

    var displayName: String {
        switch self {
        case .managed: "Managed"
        case .notManaged: "Not managed"
        case .modified: "Modified"
        case .unknown: "Unknown"
        }
    }
}

nonisolated enum FrameGenerationProcessState: String, Codable, Sendable, Hashable {
    case unknown
    case running
    case exited

    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .running: "Running"
        case .exited: "Exited"
        }
    }
}

nonisolated enum FrameGenerationLogEvidence: String, Codable, Sendable, Hashable {
    case unknown
    case waiting
    case available
    case initialized
    case active
    case failed

    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .waiting: "Waiting for upscaler"
        case .available: "Available"
        case .initialized: "OptiFG initialized"
        case .active: "Frame generation active"
        case .failed: "Failure reported"
        }
    }
}

nonisolated struct FrameGenerationRuntimeEvidence: Equatable, Sendable, Hashable {
    let installation: FrameGenerationInstallationState
    let process: FrameGenerationProcessState
    let log: FrameGenerationLogEvidence
    let detail: String?
}

/// The provider lifecycle is deliberately independent of AppKit, MetalFX,
/// host capture APIs, and input routing. It observes the in-process OptiScaler
/// result only; the real game window remains the sole presentation surface.
@MainActor protocol FrameGenerationProvider: AnyObject {
    var identifier: String { get }
    var runtimeErrorHandler: (@Sendable (Error) -> Void)? { get set }
    var stateHandler: (@Sendable (FrameGenerationState) -> Void)? { get set }
    var runtimeEvidenceHandler: (@Sendable (FrameGenerationRuntimeEvidence) -> Void)? { get set }

    func capabilities() -> FrameGenerationCapabilities
    func start(
        gamePID: pid_t?,
        gameRoot: URL,
        executable: URL,
        configuration: OptiScalerConfiguration
    ) async throws
    func updateGamePIDs(_ gamePIDs: [Int32])
    func stop() async
}

nonisolated struct FrameGenerationCapabilities: Equatable, Sendable {
    let isSupported: Bool
    let reason: String?
}
