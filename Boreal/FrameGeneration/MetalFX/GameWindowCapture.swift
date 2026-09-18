import CoreMedia
import CoreVideo
import Foundation
import Metal
import ScreenCaptureKit

final class GameWindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    typealias FrameHandler = @Sendable (CapturedGameFrame) -> Void
    typealias ErrorHandler = @Sendable (Error) -> Void

    private let device: MTLDevice
    private let outputQueue = DispatchQueue(label: "com.boreal.frame-generation.capture", qos: .userInitiated)
    private let frameHandler: FrameHandler
    private let errorHandler: ErrorHandler
    private var stream: SCStream?
    private var textureCache: CVMetalTextureCache?
    private var configuration: SCStreamConfiguration?
    private var nextFrameSequence: UInt64 = 0

    init(device: MTLDevice, frameHandler: @escaping FrameHandler, errorHandler: @escaping ErrorHandler) {
        self.device = device
        self.frameHandler = frameHandler
        self.errorHandler = errorHandler
        super.init()
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        textureCache = cache
    }

    func start(window: SCWindow, width: Int, height: Int) async throws {
        nextFrameSequence = 0
        let configuration = makeConfiguration(width: width, height: height)
        let stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        self.configuration = configuration
        self.stream = stream
        try await stream.startCapture()
    }

    func updateDimensions(width: Int, height: Int) async throws {
        guard let stream else { return }
        let updated = makeConfiguration(width: width, height: height)
        try await stream.updateConfiguration(updated)
        configuration = updated
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        configuration = nil
        try? await stream.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var metalTextureReference: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &metalTextureReference
        )
        guard status == kCVReturnSuccess,
              let metalTextureReference,
              let texture = CVMetalTextureGetTexture(metalTextureReference) else { return }

        frameHandler(
            CapturedGameFrame(
                texture: texture,
                pixelBuffer: pixelBuffer,
                metalTextureReference: metalTextureReference,
                presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                sequence: nextFrameSequence
            )
        )
        nextFrameSequence &+= 1
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        errorHandler(error)
    }

    private func makeConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, width)
        configuration.height = max(1, height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 240)
        return configuration
    }
}
