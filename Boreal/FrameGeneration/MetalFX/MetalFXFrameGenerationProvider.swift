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
    private var latestStatistics = FrameGenerationStatistics()
    private var gamePID: pid_t?
    private var resolvedWindow: ResolvedGameWindow?

    func capabilities() -> FrameGenerationCapabilities {
        MetalFXFrameGenerationSupport.capabilities()
    }

    func start(gamePID: pid_t, configuration: FrameGenerationRuntimeConfiguration) async throws {
        await stop()
        guard configuration.enabled, configuration.backend == .metalFX else { return }
        let capabilities = capabilities()
        guard capabilities.isSupported else {
            throw FrameGenerationError.unsupportedHardware
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw FrameGenerationError.metalDeviceUnavailable
        }

        if MotionVectorDiagnostic.isEnabled {
            let logger = logger
            Task.detached {
                await MotionVectorDiagnostic.runIfEnabled(logger: logger)
            }
        }

        logger.info("Starting MetalFX provider; game PID: \(gamePID, privacy: .public); device: \(device.name, privacy: .public)")
        let resolved = try await GameWindowResolver.resolve(gamePID: gamePID)
        logger.info("Resolved game window PID: \(resolved.processID, privacy: .public); resolution: \(resolved.pixelWidth, privacy: .public)x\(resolved.pixelHeight, privacy: .public)")

        let overlay = try FrameGenerationOverlayWindow(
            frame: resolved.frame,
            pixelWidth: resolved.pixelWidth,
            pixelHeight: resolved.pixelHeight
        )
        let renderer = FrameGenerationRenderer(layer: overlay.metalLayer, commandQueue: commandQueue)
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
                    self?.handleRuntimeError(error)
                }
            }
        )

        do {
            try await capture.start(
                window: resolved.window,
                width: resolved.pixelWidth,
                height: resolved.pixelHeight
            )
            guard await pipeline.waitForFirstFrame() else {
                throw FrameGenerationError.captureFailed("Timed out waiting for the first captured frame.")
            }

            let controller = try FrameGenerationTimingController(
                metalLayer: overlay.metalLayer,
                updateHandler: { [weak pipeline] drawable, targetTimestamp, targetPresentationTimestamp in
                    guard let pipeline else { return }
                    Task {
                        await pipeline.presentNext(
                            drawable: drawable,
                            targetTimestamp: targetTimestamp,
                            targetPresentationTimestamp: targetPresentationTimestamp
                        )
                    }
                }
            )
            overlay.show()
            controller.start()

            self.capture = capture
            self.pipeline = pipeline
            self.overlay = overlay
            self.timingController = controller
            self.gamePID = gamePID
            self.resolvedWindow = resolved
            overlay.setStatisticsVisible(configuration.showStatistics)
            startGeometryTracking()
            startStatisticsTracking(pipeline: pipeline)
            logger.info("MetalFX provider running; capture resolution: \(resolved.pixelWidth, privacy: .public)x\(resolved.pixelHeight, privacy: .public)")
        } catch {
            await capture.stop()
            await pipeline.stop()
            overlay.close()
            throw mapStartError(error)
        }
    }

    func stop() async {
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
        guard let previous = resolvedWindow,
              let overlay,
              let capture,
              let pipeline else { return }
        resolvedWindow = resolved
        overlay.updateGeometry(
            frame: resolved.frame,
            pixelWidth: resolved.pixelWidth,
            pixelHeight: resolved.pixelHeight
        )

        let windowChanged = previous.windowID != resolved.windowID || previous.processID != resolved.processID
        if windowChanged {
            do {
                await pipeline.resetTemporalState(reason: .windowChanged)
                await capture.stop()
                try await capture.start(
                    window: resolved.window,
                    width: resolved.pixelWidth,
                    height: resolved.pixelHeight
                )
                logger.info("Frame Generation capture restarted for a new game window")
            } catch {
                handleRuntimeError(error)
            }
            return
        }

        guard previous.pixelWidth != resolved.pixelWidth || previous.pixelHeight != resolved.pixelHeight else { return }
        do {
            try await capture.updateDimensions(width: resolved.pixelWidth, height: resolved.pixelHeight)
            try await pipeline.resizeIfNeeded(width: resolved.pixelWidth, height: resolved.pixelHeight)
            logger.info("Frame Generation resized to \(resolved.pixelWidth, privacy: .public)x\(resolved.pixelHeight, privacy: .public)")
        } catch {
            handleRuntimeError(error)
        }
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

    private func mapStartError(_ error: Error) -> Error {
        if let error = error as? FrameGenerationError { return error }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain && (nsError.code == -3801 || nsError.code == -3803) {
            return FrameGenerationError.screenCapturePermissionDenied
        }
        return FrameGenerationError.captureFailed(error.localizedDescription)
    }
}
