import CoreVideo
import Foundation
@preconcurrency import Metal

struct MotionVectorConversion: Sendable {
    let invertX: Bool
    let invertY: Bool
    let magnitudeScaleX: Float
    let magnitudeScaleY: Float

    // VideoToolbox convention (verified on the Apple M4/macOS 27.2 app
    // runtime): session.motion(of: current, comparedTo: previous) returns
    // current-to-previous vectors in pixel units. A +16 px synthetic
    // translation produced -16, and the 16x16-block output was 16x10 for a
    // 256x160 frame. MetalFX with scale 1 expects the same convention, so
    // the conversion is intentionally identity. Keep the developer probe
    // available to detect a future device/API variation.
    // Spatial sampling (a motion buffer with one vector per 16x16 block) is
    // separate from the vector's magnitude units.
    static let videoToolboxToMetalFX = MotionVectorConversion(
        invertX: false,
        invertY: false,
        magnitudeScaleX: 1,
        magnitudeScaleY: 1
    )

    var isIdentity: Bool {
        !invertX && !invertY && magnitudeScaleX == 1 && magnitudeScaleY == 1
    }
}

private struct MotionVectorConversionGPU {
    var magnitudeScale: SIMD2<Float>
    var invert: SIMD2<UInt32>
}

nonisolated final class MotionVectorConverter: @unchecked Sendable {
    private let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let width: Int
    private let height: Int
    private let conversion: MotionVectorConversion

    var requiresTransform: Bool { !conversion.isIdentity }

    init(
        device: MTLDevice,
        width: Int,
        height: Int,
        conversion: MotionVectorConversion = .videoToolboxToMetalFX
    ) throws {
        self.device = device
        self.width = max(1, width)
        self.height = max(1, height)
        self.conversion = conversion
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let function = library.makeFunction(name: "borealResizeMotionVectors") else {
                throw FrameGenerationError.interpolatorCreationFailed
            }
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            throw FrameGenerationError.interpolatorCreationFailed
        }
    }

    func makeDestinationTexture() -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: descriptor)
    }

    func encode(source: MTLTexture, destination: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        var gpuConversion = MotionVectorConversionGPU(
            magnitudeScale: SIMD2(conversion.magnitudeScaleX, conversion.magnitudeScaleY),
            invert: SIMD2(conversion.invertX ? 1 : 0, conversion.invertY ? 1 : 0)
        )
        encoder.setBytes(&gpuConversion, length: MemoryLayout<MotionVectorConversionGPU>.stride, index: 0)
        let threads = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(width: destination.width, height: destination.height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threads)
        encoder.endEncoding()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct MotionVectorConversionGPU {
        float2 magnitudeScale;
        uint2 invert;
    };

    kernel void borealResizeMotionVectors(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        constant MotionVectorConversionGPU &conversion [[buffer(0)]],
        uint2 position [[thread_position_in_grid]]) {
        if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
            return;
        }
        float2 destinationSize = float2(destination.get_width(), destination.get_height());
        float2 sourceSize = float2(source.get_width(), source.get_height());
        float2 uv = (float2(position) + 0.5) / destinationSize;
        uint2 sourcePosition = min(uint2(uv * sourceSize), uint2(source.get_width() - 1, source.get_height() - 1));
        float4 vector = source.read(sourcePosition);
        vector.xy *= conversion.magnitudeScale;
        if (conversion.invert.x != 0) vector.x = -vector.x;
        if (conversion.invert.y != 0) vector.y = -vector.y;
        destination.write(float4(vector.xy, 0.0, 0.0), position);
    }
    """
}
