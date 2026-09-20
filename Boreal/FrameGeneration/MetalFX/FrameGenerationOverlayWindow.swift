import AppKit
import Metal
import os
@preconcurrency import QuartzCore

@MainActor
final class FrameGenerationOverlayWindow {
    private let panel: FrameGenerationOverlayPanel
    private let metalView: FrameGenerationMetalView
    private let hudView: FrameGenerationHUDView

    init(frame: CGRect, pixelWidth: Int, pixelHeight: Int, device: MTLDevice) throws {
        metalView = FrameGenerationMetalView(frame: .zero)
        hudView = FrameGenerationHUDView(frame: .zero)
        panel = FrameGenerationOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // This window presents the generated image, but it must never become
        // the active/key window. Otherwise the full-screen MetalFX surface
        // steals keyboard focus from the Wine game even though mouse events
        // are configured to pass through it.
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        // This surface is output-only. It must never enter AppKit's key-window
        // negotiation, even briefly while the game is entering fullscreen.
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        // A shielding-level window sits above the normal event routing stack.
        // A floating auxiliary window is sufficient for presentation and lets
        // the game remain the frontmost input owner.
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.worksWhenModal = true
        panel.sharingType = .none
        panel.contentView = metalView
        // On macOS CAMetalLayer has no default device. Set it before the
        // CAMetalDisplayLink asks the layer for its first drawable.
        metalView.metalLayer.device = device
        metalView.addSubview(hudView)
        hudView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hudView.leadingAnchor.constraint(equalTo: metalView.leadingAnchor, constant: 14),
            hudView.topAnchor.constraint(equalTo: metalView.topAnchor, constant: 14),
            hudView.widthAnchor.constraint(greaterThanOrEqualToConstant: 264),
            hudView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])
        hudView.updateResolution(width: pixelWidth, height: pixelHeight)
        updateGeometry(frame: frame, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    var metalLayer: CAMetalLayer { metalView.metalLayer }

    func show(focusProcessID: pid_t) {
        panel.orderFrontRegardless()
        panel.resignKey()

        // Ordering a window from Boreal can leave Boreal as the active macOS
        // application even when the panel is non-activating. Return focus to
        // the process that owns the captured game window so keyboard and mouse
        // input continue to reach Wine.
        NSApp.deactivate()
        if let gameApplication = NSRunningApplication(processIdentifier: focusProcessID) {
            gameApplication.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }

    func updateGeometry(frame: CGRect, pixelWidth: Int, pixelHeight: Int) {
        panel.setFrame(frame, display: false)
        metalView.frame = metalView.superview?.bounds ?? CGRect(origin: .zero, size: frame.size)
        metalView.metalLayer.drawableSize = CGSize(width: max(1, pixelWidth), height: max(1, pixelHeight))
        metalView.metalLayer.contentsScale = panel.backingScaleFactor
        hudView.updateResolution(width: pixelWidth, height: pixelHeight)
    }

    func setStatisticsVisible(_ visible: Bool) {
        hudView.setStatisticsVisible(visible)
    }

    func setDisplaySyncEnabled(_ enabled: Bool) {
        metalView.metalLayer.displaySyncEnabled = enabled
    }

    func updateStatistics(_ statistics: FrameGenerationStatistics) {
        hudView.updateStatistics(statistics)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

@MainActor
private final class FrameGenerationOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class FrameGenerationHUDView: NSVisualEffectView {
    private let titleLabel = NSTextField(labelWithString: "Boreal • MetalFX Frame Generation")
    private let resolutionLabel = NSTextField(labelWithString: "")
    private let statisticsLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        resolutionLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        resolutionLabel.textColor = .white.withAlphaComponent(0.75)
        statisticsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        statisticsLabel.textColor = .white
        detailLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = .white.withAlphaComponent(0.75)
        detailLabel.maximumNumberOfLines = 4
        detailLabel.lineBreakMode = .byWordWrapping

        [titleLabel, resolutionLabel, statisticsLabel, detailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            resolutionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            resolutionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            resolutionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            statisticsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statisticsLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            statisticsLabel.topAnchor.constraint(equalTo: resolutionLabel.bottomAnchor, constant: 5),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: statisticsLabel.bottomAnchor, constant: 2),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        setStatisticsVisible(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func updateResolution(width: Int, height: Int) {
        resolutionLabel.stringValue = "MetalFX • \(max(1, width))×\(max(1, height))"
    }

    func setStatisticsVisible(_ visible: Bool) {
        statisticsLabel.isHidden = !visible
        detailLabel.isHidden = !visible
    }

    func updateStatistics(_ statistics: FrameGenerationStatistics) {
        statisticsLabel.stringValue = String(
            format: "Input %3.0f  •  Generated %3.0f  •  Output %3.0f FPS",
            statistics.inputFPS,
            statistics.generatedFPS,
            statistics.outputFPS
        )
        detailLabel.stringValue = String(
            format: "Dropped %llu  •  Skipped %llu  •  %.1f ms\nResets %llu  •  Stale %llu  •  Motion %llu\nGPU %llu  •  Presentation drops %llu\nCapture→Presentation %.1f ms  •  Last reset: %@",
            statistics.droppedInputFrames,
            statistics.skippedGeneratedFrames,
            statistics.averageGenerationTimeMS,
            statistics.temporalResetCount,
            statistics.staleEpochDrops,
            statistics.motionEstimationDrops,
            statistics.gpuErrorCount,
            statistics.presentationDrops,
            statistics.captureToPresentationLatencyMS,
            statistics.lastTemporalResetReason?.displayName ?? "—"
        )
    }
}

@MainActor
private final class FrameGenerationMetalView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.isOpaque = true
        return layer
    }

    var metalLayer: CAMetalLayer {
        if let layer = layer as? CAMetalLayer { return layer }
        let layer = makeBackingLayer() as! CAMetalLayer
        self.layer = layer
        return layer
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}

nonisolated final class FrameGenerationRenderer: @unchecked Sendable {
    private let commandQueue: MTLCommandQueue
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    private let logger = Logger(subsystem: "STDMSolution.Boreal", category: "FrameGeneration")

    init(commandQueue: MTLCommandQueue) {
        self.commandQueue = commandQueue
    }

    func present(
        texture: MTLTexture,
        drawable: CAMetalDrawable,
        completion: @escaping @Sendable (_ succeeded: Bool) -> Void
    ) -> Bool {
        let drawableTexture = drawable.texture
        guard texture.width == drawableTexture.width,
              texture.height == drawableTexture.height,
              texture.pixelFormat == drawableTexture.pixelFormat else {
            logger.error(
                "Skipping MetalFX presentation with incompatible drawable; source=\(texture.width, privacy: .public)x\(texture.height, privacy: .public)/\(String(describing: texture.pixelFormat), privacy: .public), drawable=\(drawableTexture.width, privacy: .public)x\(drawableTexture.height, privacy: .public)/\(String(describing: drawableTexture.pixelFormat), privacy: .public)"
            )
            // CAMetalLayer can hand out one drawable from the previous
            // geometry epoch while the game/capture window is resizing. Do
            // not call copyFromTexture here: Metal asserts on a size or
            // format mismatch and terminates the whole Boreal process.
            drawable.layer.drawableSize = CGSize(
                width: texture.width,
                height: texture.height
            )
            return false
        }
        guard inFlightSemaphore.wait(timeout: .now()) == .success else {
            return false
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return false
        }
        commandBuffer.addCompletedHandler { [inFlightSemaphore] commandBuffer in
            inFlightSemaphore.signal()
            completion(commandBuffer.status == .completed)
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            inFlightSemaphore.signal()
            return false
        }
        blit.copy(from: texture, to: drawable.texture)
        blit.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }
}
