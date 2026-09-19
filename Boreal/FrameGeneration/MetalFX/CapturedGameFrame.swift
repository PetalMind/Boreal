import CoreMedia
import CoreVideo
import Metal

nonisolated struct CapturedGameFrame: @unchecked Sendable {
    let texture: MTLTexture
    let pixelBuffer: CVPixelBuffer
    let metalTextureReference: CVMetalTexture
    // CVMetalTextureCache must outlive every CVMetalTexture created from it.
    // Retain it with the captured frame so async Metal/VideoToolbox work
    // cannot release the cache while an older frame is still in flight.
    let metalTextureCache: CVMetalTextureCache
    let presentationTime: CMTime
    let sequence: UInt64
    let captureEpoch: UInt64

    var width: Int { CVPixelBufferGetWidth(pixelBuffer) }
    var height: Int { CVPixelBufferGetHeight(pixelBuffer) }
}
