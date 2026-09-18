import CoreVideo
import Foundation
import os
import VideoToolbox

nonisolated enum MotionVectorDiagnostic {
    static let environmentKey = "BOREAL_METALFX_MOTION_DIAGNOSTIC"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static func runIfEnabled(logger: Logger) async {
        guard isEnabled else { return }
        guard #available(macOS 26.0, *) else {
            logger.error("[FrameGeneration][MotionTest] VideoToolbox motion estimation requires macOS 26 or newer")
            return
        }

        do {
            let session = try VTMotionEstimationSession(
                width: 256,
                height: 160,
                motionVectorSize: .blockSize16x16,
                useMultiPassSearch: false,
                label: "Boreal Frame Generation motion diagnostic"
            )
            logger.info("[FrameGeneration][MotionTest] starting deterministic textured-pattern probe")
            for translation in [(16, 0), (0, 16), (16, 16)] {
                let previous = try makeBuffer(shiftX: 0, shiftY: 0)
                let current = try makeBuffer(shiftX: translation.0, shiftY: translation.1)
                let motion = try await session.motion(
                    of: CVReadOnlyPixelBuffer(unsafeBuffer: current),
                    comparedTo: CVReadOnlyPixelBuffer(unsafeBuffer: previous),
                    flags: []
                )
                let result = try median(
                    motion.motionVector,
                    translationX: translation.0,
                    translationY: translation.1
                )
                logResult(result, translationX: translation.0, translationY: translation.1, logger: logger)
            }
        } catch {
            logger.error("[FrameGeneration][MotionTest] FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct MedianResult {
        let x: Float
        let y: Float
        let width: Int
        let height: Int
        let pixelFormat: OSType
        let sampleCount: Int
    }

    private static func logResult(
        _ result: MedianResult,
        translationX: Int,
        translationY: Int,
        logger: Logger
    ) {
        let expectedX = Float(-translationX)
        let expectedY = Float(-translationY)
        let scaleX = abs(result.x) > 0.001 ? abs(expectedX / result.x) : 0
        let scaleY = abs(result.y) > 0.001 ? abs(expectedY / result.y) : 0
        let invertX = abs(expectedX) > 0.001 && (result.x.sign != expectedX.sign)
        let invertY = abs(expectedY) > 0.001 && (result.y.sign != expectedY.sign)
        let xPass = abs(translationX) < 1 || abs(result.x * (invertX ? -scaleX : scaleX) - expectedX) <= 2
        let yPass = abs(translationY) < 1 || abs(result.y * (invertY ? -scaleY : scaleY) - expectedY) <= 2
        let resultName = xPass && yPass ? "PASS" : "FAIL"
        logger.info("[FrameGeneration][MotionTest] Known translation X=\(translationX, privacy: .public) Y=\(translationY, privacy: .public)")
        logger.info("[FrameGeneration][MotionTest] VideoToolbox median X=\(result.x, privacy: .public) Y=\(result.y, privacy: .public) output=\(result.width, privacy: .public)x\(result.height, privacy: .public) format=0x\(String(result.pixelFormat, radix: 16), privacy: .public) samples=\(result.sampleCount, privacy: .public)")
        logger.info("[FrameGeneration][MotionTest] MetalFX expected X=\(expectedX, privacy: .public) Y=\(expectedY, privacy: .public)")
        logger.info("[FrameGeneration][MotionTest] Conversion invertX=\(invertX, privacy: .public) invertY=\(invertY, privacy: .public) scaleX=\(scaleX, privacy: .public) scaleY=\(scaleY, privacy: .public)")
        logger.info("[FrameGeneration][MotionTest] RESULT=\(resultName, privacy: .public)")
    }

    private static func makeBuffer(shiftX: Int, shiftY: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            256,
            160,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw MotionVectorDiagnosticError.bufferCreation(status)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw MotionVectorDiagnosticError.missingBaseAddress
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<160 {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<256 {
                let inPatch = x >= 64 + shiftX && x < 128 + shiftX
                    && y >= 48 + shiftY && y < 112 + shiftY
                let sourceX = inPatch ? x - shiftX : x
                let sourceY = inPatch ? y - shiftY : y
                let value = patternHash(x: sourceX, y: sourceY, inPatch: inPatch)
                let offset = x * 4
                row[offset] = UInt8(truncatingIfNeeded: value)
                row[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
                row[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
                row[offset + 3] = 255
            }
        }
        return buffer
    }

    private static func patternHash(x: Int, y: Int, inPatch: Bool) -> UInt32 {
        var value = UInt32(truncatingIfNeeded: x &* 1_664_525 &+ y &* 1_013_904_223)
        value ^= value >> 13
        value &*= 1_274_126_177
        value ^= value >> 16
        return inPatch ? value : value ^ 0x3A5C_91E7
    }

    private static func median(
        _ readOnlyBuffer: CVReadOnlyPixelBuffer,
        translationX: Int,
        translationY: Int
    ) throws -> MedianResult {
        try readOnlyBuffer.withUnsafeBuffer { buffer in
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
            guard pixelFormat == kCVPixelFormatType_TwoComponent32Float
                    || pixelFormat == kCVPixelFormatType_TwoComponent16Half else {
                throw MotionVectorDiagnosticError.unsupportedPixelFormat(pixelFormat)
            }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
                throw MotionVectorDiagnosticError.missingBaseAddress
            }

            let bytesPerComponent = pixelFormat == kCVPixelFormatType_TwoComponent32Float ? 4 : 2
            let bytesPerPixel = bytesPerComponent * 2
            let minX = max(0, Int(Double(64 + translationX) / 256 * Double(width)))
            let maxX = min(width, Int(ceil(Double(128 + translationX) / 256 * Double(width))))
            let minY = max(0, Int(Double(48 + translationY) / 160 * Double(height)))
            let maxY = min(height, Int(ceil(Double(112 + translationY) / 160 * Double(height))))
            var xValues: [Float] = []
            var yValues: [Float] = []
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for y in minY..<maxY {
                for x in minX..<maxX {
                    let address = baseAddress.advanced(by: y * bytesPerRow + x * bytesPerPixel)
                    let values: (Float, Float)
                    if pixelFormat == kCVPixelFormatType_TwoComponent32Float {
                        let vector = address.assumingMemoryBound(to: Float.self)
                        values = (vector[0], vector[1])
                    } else {
                        let vector = address.assumingMemoryBound(to: UInt16.self)
                        values = (Float(Float16(bitPattern: vector[0])), Float(Float16(bitPattern: vector[1])))
                    }
                    if values.0.isFinite && values.1.isFinite {
                        xValues.append(values.0)
                        yValues.append(values.1)
                    }
                }
            }
            guard !xValues.isEmpty else { throw MotionVectorDiagnosticError.emptySample }
            xValues.sort()
            yValues.sort()
            return MedianResult(
                x: xValues[xValues.count / 2],
                y: yValues[yValues.count / 2],
                width: width,
                height: height,
                pixelFormat: pixelFormat,
                sampleCount: xValues.count
            )
        }
    }
}

private enum MotionVectorDiagnosticError: LocalizedError {
    case bufferCreation(CVReturn)
    case missingBaseAddress
    case unsupportedPixelFormat(OSType)
    case emptySample

    var errorDescription: String? {
        switch self {
        case .bufferCreation(let status): "CVPixelBuffer creation failed: \(status)"
        case .missingBaseAddress: "CVPixelBuffer has no base address"
        case .unsupportedPixelFormat(let format): "Unsupported motion-vector pixel format: 0x\(String(format, radix: 16))"
        case .emptySample: "Motion-vector diagnostic produced no representative samples"
        }
    }
}
