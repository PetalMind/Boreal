import CoreVideo
import Foundation
import VideoToolbox

nonisolated final class MotionEstimator: @unchecked Sendable {
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
            throw FrameGenerationError.motionEstimatorUnavailable
        }
    }
}
