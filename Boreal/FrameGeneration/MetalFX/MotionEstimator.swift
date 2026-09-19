import CoreVideo
import Foundation
import os
import VideoToolbox

nonisolated final class MotionEstimator: @unchecked Sendable {
    static let isAvailable: Bool = {
        guard #available(macOS 26.0, *) else { return false }
        do {
            _ = try VTMotionEstimationSession(
                width: 256,
                height: 160,
                motionVectorSize: .blockSize16x16,
                useMultiPassSearch: false,
                label: "Boreal Frame Generation capability probe"
            )
            return true
        } catch {
            let nsError = error as NSError
            Logger(subsystem: "STDMSolution.Boreal", category: "FrameGeneration").error(
                "VTMotionEstimationSession capability probe failed; OSStatus=\(nsError.code, privacy: .public); error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }()

    private let logger = Logger(subsystem: "STDMSolution.Boreal", category: "FrameGeneration")
    private let session: VTMotionEstimationSession
    private let width: Int
    private let height: Int

    init(width: Int, height: Int) throws {
        self.width = width
        self.height = height
        do {
            session = try VTMotionEstimationSession(
                width: UInt32(width),
                height: UInt32(height),
                motionVectorSize: .blockSize16x16,
                useMultiPassSearch: false,
                label: "Boreal Frame Generation"
            )
        } catch {
            let nsError = error as NSError
            logger.error(
                "VTMotionEstimationSession creation failed; OSStatus=\(nsError.code, privacy: .public); error=\(error.localizedDescription, privacy: .public)"
            )
            throw FrameGenerationError.motionEstimatorUnavailable
        }
    }

    func estimate(previous: CVPixelBuffer, current: CVPixelBuffer) async throws -> CVReadOnlyPixelBuffer {
        guard CVPixelBufferGetWidth(previous) == width,
              CVPixelBufferGetHeight(previous) == height,
              CVPixelBufferGetWidth(current) == width,
              CVPixelBufferGetHeight(current) == height,
              CVPixelBufferGetPixelFormatType(previous) == CVPixelBufferGetPixelFormatType(current) else {
            throw FrameGenerationError.motionEstimatorUnavailable
        }

        do {
            let motion = try await session.motion(
                of: CVReadOnlyPixelBuffer(unsafeBuffer: current),
                comparedTo: CVReadOnlyPixelBuffer(unsafeBuffer: previous),
                flags: []
            )
            return motion.motionVector
        } catch {
            let nsError = error as NSError
            logger.error(
                "VTMotionEstimationSession motion request failed; OSStatus=\(nsError.code, privacy: .public); error=\(error.localizedDescription, privacy: .public)"
            )
            throw FrameGenerationError.motionEstimatorUnavailable
        }
    }
}
