import AppKit
import Foundation
import Metal
import os
import ScreenCaptureKit

@MainActor
final class MetalFXFrameGenerationProvider: FrameGenerationProvider {
    let backend: FrameGenerationBackend = .metalFX

    var runtimeErrorHandler: (@Sendable (Error) -> Void)?

    private let logger = Logger(subsystem: "STDMSolution.Boreal", category: "FrameGeneration")
    private var capture: GameWindowCapture?
    private var pipeline: MetalFXFrameGenerationPipeline?
    private var overlay: FrameGenerationOverlayWindow?
    private var timingController: FrameGenerationTimingController?
    private var geometryTask: Task<Void, Never>?
    private var statisticsTask: Task<Void, Never>?
    private var captureRecoveryTask: Task<Void, Never>?
    private var latestStatistics = FrameGenerationStatistics()
    private var gamePID: pid_t?
    private var resolvedWindow: ResolvedGameWindow?
    private var isStopping = true
    private var providerIsRunning = false
    private var captureReconfigurationInFlight = false

    func capabilities() -> FrameGenerationCapabilities {
        MetalFXFrameGenerationSupport.capabilities()
    }

    func start(gamePID: pid_t, configuration: FrameGenerationRuntimeConfiguration) async throws {
        await stop()
        isStopping = false
        providerIsRunning = false
        logger.info(
            "MetalFX provider start entered; game PID: \(gamePID, privacy: .public), enabled: \(configuration.enabled, privacy: .public), backend: \(configuration.backend.rawValue, privacy: .public)"
        )
        guard configuration.enabled, configuration.backend == .metalFX else { return }

        if MotionVectorDiagnostic.isEnabled {
            let logger = logger
            Task.detached {
                await MotionVectorDiagnostic.runIfEnabled(logger: logger)
            }
        }

        let capabilities = capabilities()
        guard capabilities.isSupported else {
            if #available(macOS 26.0, *), !MotionEstimator.isAvailable {
                throw FrameGenerationError.motionEstimatorUnavailable
            }
            throw FrameGenerationError.unsupportedHardware
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw FrameGenerationError.metalDeviceUnavailable
        }

        logger.info("Starting MetalFX provider; game PID: \(gamePID, privacy: .public); device: \(device.name, privacy: .public)")
        try GameWindowResolver.requireScreenCaptureAccess()
        let resolved = try await GameWindowResolver.resolve(gamePID: gamePID)
        logger.info("Resolved game window PID: \(resolved.processID, privacy: .public); resolution: \(resolved.pixelWidth, privacy: .public)x\(resolved.pixelHeight, privacy: .public)")

        let overlay = try FrameGenerationOverlayWindow(
            frame: resolved.frame,
            pixelWidth: resolved.pixelWidth,
            pixelHeight: resolved.pixelHeight,
            device: device
        )
        let renderer = FrameGenerationRenderer(commandQueue: commandQueue)
        let pipeline = try MetalFXFrameGenerationPipeline(
            device: device,
            commandQueue: commandQueue,
            renderer: renderer,
            width: resolved.pixelWidth,
            height: resolved.pixelHeight,
            lowLatencyModeEnabled: configuration.lowLatencyModeEnabled,
            verticalSyncEnabled: configuration.verticalSyncEnabled
        )

        let capture = GameWindowCapture(
            device: device,
            frameHandler: { frame in
                Task { await pipeline.consume(frame) }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleCaptureStreamError(error)
                }
            }
        )

        self.capture = capture
        self.pipeline = pipeline
        self.overlay = overlay
        self.gamePID = gamePID
        self.resolvedWindow = resolved

        do {
            let captureEpoch = try await capture.start(
                window: resolved.window,
                width: resolved.pixelWidth,
                height: resolved.pixelHeight
            )
            await pipeline.acceptCaptureEpoch(captureEpoch)
            guard await pipeline.waitForFirstFrame() else {
                throw FrameGenerationError.captureFailed("Timed out waiting for the first captured frame.")
            }

            let presentationGate = FrameGenerationPresentationGate()
            let controller = FrameGenerationTimingController(
                metalLayer: overlay.metalLayer,
                updateHandler: { [weak pipeline] drawable, targetTimestamp, targetPresentationTimestamp in
                    guard let pipeline, presentationGate.tryAcquire() else { return }
                    Task {
                        await pipeline.presentNext(
                            drawable: drawable,
                            targetTimestamp: targetTimestamp,
                            targetPresentationTimestamp: targetPresentationTimestamp
                        )
                        presentationGate.release()
                    }
                }
            )
            overlay.show(focusProcessID: resolved.processID)
            overlay.setDisplaySyncEnabled(configuration.verticalSyncEnabled)
            controller.start()

            self.timingController = controller
            providerIsRunning = true
            overlay.setStatisticsVisible(configuration.showStatistics)
            startGeometryTracking()
            startStatisticsTracking(pipeline: pipeline)
            logger.info("MetalFX provider running; capture resolution: \(resolved.pixelWidth, privacy: .public)x\(resolved.pixelHeight, privacy: .public)")
        } catch {
            await capture.stop()
            await pipeline.stop()
            overlay.close()
            clearResources()
            throw mapStartError(error)
        }
    }

    func stop() async {
        isStopping = true
        providerIsRunning = false
        captureRecoveryTask?.cancel()
        captureRecoveryTask = nil
        geometryTask?.cancel()
        statisticsTask?.cancel()
        geometryTask = nil
        statisticsTask = nil
        timingController?.stop()
        timingController = nil
        if let capture { await capture.stop() }
        if let pipeline { await pipeline.stop() }
        overlay?.close()
        capture = nil
        pipeline = nil
        overlay = nil
        gamePID = nil
        resolvedWindow = nil
        latestStatistics = FrameGenerationStatistics()
        captureReconfigurationInFlight = false
        logger.info("Stopped MetalFX provider")
    }

    func statistics() -> FrameGenerationStatistics {
        latestStatistics
    }

    private func startGeometryTracking() {
        geometryTask?.cancel()
        geometryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, let gamePID = self.gamePID else { return }
                guard let resolved = try? await GameWindowResolver.resolve(
                    gamePID: gamePID,
                    timeout: .milliseconds(300)
                ) else { continue }
                await self.updateGeometry(resolved)
            }
        }
    }

    private func updateGeometry(_ resolved: ResolvedGameWindow) async {
        guard let previous = resolvedWindow else { return }

        let windowChanged = previous.windowID != resolved.windowID || previous.processID != resolved.processID
        let dimensionsChanged = previous.pixelWidth != resolved.pixelWidth
            || previous.pixelHeight != resolved.pixelHeight
        guard windowChanged || dimensionsChanged else { return }

        do {
            try await restartCapture(
                resolved: resolved,
                reason: windowChanged ? .windowChanged : .resize
            )
            if windowChanged {
                logger.info("Frame Generation capture restarted for a new game window")
            } else {
                logger.info("Frame Generation resized to \(resolved.pixelWidth, privacy: .public)x\(resolved.pixelHeight, privacy: .public)")
            }
        } catch {
            logger.error("Frame Generation geometry update failed; scheduling capture recovery: \(error.localizedDescription, privacy: .public)")
            scheduleCaptureRecovery()
        }
    }

    private func restartCapture(
        resolved: ResolvedGameWindow,
        reason: TemporalResetReason
    ) async throws {
        while captureReconfigurationInFlight {
            try await Task.sleep(for: .milliseconds(50))
            guard !isStopping else {
                throw FrameGenerationError.captureFailed("Frame generation is stopping.")
            }
        }

        guard let capture, let pipeline, let overlay else {
            throw FrameGenerationError.captureFailed("Frame generation resources are unavailable.")
        }

        captureReconfigurationInFlight = true
        defer { captureReconfigurationInFlight = false }

        // Stop the old stream before rebuilding MetalFX resources. This prevents
        // frames from the old window or dimensions from entering the new epoch.
        await pipeline.invalidateCaptureEpoch(reason: reason)
        guard !isStopping else { return }
        await capture.stop()
        guard !isStopping else { return }
        try await pipeline.resizeIfNeeded(width: resolved.pixelWidth, height: resolved.pixelHeight)
        guard !isStopping else { return }
        let captureEpoch = try await capture.start(
            window: resolved.window,
            width: resolved.pixelWidth,
            height: resolved.pixelHeight
        )
        guard !isStopping else {
            await capture.stop()
            return
        }
        await pipeline.acceptCaptureEpoch(captureEpoch)
        overlay.updateGeometry(
            frame: resolved.frame,
            pixelWidth: resolved.pixelWidth,
            pixelHeight: resolved.pixelHeight
        )
        resolvedWindow = resolved
    }

    private func handleCaptureStreamError(_ error: Error) {
        guard !isStopping, providerIsRunning else { return }
        if isPermanentCaptureError(error) {
            handleRuntimeError(error)
            return
        }

        logger.error("Frame Generation capture stream stopped; scheduling recovery: \(error.localizedDescription, privacy: .public)")
        scheduleCaptureRecovery()
    }

    private func scheduleCaptureRecovery() {
        guard !isStopping, providerIsRunning, captureRecoveryTask == nil else { return }
        captureRecoveryTask = Task { [weak self] in
            await self?.recoverCapture()
        }
    }

    private func recoverCapture() async {
        defer { captureRecoveryTask = nil }
        guard let gamePID else { return }

        let retryDelays: [Duration] = [
            .milliseconds(100),
            .milliseconds(250),
            .milliseconds(500),
            .seconds(1),
            .seconds(2),
            .seconds(3),
            .seconds(4),
            .seconds(5)
        ]

        for (index, delay) in retryDelays.enumerated() {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !isStopping, providerIsRunning else { return }

            do {
                let resolved = try await GameWindowResolver.resolve(
                    gamePID: gamePID,
                    timeout: .seconds(2)
                )
                try await restartCapture(resolved: resolved, reason: .captureRestart)
                logger.info("Frame Generation capture recovered on attempt \(index + 1, privacy: .public)")
                return
            } catch {
                logger.error("Frame Generation capture recovery attempt \(index + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !Task.isCancelled, !isStopping else { return }
        handleRuntimeError(
            FrameGenerationError.captureFailed(
                "ScreenCaptureKit did not recover the game window after a capture interruption."
            )
        )
    }

    private func isPermanentCaptureError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return false }
        return nsError.code == -3801
            || nsError.code == -3803
            || nsError.code == -3817
    }

    private func startStatisticsTracking(pipeline: MetalFXFrameGenerationPipeline) {
        statisticsTask?.cancel()
        statisticsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let statistics = await pipeline.statistics()
                self?.latestStatistics = statistics
                self?.overlay?.updateStatistics(statistics)
            }
        }
    }

    private func handleRuntimeError(_ error: Error) {
        logger.error("Frame Generation error: \(error.localizedDescription, privacy: .public)")
        runtimeErrorHandler?(error)
        Task { [weak self] in await self?.stop() }
    }

    private func clearResources() {
        geometryTask?.cancel()
        statisticsTask?.cancel()
        captureRecoveryTask?.cancel()
        geometryTask = nil
        statisticsTask = nil
        captureRecoveryTask = nil
        captureReconfigurationInFlight = false
        timingController?.stop()
        timingController = nil
        capture = nil
        pipeline = nil
        overlay = nil
        gamePID = nil
        resolvedWindow = nil
        providerIsRunning = false
    }

    private func mapStartError(_ error: Error) -> Error {
        if let error = error as? FrameGenerationError { return error }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain && (nsError.code == -3801 || nsError.code == -3803) {
            return FrameGenerationError.screenCapturePermissionDenied
        }
        return FrameGenerationError.captureFailed(error.localizedDescription)
    }
}
