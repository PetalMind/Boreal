import CoreVideo
import Foundation

nonisolated final class FrameGenerationTimingController: @unchecked Sendable {
    private var displayLink: CVDisplayLink?
    private let queue: DispatchQueue
    private let tickHandler: @Sendable () -> Void

    init(displayID: CGDirectDisplayID?, tickHandler: @escaping @Sendable () -> Void) throws {
        self.queue = DispatchQueue(label: "com.boreal.frame-generation.display", qos: .userInteractive)
        self.tickHandler = tickHandler
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else {
            throw FrameGenerationError.overlayCreationFailed
        }
        displayLink = link
        if let displayID {
            CVDisplayLinkSetCurrentCGDisplay(link, displayID)
        }
        let result = CVDisplayLinkSetOutputCallback(link, Self.outputCallback, Unmanaged.passUnretained(self).toOpaque())
        guard result == kCVReturnSuccess else {
            displayLink = nil
            throw FrameGenerationError.overlayCreationFailed
        }
    }

    func start() {
        guard let displayLink else { return }
        CVDisplayLinkStart(displayLink)
    }

    func stop() {
        guard let displayLink, CVDisplayLinkIsRunning(displayLink) else { return }
        CVDisplayLinkStop(displayLink)
    }

    deinit {
        stop()
    }

    private static let outputCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
        guard let userInfo else { return kCVReturnSuccess }
        let controller = Unmanaged<FrameGenerationTimingController>.fromOpaque(userInfo).takeUnretainedValue()
        controller.queue.async(execute: controller.tickHandler)
        return kCVReturnSuccess
    }
}
