@preconcurrency import Metal
@preconcurrency import MetalFX

nonisolated final class MetalFXInterpolator: @unchecked Sendable {
    let width: Int
    let height: Int
    let outputTextureUsage: MTLTextureUsage
    private let interpolator: MTLFXFrameInterpolator

    init(device: MTLDevice, width: Int, height: Int) throws {
        guard #available(macOS 26.0, *), MTLFXFrameInterpolatorDescriptor.supportsDevice(device) else {
            throw FrameGenerationError.unsupportedHardware
        }
        self.width = width
        self.height = height

        let descriptor = MTLFXFrameInterpolatorDescriptor()
        descriptor.colorTextureFormat = .bgra8Unorm
        descriptor.outputTextureFormat = .bgra8Unorm
        descriptor.depthTextureFormat = .r32Float
        descriptor.motionTextureFormat = .rg32Float
        descriptor.inputWidth = max(1, width)
        descriptor.inputHeight = max(1, height)
        descriptor.outputWidth = max(1, width)
        descriptor.outputHeight = max(1, height)

        guard let interpolator = descriptor.makeFrameInterpolator(device: device) else {
            throw FrameGenerationError.interpolatorCreationFailed
        }
        self.interpolator = interpolator
        outputTextureUsage = interpolator.outputTextureUsage

        interpolator.motionVectorScaleX = 1
        interpolator.motionVectorScaleY = 1
        interpolator.nearPlane = 0.1
        interpolator.farPlane = 1_000
        interpolator.fieldOfView = 90
        interpolator.aspectRatio = Float(width) / Float(max(1, height))
        interpolator.isDepthReversed = false
        interpolator.shouldResetHistory = false
    }

    func encode(
        previous: MTLTexture,
        current: MTLTexture,
        motion: MTLTexture,
        depth: MTLTexture,
        output: MTLTexture,
        deltaTime: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        interpolator.prevColorTexture = previous
        interpolator.colorTexture = current
        interpolator.motionTexture = motion
        interpolator.depthTexture = depth
        interpolator.outputTexture = output
        interpolator.deltaTime = max(1.0 / 240.0, min(deltaTime, 1.0 / 15.0))
        interpolator.encode(commandBuffer: commandBuffer)
    }
}
