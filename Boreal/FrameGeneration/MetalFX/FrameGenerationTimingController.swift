import AppKit
@preconcurrency import QuartzCore

nonisolated final class FrameGenerationTimingController: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    typealias UpdateHandler = @Sendable (
        _ drawable: CAMetalDrawable,
        _ targetTimestamp: CFTimeInterval,
        _ targetPresentationTimestamp: CFTimeInterval
    ) -> Void

    private let displayLink: CAMetalDisplayLink
    private let updateHandler: UpdateHandler
    private let runLoop: RunLoop
    private var isStarted = false

    init(metalLayer: CAMetalLayer, updateHandler: @escaping UpdateHandler) throws {
        self.displayLink = CAMetalDisplayLink(metalLayer: metalLayer)
        self.updateHandler = updateHandler
        self.runLoop = .main
        super.init()
        displayLink.delegate = self
        displayLink.preferredFrameLatency = 1
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 240,
            preferred: 120
        )
        displayLink.isPaused = true
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        displayLink.add(to: runLoop, forMode: .common)
        displayLink.isPaused = false
    }

    func stop() {
        guard isStarted else {
            displayLink.isPaused = true
            return
        }
        displayLink.isPaused = true
        displayLink.remove(from: runLoop, forMode: .common)
        isStarted = false
    }

    deinit {
        displayLink.isPaused = true
        displayLink.remove(from: runLoop, forMode: .common)
        displayLink.invalidate()
    }

    func metalDisplayLink(
        _ link: CAMetalDisplayLink,
        needsUpdate update: CAMetalDisplayLink.Update
    ) {
        updateHandler(
            update.drawable,
            update.targetTimestamp,
            update.targetPresentationTimestamp
        )
    }
}
