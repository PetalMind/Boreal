import CoreMedia
import CoreVideo
import Metal

nonisolated struct CapturedGameFrame: @unchecked Sendable {
    let texture: MTLTexture
    let pixelBuffer: CVPixelBuffer
    let metalTextureReference: CVMetalTexture
    let presentationTime: CMTime
    let sequence: UInt64

    var width: Int { CVPixelBufferGetWidth(pixelBuffer) }
    var height: Int { CVPixelBufferGetHeight(pixelBuffer) }
}
