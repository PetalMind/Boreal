import Metal

nonisolated final class FlatDepthTextureProvider: @unchecked Sendable {
    let texture: MTLTexture
    let width: Int
    let height: Int

    init(device: MTLDevice, width: Int, height: Int) throws {
        self.width = width
        self.height = height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw FrameGenerationError.interpolatorCreationFailed
        }
        self.texture = texture

        let values = [Float](repeating: 1, count: max(1, width * height))
        values.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, max(1, width), max(1, height)),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: max(1, width) * MemoryLayout<Float>.stride
            )
        }
    }
}
