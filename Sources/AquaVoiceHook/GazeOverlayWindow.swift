import AppKit

final class GazeOverlayWindow: NSWindow {
    private let circleView = CircleView()

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let size: CGFloat = 120
        circleView.frame = NSRect(
            x: (screen.frame.width - size) / 2,
            y: (screen.frame.height - size) / 2,
            width: size,
            height: size
        )
        circleView.alphaValue = 0

        contentView = NSView(frame: screen.frame)
        contentView?.addSubview(circleView)
    }

    func show() {
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            circleView.animator().alphaValue = 1.0
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            circleView.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

private final class CircleView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.orange.cgColor
        layer?.cornerRadius = bounds.width / 2
    }
}
