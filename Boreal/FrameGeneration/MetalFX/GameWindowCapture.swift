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
    private let stateLock = NSLock()
    private let frameHandler: FrameHandler
    private let errorHandler: ErrorHandler
    private var stream: SCStream?
    private var textureCache: CVMetalTextureCache?
    private var configuration: SCStreamConfiguration?
    private var nextFrameSequence: UInt64 = 0
    private var captureEpoch: UInt64 = 0

    init(device: MTLDevice, frameHandler: @escaping FrameHandler, errorHandler: @escaping ErrorHandler) {
        self.device = device
        self.frameHandler = frameHandler
        self.errorHandler = errorHandler
        super.init()
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        textureCache = cache
    }

    @discardableResult
    func start(window: SCWindow, width: Int, height: Int) async throws -> UInt64 {
        let configuration = makeConfiguration(width: width, height: height)
        let stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        let startedCaptureEpoch = withStateLock {
            nextFrameSequence = 0
            captureEpoch &+= 1
            self.configuration = configuration
            self.stream = stream
            return captureEpoch
        }
        do {
            try await stream.startCapture()
        } catch {
            withStateLock {
                if self.stream === stream {
                    self.stream = nil
                    self.configuration = nil
                }
            }
            throw error
        }
        return startedCaptureEpoch
    }

    func updateDimensions(width: Int, height: Int) async throws {
        let stream = withStateLock { self.stream }
        guard let stream else { return }
        let updated = makeConfiguration(width: width, height: height)
        try await stream.updateConfiguration(updated)
        withStateLock {
            if self.stream === stream {
                configuration = updated
            }
        }
    }

    func stop() async {
        let stream = withStateLock {
            let stream = self.stream
            self.stream = nil
            configuration = nil
            return stream
        }
        guard let stream else { return }
        try? await stream.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        stateLock.lock()
        let isCurrentStream = self.stream === stream
        let textureCache = self.textureCache
        let sequence = nextFrameSequence
        let epoch = captureEpoch
        stateLock.unlock()
        guard isCurrentStream, let textureCache else { return }

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

        stateLock.lock()
        let stillCurrent = self.stream === stream
            && captureEpoch == epoch
            && nextFrameSequence == sequence
        if stillCurrent {
            nextFrameSequence &+= 1
        }
        stateLock.unlock()
        guard stillCurrent else { return }

        frameHandler(
            CapturedGameFrame(
                texture: texture,
                pixelBuffer: pixelBuffer,
                metalTextureReference: metalTextureReference,
                metalTextureCache: textureCache,
                presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                sequence: sequence,
                captureEpoch: epoch
            )
        )
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateLock.lock()
        let isCurrentStream = self.stream === stream
        stateLock.unlock()
        guard isCurrentStream else { return }
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

    private func withStateLock<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
