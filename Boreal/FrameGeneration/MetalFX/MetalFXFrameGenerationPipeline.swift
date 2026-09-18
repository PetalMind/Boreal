import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import Metal

actor MetalFXFrameGenerationPipeline {
    private struct PresentationItem: @unchecked Sendable {
        let texture: MTLTexture
        let owner: CapturedGameFrame?
        let isGenerated: Bool
    }

    private struct MotionTexture: @unchecked Sendable {
        let texture: MTLTexture
        let sourceTexture: MTLTexture?
        let sourceReference: CVMetalTexture
        let sourceBuffer: CVReadOnlyPixelBuffer
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderer: FrameGenerationRenderer
    private let lowLatencyModeEnabled: Bool
    private let verticalSyncEnabled: Bool
    private let textureCache: CVMetalTextureCache
    private var interpolator: MetalFXInterpolator
    private var motionEstimator: MotionEstimator
    private var motionVectorConverter: MotionVectorConverter
    private var flatDepth: FlatDepthTextureProvider
    private var outputTextures: [MTLTexture]
    private var presentationQueue = FrameRingBuffer<PresentationItem>(capacity: 3)
    private var previousFrame: CapturedGameFrame?
    private var pendingFrame: CapturedGameFrame?
    private var isProcessing = false
    private var isStopped = false

    private var inputTimes: [Date] = []
    private var generatedTimes: [Date] = []
    private var outputTimes: [Date] = []
    private var droppedInputFrames: UInt64 = 0
    private var skippedGeneratedFrames: UInt64 = 0
    private var generationDurations: [Double] = []

    init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        renderer: FrameGenerationRenderer,
        width: Int,
        height: Int,
        lowLatencyModeEnabled: Bool,
        verticalSyncEnabled: Bool
    ) throws {
        self.device = device
        self.commandQueue = commandQueue
        self.renderer = renderer
        self.lowLatencyModeEnabled = lowLatencyModeEnabled
        self.verticalSyncEnabled = verticalSyncEnabled
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard let cache else { throw FrameGenerationError.metalDeviceUnavailable }
        textureCache = cache
        interpolator = try MetalFXInterpolator(device: device, width: width, height: height)
        motionEstimator = try MotionEstimator(width: width, height: height)
        motionVectorConverter = try MotionVectorConverter(device: device, width: width, height: height)
        flatDepth = try FlatDepthTextureProvider(device: device, width: width, height: height)
        outputTextures = try Self.makeOutputTextures(
            device: device,
            usage: interpolator.outputTextureUsage,
            width: width,
            height: height
        )
    }

    func consume(_ frame: CapturedGameFrame) {
        guard !isStopped else { return }
        record(&inputTimes)

        guard let previousFrame else {
            self.previousFrame = frame
            enqueue(PresentationItem(texture: frame.texture, owner: frame, isGenerated: false))
            return
        }

        guard !isProcessing else {
            if lowLatencyModeEnabled || pendingFrame == nil {
                if pendingFrame != nil { droppedInputFrames += 1 }
                pendingFrame = frame
            } else {
                droppedInputFrames += 1
            }
            return
        }

        self.previousFrame = frame
        isProcessing = true
        Task { await processPair(previous: previousFrame, current: frame) }
    }

    func presentNext() {
        guard !isStopped, let item = presentationQueue.removeFirst() else { return }
        record(&outputTimes)
        renderer.present(texture: item.texture) { [weak self] in
            guard item.isGenerated else { return }
            Task { await self?.releaseOutput(item.texture) }
        }
    }

    func resizeIfNeeded(width: Int, height: Int) throws {
        guard interpolator.width != width || interpolator.height != height else { return }
        clearPresentationQueue()
        previousFrame = nil
        pendingFrame = nil
        isProcessing = false
        interpolator = try MetalFXInterpolator(device: device, width: width, height: height)
        motionEstimator = try MotionEstimator(width: width, height: height)
        motionVectorConverter = try MotionVectorConverter(device: device, width: width, height: height)
        flatDepth = try FlatDepthTextureProvider(device: device, width: width, height: height)
        outputTextures = try Self.makeOutputTextures(
            device: device,
            usage: interpolator.outputTextureUsage,
            width: width,
            height: height
        )
    }

    func stop() {
        isStopped = true
        clearPresentationQueue()
        previousFrame = nil
        pendingFrame = nil
    }

    func statistics() -> FrameGenerationStatistics {
        let now = Date()
        prune(&inputTimes, now: now)
        prune(&generatedTimes, now: now)
        prune(&outputTimes, now: now)
        generationDurations = Array(generationDurations.suffix(120))
        return FrameGenerationStatistics(
            inputFPS: Double(inputTimes.count),
            generatedFPS: Double(generatedTimes.count),
            outputFPS: Double(outputTimes.count),
            droppedInputFrames: droppedInputFrames,
            skippedGeneratedFrames: skippedGeneratedFrames,
            averageGenerationTimeMS: generationDurations.isEmpty
                ? 0
                : generationDurations.reduce(0, +) / Double(generationDurations.count)
        )
    }

    private func processPair(previous: CapturedGameFrame, current: CapturedGameFrame) async {
        let startedAt = Date()
        do {
            let motionPixelBuffer = try await motionEstimator.estimate(
                previous: previous.pixelBuffer,
                current: current.pixelBuffer
            )
            guard let motion = makeMotionTexture(motionPixelBuffer),
                  let output = outputTextures.popLast(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                skippedGeneratedFrames += 1
                enqueue(PresentationItem(texture: current.texture, owner: current, isGenerated: false))
                finishPair(current: current)
                return
            }

            if let sourceTexture = motion.sourceTexture {
                motionVectorConverter.encode(
                    source: sourceTexture,
                    destination: motion.texture,
                    commandBuffer: commandBuffer
                )
            }

            let deltaTime = current.presentationTime.seconds - previous.presentationTime.seconds
            interpolator.encode(
                previous: previous.texture,
                current: current.texture,
                motion: motion.texture,
                depth: flatDepth.texture,
                output: output,
                deltaTime: Float(deltaTime.isFinite && deltaTime > 0 ? deltaTime : 1.0 / 60.0),
                commandBuffer: commandBuffer
            )
            let generatedItem = PresentationItem(texture: output, owner: nil, isGenerated: true)
            commandBuffer.addCompletedHandler { [weak self, motion] buffer in
                // Keep the CoreVideo and source texture objects alive until the
                // command buffer has consumed the converted motion vectors.
                _ = motion.sourceReference
                _ = motion.sourceBuffer
                Task {
                    guard let self else { return }
                    await self.finishGPU(
                        buffer: buffer,
                        item: generatedItem,
                        current: current,
                        duration: Date().timeIntervalSince(startedAt)
                    )
                }
            }
            commandBuffer.commit()
        } catch {
            skippedGeneratedFrames += 1
            enqueue(PresentationItem(texture: current.texture, owner: current, isGenerated: false))
            finishPair(current: current)
        }
    }

    private func finishGPU(
        buffer: MTLCommandBuffer,
        item: PresentationItem,
        current: CapturedGameFrame,
        duration: TimeInterval
    ) {
        guard buffer.status == .completed, !isStopped else {
            outputTextures.append(item.texture)
            if !isStopped {
                skippedGeneratedFrames += 1
                enqueue(PresentationItem(texture: current.texture, owner: current, isGenerated: false))
            }
            finishPair(current: current)
            return
        }
        generationDurations.append(duration * 1_000)
        record(&generatedTimes)
        enqueue(item)
        enqueue(PresentationItem(texture: current.texture, owner: current, isGenerated: false))
        finishPair(current: current)
    }

    private func finishPair(current: CapturedGameFrame) {
        isProcessing = false
        guard let pendingFrame else { return }
        self.pendingFrame = nil
        self.previousFrame = pendingFrame
        isProcessing = true
        Task { await processPair(previous: current, current: pendingFrame) }
    }

    private func enqueue(_ item: PresentationItem) {
        for removed in presentationQueue.append(item) where removed.isGenerated {
            outputTextures.append(removed.texture)
            skippedGeneratedFrames += 1
        }
        if !verticalSyncEnabled {
            presentNext()
        }
    }

    private func clearPresentationQueue() {
        while let item = presentationQueue.removeFirst() {
            if item.isGenerated { outputTextures.append(item.texture) }
        }
    }

    private func releaseOutput(_ texture: MTLTexture) {
        outputTextures.append(texture)
    }

    private func makeMotionTexture(_ pixelBuffer: CVReadOnlyPixelBuffer) -> MotionTexture? {
        pixelBuffer.withUnsafeBuffer { buffer in
            let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
            let sourceFormat: MTLPixelFormat
            switch pixelFormat {
            case kCVPixelFormatType_TwoComponent32Float:
                sourceFormat = .rg32Float
            case kCVPixelFormatType_TwoComponent16Half:
                sourceFormat = .rg16Float
            default:
                return nil
            }
            let sourceWidth = CVPixelBufferGetWidth(buffer)
            let sourceHeight = CVPixelBufferGetHeight(buffer)
            var reference: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                buffer,
                nil,
                sourceFormat,
                sourceWidth,
                sourceHeight,
                0,
                &reference
            )
            guard status == kCVReturnSuccess, let reference else { return nil }
            guard let sourceTexture = CVMetalTextureGetTexture(reference) else { return nil }
            let requiresConversion = sourceFormat != .rg32Float
                || sourceWidth != interpolator.width
                || sourceHeight != interpolator.height
            if requiresConversion {
                guard let destination = motionVectorConverter.makeDestinationTexture() else { return nil }
                return MotionTexture(
                    texture: destination,
                    sourceTexture: sourceTexture,
                    sourceReference: reference,
                    sourceBuffer: pixelBuffer
                )
            }
            return MotionTexture(
                texture: sourceTexture,
                sourceTexture: nil,
                sourceReference: reference,
                sourceBuffer: pixelBuffer
            )
        }
    }

    private static func makeOutputTextures(
        device: MTLDevice,
        usage: MTLTextureUsage,
        width: Int,
        height: Int
    ) throws -> [MTLTexture] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = usage.union(.shaderRead)
        let textures = (0..<3).compactMap { _ in device.makeTexture(descriptor: descriptor) }
        guard textures.count == 3 else { throw FrameGenerationError.interpolatorCreationFailed }
        return textures
    }

    private func record(_ values: inout [Date]) {
        values.append(Date())
        prune(&values, now: Date())
    }

    private func prune(_ values: inout [Date], now: Date) {
        values.removeAll { now.timeIntervalSince($0) > 1.0 }
    }
}
