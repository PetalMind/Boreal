import AppKit
@preconcurrency import QuartzCore

nonisolated final class FrameGenerationPresentationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var acquired = false

    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !acquired else { return false }
        acquired = true
        return true
    }

    func release() {
        lock.lock()
        acquired = false
        lock.unlock()
    }
}

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

    init(metalLayer: CAMetalLayer, updateHandler: @escaping UpdateHandler) {
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
