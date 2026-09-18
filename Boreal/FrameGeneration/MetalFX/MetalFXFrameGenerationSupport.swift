import Metal
import MetalFX

enum MetalFXFrameGenerationSupport {
    static func capabilities() -> FrameGenerationCapabilities {
        guard #available(macOS 26.0, *) else {
            return FrameGenerationCapabilities(
                isSupported: false,
                reason: FrameGenerationError.unsupportedOS.localizedDescription
            )
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            return FrameGenerationCapabilities(
                isSupported: false,
                reason: FrameGenerationError.metalDeviceUnavailable.localizedDescription
            )
        }
        guard MTLFXFrameInterpolatorDescriptor.supportsDevice(device) else {
            return FrameGenerationCapabilities(
                isSupported: false,
                reason: FrameGenerationError.unsupportedHardware.localizedDescription
            )
        }
        return FrameGenerationCapabilities(isSupported: true, reason: nil)
    }
}
