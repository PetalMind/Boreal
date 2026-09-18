import AppKit
import Metal
import QuartzCore

@MainActor
final class FrameGenerationOverlayWindow {
    private let panel: NSPanel
    private let metalView: FrameGenerationMetalView

    init(frame: CGRect, pixelWidth: Int, pixelHeight: Int) throws {
        metalView = FrameGenerationMetalView(frame: .zero)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = metalView
        updateGeometry(frame: frame, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    var metalLayer: CAMetalLayer { metalView.metalLayer }

    func show() {
        panel.orderFrontRegardless()
    }

    func updateGeometry(frame: CGRect, pixelWidth: Int, pixelHeight: Int) {
        panel.setFrame(frame, display: false)
        metalView.frame = metalView.superview?.bounds ?? CGRect(origin: .zero, size: frame.size)
        metalView.metalLayer.drawableSize = CGSize(width: max(1, pixelWidth), height: max(1, pixelHeight))
        metalView.metalLayer.contentsScale = panel.backingScaleFactor
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
    private let layer: CAMetalLayer
    private let commandQueue: MTLCommandQueue

    init(layer: CAMetalLayer, commandQueue: MTLCommandQueue) {
        self.layer = layer
        self.commandQueue = commandQueue
    }

    func present(texture: MTLTexture, completion: @escaping @Sendable () -> Void) {
        guard let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            completion()
            return
        }
        commandBuffer.addCompletedHandler { _ in completion() }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            commandBuffer.commit()
            return
        }
        blit.copy(from: texture, to: drawable.texture)
        blit.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
