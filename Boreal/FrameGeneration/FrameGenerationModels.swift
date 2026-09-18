import Foundation

nonisolated enum FrameGenerationBackend: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case off
    case metalFX

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: String(localized: "Off")
        case .metalFX: String(localized: "MetalFX Frame Generation")
        }
    }
}

nonisolated struct FrameGenerationRuntimeConfiguration: Codable, Equatable, Hashable, Sendable {
    var enabled = false
    var backend: FrameGenerationBackend = .metalFX
    var targetFPS: Int?
    var verticalSyncEnabled = true
    var lowLatencyModeEnabled = true
    var showStatistics = false

    static let `default` = FrameGenerationRuntimeConfiguration()
}

nonisolated struct FrameGenerationCapabilities: Equatable, Sendable {
    let isSupported: Bool
    let reason: String?
}

nonisolated enum FrameGenerationState: Equatable, Sendable {
    case inactive
    case preparing
    case running
    case unavailable(String)
    case failed(String)
}

nonisolated enum TemporalResetReason: String, CaseIterable, Sendable {
    case startup
    case resize
    case captureRestart
    case windowChanged
    case timestampDiscontinuity
    case frameContinuityLoss
    case sceneCut
    case gpuError
    case metalFXRecreation
    case motionEstimatorRecreation

    var displayName: String {
        switch self {
        case .startup: "startup"
        case .resize: "resize"
        case .captureRestart: "captureRestart"
        case .windowChanged: "windowChanged"
        case .timestampDiscontinuity: "timestampDiscontinuity"
        case .frameContinuityLoss: "frameContinuityLoss"
        case .sceneCut: "sceneCut"
        case .gpuError: "gpuError"
        case .metalFXRecreation: "metalFXRecreation"
        case .motionEstimatorRecreation: "motionEstimatorRecreation"
        }
    }
}

nonisolated struct FrameGenerationStatistics: Equatable, Sendable {
    var inputFPS: Double = 0
    var generatedFPS: Double = 0
    var outputFPS: Double = 0
    var droppedInputFrames: UInt64 = 0
    var skippedGeneratedFrames: UInt64 = 0
    var averageGenerationTimeMS: Double = 0
    var temporalResetCount: UInt64 = 0
    var staleEpochDrops: UInt64 = 0
    var motionEstimationDrops: UInt64 = 0
    var presentationDrops: UInt64 = 0
    var gpuErrorCount: UInt64 = 0
    var lastTemporalResetReason: TemporalResetReason?
    var captureToPresentationLatencyMS: Double = 0
}

nonisolated enum FrameGenerationError: LocalizedError, Sendable {
    case unsupportedHardware
    case unsupportedOS
    case screenCapturePermissionDenied
    case metalDeviceUnavailable
    case gameWindowNotFound
    case captureFailed(String)
    case motionEstimatorUnavailable
    case interpolatorCreationFailed
    case overlayCreationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedHardware:
            String(localized: "MetalFX frame interpolation is not supported by this Mac.")
        case .unsupportedOS:
            String(localized: "Frame generation requires a newer macOS version.")
        case .screenCapturePermissionDenied:
            String(localized: "Screen Recording permission is required for frame generation.")
        case .metalDeviceUnavailable:
            String(localized: "No Metal device is available for frame generation.")
        case .gameWindowNotFound:
            String(localized: "The game window could not be found.")
        case .captureFailed(let detail):
            String(localized: "Game capture failed: \(detail)")
        case .motionEstimatorUnavailable:
            String(localized: "VideoToolbox motion estimation is unavailable for this capture.")
        case .interpolatorCreationFailed:
            String(localized: "MetalFX frame interpolator could not be created.")
        case .overlayCreationFailed:
            String(localized: "The frame generation overlay could not be created.")
        }
    }
}

@MainActor protocol FrameGenerationProvider: AnyObject {
    var backend: FrameGenerationBackend { get }
    var runtimeErrorHandler: (@Sendable (Error) -> Void)? { get set }
    func capabilities() -> FrameGenerationCapabilities
    func start(gamePID: pid_t, configuration: FrameGenerationRuntimeConfiguration) async throws
    func stop() async
    func statistics() -> FrameGenerationStatistics
}
