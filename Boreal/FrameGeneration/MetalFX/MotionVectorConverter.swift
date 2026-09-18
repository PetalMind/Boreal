import CoreVideo
import Foundation
@preconcurrency import Metal

nonisolated final class MotionVectorConverter: @unchecked Sendable {
    private let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let width: Int
    private let height: Int

    init(device: MTLDevice, width: Int, height: Int) throws {
        self.device = device
        self.width = max(1, width)
        self.height = max(1, height)
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
        let threads = MTLSize(width: 8, height: 8, depth: 1)
        let grid = MTLSize(width: destination.width, height: destination.height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threads)
        encoder.endEncoding()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void borealResizeMotionVectors(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        uint2 position [[thread_position_in_grid]]) {
        if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
            return;
        }
        float2 destinationSize = float2(destination.get_width(), destination.get_height());
        float2 sourceSize = float2(source.get_width(), source.get_height());
        float2 uv = (float2(position) + 0.5) / destinationSize;
        uint2 sourcePosition = min(uint2(uv * sourceSize), uint2(source.get_width() - 1, source.get_height() - 1));
        float4 vector = source.read(sourcePosition);
        vector.xy *= destinationSize / sourceSize;
        destination.write(float4(vector.xy, 0.0, 0.0), position);
    }
    """
}
