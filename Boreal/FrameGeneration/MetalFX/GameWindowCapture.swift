import CoreMedia
import CoreVideo
import Darwin
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

    private static let machTimebase: mach_timebase_info_data_t = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return timebase
    }()

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
                presentationTime: presentationTime(for: sampleBuffer),
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

    private func presentationTime(for sampleBuffer: CMSampleBuffer) -> CMTime {
        if let displayTime = displayTime(from: sampleBuffer), displayTime > 0 {
            return CMTime(
                seconds: Self.machAbsoluteTimeToSeconds(displayTime),
                preferredTimescale: 1_000_000_000
            )
        }

        let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if sampleTime.isValid,
           sampleTime.isNumeric,
           sampleTime.seconds.isFinite,
           sampleTime.seconds > 0 {
            return sampleTime
        }

        // ScreenCaptureKit can deliver a valid image with an unusable CMSampleBuffer
        // presentation timestamp during a window-server transition. The pipeline
        // needs a monotonic source clock to keep pairing frames; systemUptime is
        // monotonic and remains valid while the game window is being recreated.
        return CMTime(
            seconds: ProcessInfo.processInfo.systemUptime,
            preferredTimescale: 1_000_000_000
        )
    }

    private func displayTime(from sampleBuffer: CMSampleBuffer) -> UInt64? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[AnyHashable: Any]],
              let rawValue = attachments.first?[SCStreamFrameInfo.displayTime] else {
            return nil
        }

        if let number = rawValue as? NSNumber {
            return number.uint64Value
        }
        return rawValue as? UInt64
    }

    private static func machAbsoluteTimeToSeconds(_ value: UInt64) -> Double {
        let timebase = machTimebase
        return Double(value) * Double(timebase.numer)
            / Double(timebase.denom)
            / 1_000_000_000
    }

    private func withStateLock<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
