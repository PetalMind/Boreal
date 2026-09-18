import CoreMedia
import CoreVideo
import Foundation
import os
@preconcurrency import Metal
@preconcurrency import QuartzCore

actor MetalFXFrameGenerationPipeline {
    private enum FrameKind {
        case real
        case generated
    }

    private struct PresentationItem: @unchecked Sendable {
        let texture: MTLTexture
        let owner: CapturedGameFrame?
        let kind: FrameKind
        let epoch: UInt64
        let sourceSequence: UInt64
        let sourceTimestamp: CMTime
        let previousSourceSequence: UInt64?
        let previousSourceTimestamp: CMTime?
        let currentSourceTimestamp: CMTime?
        let interpolationFactor: Double?
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
    private let presentationCapacity: Int
    private let textureCache: CVMetalTextureCache
    private let logger = Logger(subsystem: "STDMSolution.Boreal", category: "FrameGeneration")
    private let verboseDiagnostics = ProcessInfo.processInfo.environment["BOREAL_METALFX_VERBOSE_DIAGNOSTICS"] == "1"

    private var interpolator: MetalFXInterpolator
    private var motionEstimator: MotionEstimator
    private var motionVectorConverter: MotionVectorConverter
    private var flatDepth: FlatDepthTextureProvider
    private var outputTextures: [MTLTexture]
    private var presentationQueue: [PresentationItem] = []
    private var previousFrame: CapturedGameFrame?
    private var pendingFrame: CapturedGameFrame?
    private var processingEpoch: UInt64?
    private var generationID: UInt64 = 1
    private var isStopped = false
    private var needsHistoryReset = true
    private var firstRealFrameSeen = false
    private var firstFrameWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    private var lastSourceTimestamp: CMTime?
    private var estimatedSourceInterval: Double?
    private var inputTimes: [Date] = []
    private var generatedTimes: [Date] = []
    private var outputTimes: [Date] = []
    private var droppedInputFrames: UInt64 = 0
    private var skippedGeneratedFrames: UInt64 = 0
    private var generationDurations: [Double] = []
    private var temporalResetCount: UInt64 = 1
    private var staleEpochDrops: UInt64 = 0
    private var motionEstimationDrops: UInt64 = 0
    private var presentationDrops: UInt64 = 0
    private var gpuErrorCount: UInt64 = 0
    private var lastTemporalResetReason: TemporalResetReason = .startup
    private var captureToPresentationLatencyMS: Double = 0

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
        self.presentationCapacity = verticalSyncEnabled
            ? (lowLatencyModeEnabled ? 3 : 4)
            : 3
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard let cache else { throw FrameGenerationError.metalDeviceUnavailable }
        textureCache = cache
        interpolator = try MetalFXInterpolator(
            device: device,
            width: width,
            height: height,
            parameters: .fallback
        )
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

    func waitForFirstFrame(timeout: Duration = .seconds(2)) async -> Bool {
        if firstRealFrameSeen { return true }
        let waiterID = UUID()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { [weak self] in
                guard let self else { return false }
                return await self.waitForFirstFrameSignal(id: waiterID)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            if !result {
                cancelFirstFrameWaiter(id: waiterID)
            }
            return result
        }
    }

    func consume(_ frame: CapturedGameFrame) {
        guard !isStopped else { return }
        record(&inputTimes)

        if let discontinuity = updateSourceTiming(for: frame) {
            resetTemporalState(reason: discontinuity)
            previousFrame = frame
            enqueue(real: frame)
            return
        }

        guard let previousFrame else {
            self.previousFrame = frame
            enqueue(real: frame)
            return
        }

        guard processingEpoch == nil else {
            if lowLatencyModeEnabled || pendingFrame == nil {
                if pendingFrame != nil { droppedInputFrames += 1 }
                pendingFrame = frame
            } else {
                droppedInputFrames += 1
            }
            return
        }

        guard areConsecutive(previousFrame, frame) else {
            resetTemporalState(reason: .frameContinuityLoss)
            self.previousFrame = frame
            enqueue(real: frame)
            return
        }

        beginPair(previous: previousFrame, current: frame)
    }

    func presentNext(
        drawable: CAMetalDrawable,
        targetTimestamp: CFTimeInterval,
        targetPresentationTimestamp: CFTimeInterval
    ) {
        guard !isStopped else { return }

        while !presentationQueue.isEmpty {
            let item = presentationQueue.removeFirst()
            guard item.epoch == generationID else {
                staleEpochDrops += 1
                recycleOutputIfCurrent(item)
                continue
            }

            record(&outputTimes)
            recordCaptureToPresentationLatency(
                item: item,
                targetPresentationTimestamp: targetPresentationTimestamp
            )
            tracePresentation(
                item: item,
                targetTimestamp: targetTimestamp,
                targetPresentationTimestamp: targetPresentationTimestamp
            )

            let didSubmit = renderer.present(
                texture: item.texture,
                drawable: drawable
            ) { [weak self, item] in
                guard let self else { return }
                Task { await self.releaseOutput(item) }
            }
            if !didSubmit {
                presentationDrops += 1
                recycleOutputIfCurrent(item)
            }
            return
        }
    }

    func resizeIfNeeded(width: Int, height: Int) throws {
        guard interpolator.width != width || interpolator.height != height else { return }
        resetTemporalState(reason: .resize)
        interpolator = try MetalFXInterpolator(
            device: device,
            width: width,
            height: height,
            parameters: .fallback
        )
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
        resetTemporalState(reason: .captureRestart)
        for waiter in firstFrameWaiters.values {
            waiter.resume(returning: false)
        }
        firstFrameWaiters.removeAll()
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
                : generationDurations.reduce(0, +) / Double(generationDurations.count),
            temporalResetCount: temporalResetCount,
            staleEpochDrops: staleEpochDrops,
            motionEstimationDrops: motionEstimationDrops,
            presentationDrops: presentationDrops,
            gpuErrorCount: gpuErrorCount,
            lastTemporalResetReason: lastTemporalResetReason,
            captureToPresentationLatencyMS: captureToPresentationLatencyMS
        )
    }

    private func waitForFirstFrameSignal(id: UUID) async -> Bool {
        if firstRealFrameSeen { return true }
        return await withCheckedContinuation { continuation in
            if firstRealFrameSeen {
                continuation.resume(returning: true)
            } else if isStopped {
                continuation.resume(returning: false)
            } else {
                firstFrameWaiters[id] = continuation
            }
        }
    }

    private func cancelFirstFrameWaiter(id: UUID) {
        guard let waiter = firstFrameWaiters.removeValue(forKey: id) else { return }
        waiter.resume(returning: false)
    }

    private func beginPair(previous: CapturedGameFrame, current: CapturedGameFrame) {
        guard processingEpoch == nil, !isStopped else { return }
        let epoch = generationID
        previousFrame = current
        processingEpoch = epoch
        Task { await processPair(previous: previous, current: current, epoch: epoch) }
    }

    private func processPair(
        previous: CapturedGameFrame,
        current: CapturedGameFrame,
        epoch: UInt64
    ) async {
        let startedAt = Date()
        let estimator = motionEstimator
        do {
            let motionPixelBuffer = try await estimator.estimate(
                previous: previous.pixelBuffer,
                current: current.pixelBuffer
            )
            guard epoch == generationID, processingEpoch == epoch, !isStopped else {
                staleEpochDrops += 1
                finishPair(epoch: epoch)
                return
            }

            guard let motion = makeMotionTexture(motionPixelBuffer),
                  let output = outputTextures.popLast(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                motionEstimationDrops += 1
                failPair(current: current, epoch: epoch, reason: .motionEstimatorRecreation)
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
            guard deltaTime.isFinite, deltaTime > 0,
                  let estimatedSourceInterval,
                  deltaTime <= max(estimatedSourceInterval * 3, 0.1) else {
                outputTextures.append(output)
                failPair(current: current, epoch: epoch, reason: .timestampDiscontinuity)
                return
            }

            let resetHistory = needsHistoryReset
            interpolator.encode(
                previous: previous.texture,
                current: current.texture,
                motion: motion.texture,
                depth: flatDepth.texture,
                output: output,
                deltaTime: Float(deltaTime),
                resetHistory: resetHistory,
                commandBuffer: commandBuffer
            )
            needsHistoryReset = false

            let generatedItem = PresentationItem(
                texture: output,
                owner: nil,
                kind: .generated,
                epoch: epoch,
                sourceSequence: current.sequence,
                sourceTimestamp: current.presentationTime,
                previousSourceSequence: previous.sequence,
                previousSourceTimestamp: previous.presentationTime,
                currentSourceTimestamp: current.presentationTime,
                interpolationFactor: 0.5
            )
            commandBuffer.addCompletedHandler { [weak self, motion] buffer in
                _ = motion.sourceReference
                _ = motion.sourceBuffer
                Task {
                    guard let self else { return }
                    await self.finishGPU(
                        buffer: buffer,
                        item: generatedItem,
                        current: current,
                        epoch: epoch,
                        duration: Date().timeIntervalSince(startedAt)
                    )
                }
            }
            commandBuffer.commit()
        } catch {
            motionEstimationDrops += 1
            failPair(current: current, epoch: epoch, reason: .motionEstimatorRecreation)
        }
    }

    private func finishGPU(
        buffer: MTLCommandBuffer,
        item: PresentationItem,
        current: CapturedGameFrame,
        epoch: UInt64,
        duration: TimeInterval
    ) {
        guard epoch == generationID, processingEpoch == epoch, !isStopped else {
            staleEpochDrops += 1
            finishPair(epoch: epoch)
            return
        }
        guard buffer.status == .completed else {
            gpuErrorCount += 1
            failPair(current: current, epoch: epoch, reason: .gpuError)
            return
        }

        generationDurations.append(duration * 1_000)
        record(&generatedTimes)
        enqueue(item)
        enqueue(real: current)
        finishPair(epoch: epoch)
    }

    private func finishPair(epoch: UInt64) {
        guard processingEpoch == epoch else { return }
        processingEpoch = nil
        guard !isStopped,
              let pendingFrame,
              let previousFrame else { return }
        self.pendingFrame = nil

        guard areConsecutive(previousFrame, pendingFrame) else {
            resetTemporalState(reason: .frameContinuityLoss)
            self.previousFrame = pendingFrame
            enqueue(real: pendingFrame)
            return
        }
        beginPair(previous: previousFrame, current: pendingFrame)
    }

    private func failPair(
        current: CapturedGameFrame,
        epoch: UInt64,
        reason: TemporalResetReason
    ) {
        guard epoch == generationID, processingEpoch == epoch, !isStopped else {
            finishPair(epoch: epoch)
            return
        }
        resetTemporalState(reason: reason)
        previousFrame = current
        enqueue(real: current)
        finishPair(epoch: epoch)
    }

    func resetTemporalState(reason: TemporalResetReason) {
        generationID &+= 1
        needsHistoryReset = true
        previousFrame = nil
        pendingFrame = nil
        lastSourceTimestamp = nil
        estimatedSourceInterval = nil
        clearPresentationQueue()
        firstRealFrameSeen = false
        temporalResetCount &+= 1
        lastTemporalResetReason = reason
        logger.info("[FrameGeneration] Temporal reset: \(reason.displayName, privacy: .public); epoch=\(self.generationID, privacy: .public)")
    }

    private func updateSourceTiming(for frame: CapturedGameFrame) -> TemporalResetReason? {
        let timestamp = frame.presentationTime.seconds
        guard timestamp.isFinite else { return .timestampDiscontinuity }
        defer { lastSourceTimestamp = frame.presentationTime }
        guard let lastSourceTimestamp else { return nil }
        let delta = timestamp - lastSourceTimestamp.seconds
        guard delta.isFinite, delta > 0 else { return .timestampDiscontinuity }
        if let estimatedSourceInterval,
           delta > max(estimatedSourceInterval * 3, 0.1) {
            self.estimatedSourceInterval = nil
            return .timestampDiscontinuity
        }
        estimatedSourceInterval = estimatedSourceInterval.map { $0 * 0.9 + delta * 0.1 } ?? delta
        return nil
    }

    private func areConsecutive(_ previous: CapturedGameFrame, _ current: CapturedGameFrame) -> Bool {
        current.sequence == previous.sequence &+ 1
    }

    private func enqueue(real frame: CapturedGameFrame) {
        enqueue(PresentationItem(
            texture: frame.texture,
            owner: frame,
            kind: .real,
            epoch: generationID,
            sourceSequence: frame.sequence,
            sourceTimestamp: frame.presentationTime,
            previousSourceSequence: nil,
            previousSourceTimestamp: nil,
            currentSourceTimestamp: nil,
            interpolationFactor: nil
        ))
        if !firstRealFrameSeen {
            firstRealFrameSeen = true
            for waiter in firstFrameWaiters.values {
                waiter.resume(returning: true)
            }
            firstFrameWaiters.removeAll()
        }
    }

    private func enqueue(_ item: PresentationItem) {
        presentationQueue.append(item)
        while presentationQueue.count > presentationCapacity {
            guard let removed = presentationQueue.first else { break }
            presentationQueue.removeFirst()
            handlePresentationDrop(removed)

            // Dropping a real source frame also drops its immediately
            // following generated frame. This prevents presenting G(B,C)
            // after B was discarded and preserves real → generated → real.
            if removed.kind == .real,
               let next = presentationQueue.first,
               next.kind == .generated,
               next.previousSourceSequence == removed.sourceSequence {
                presentationQueue.removeFirst()
                handlePresentationDrop(next)
            }
        }
    }

    private func handlePresentationDrop(_ item: PresentationItem) {
        presentationDrops += 1
        recycleOutputIfCurrent(item)
    }

    private func clearPresentationQueue() {
        while let item = presentationQueue.first {
            presentationQueue.removeFirst()
            handlePresentationDrop(item)
        }
    }

    private func recycleOutputIfCurrent(_ item: PresentationItem) {
        guard item.kind == .generated, item.epoch == generationID, !isStopped else { return }
        outputTextures.append(item.texture)
    }

    private func releaseOutput(_ item: PresentationItem) {
        recycleOutputIfCurrent(item)
    }

    private func recordCaptureToPresentationLatency(
        item: PresentationItem,
        targetPresentationTimestamp: CFTimeInterval
    ) {
        guard targetPresentationTimestamp.isFinite,
              let sourceTimestamp = effectiveSourceTimestamp(for: item),
              sourceTimestamp.isFinite else { return }
        let latency = (targetPresentationTimestamp - sourceTimestamp) * 1_000
        guard latency.isFinite, latency >= 0, latency < 30_000 else { return }
        captureToPresentationLatencyMS = captureToPresentationLatencyMS == 0
            ? latency
            : captureToPresentationLatencyMS * 0.8 + latency * 0.2
    }

    private func effectiveSourceTimestamp(for item: PresentationItem) -> Double? {
        guard item.kind == .generated,
              let previous = item.previousSourceTimestamp?.seconds,
              let current = item.currentSourceTimestamp?.seconds,
              let factor = item.interpolationFactor else {
            return item.sourceTimestamp.seconds
        }
        return previous + (current - previous) * factor
    }

    private func tracePresentation(
        item: PresentationItem,
        targetTimestamp: CFTimeInterval,
        targetPresentationTimestamp: CFTimeInterval
    ) {
        guard verboseDiagnostics else { return }
        switch item.kind {
        case .real:
            logger.debug("[FrameGeneration][PresentationTrace] REAL seq=\(item.sourceSequence, privacy: .public) source=\(item.sourceTimestamp.seconds, privacy: .public) target=\(targetTimestamp, privacy: .public) presentation=\(targetPresentationTimestamp, privacy: .public)")
        case .generated:
            logger.debug("[FrameGeneration][PresentationTrace] GENERATED pair=\(item.previousSourceSequence ?? 0, privacy: .public)->\(item.sourceSequence, privacy: .public) factor=\(item.interpolationFactor ?? 0, privacy: .public) source=\(self.effectiveSourceTimestamp(for: item) ?? 0, privacy: .public) target=\(targetTimestamp, privacy: .public) presentation=\(targetPresentationTimestamp, privacy: .public)")
        }
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
            guard status == kCVReturnSuccess, let reference,
                  let sourceTexture = CVMetalTextureGetTexture(reference) else { return nil }
            let requiresConversion = motionVectorConverter.requiresTransform
                || sourceFormat != .rg32Float
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
