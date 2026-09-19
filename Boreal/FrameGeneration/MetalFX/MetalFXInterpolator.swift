@preconcurrency import Metal
@preconcurrency import MetalFX

struct ExternalCaptureMetalFXParameters: Sendable {
    let nearPlane: Float
    let farPlane: Float
    let fieldOfView: Float
    let depthReversed: Bool

    // ScreenCaptureKit exposes the final composited image, not the game's
    // projection/depth buffers. The pipeline therefore uses one fixed,
    // documented fallback projection together with a flat normal-depth
    // texture; these values must not be presented as camera telemetry.
    static let fallback = ExternalCaptureMetalFXParameters(
        nearPlane: 0.1,
        farPlane: 1_000,
        fieldOfView: 90,
        depthReversed: false
    )
}

nonisolated final class MetalFXInterpolator: @unchecked Sendable {
    let width: Int
    let height: Int
    let outputTextureUsage: MTLTextureUsage
    private let interpolator: MTLFXFrameInterpolator

    init(
        device: MTLDevice,
        width: Int,
        height: Int,
        parameters: ExternalCaptureMetalFXParameters = .fallback
    ) throws {
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
        interpolator.nearPlane = parameters.nearPlane
        interpolator.farPlane = parameters.farPlane
        interpolator.fieldOfView = parameters.fieldOfView
        interpolator.aspectRatio = Float(width) / Float(max(1, height))
        interpolator.isDepthReversed = parameters.depthReversed
        interpolator.jitterOffsetX = 0
        interpolator.jitterOffsetY = 0
        // Boreal receives the final composited game image and does not supply
        // a separate uiTexture. Keep this explicit instead of relying on the
        // MetalFX default; there is no UI texture to decompose or recompose.
        interpolator.isUITextureComposited = false
        interpolator.shouldResetHistory = true
    }

    func encode(
        previous: MTLTexture,
        current: MTLTexture,
        motion: MTLTexture,
        depth: MTLTexture,
        output: MTLTexture,
        deltaTime: Float,
        resetHistory: Bool,
        commandBuffer: MTLCommandBuffer
    ) {
        interpolator.prevColorTexture = previous
        interpolator.colorTexture = current
        interpolator.motionTexture = motion
        interpolator.depthTexture = depth
        interpolator.outputTexture = output
        // The pipeline rejects timestamp discontinuities before this method.
        // Only protect against a zero/negative floating-point value here; do
        // not turn a real long interval into a falsely continuous frame pair.
        interpolator.deltaTime = max(Float.leastNonzeroMagnitude, deltaTime)
        interpolator.shouldResetHistory = resetHistory
        interpolator.encode(commandBuffer: commandBuffer)
    }
}
