import AppKit

/// The "Visual Action Overlay": a short-lived HUD showing which action ran.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private let panel: NSPanel
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 160),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let effect = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        imageView.symbolConfiguration = .init(pointSize: 64, weight: .regular)
        imageView.contentTintColor = .labelColor
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: effect.leadingAnchor, constant: 12),
        ])
    }

    func show(_ action: Action, on screen: NSScreen?) {
        imageView.image = action.image
        label.stringValue = action.title
        let screen = screen ?? NSScreen.main
        if let s = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: s.midX - panel.frame.width / 2, y: s.midY - panel.frame.height / 2))
        }
        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    if self.panel.alphaValue == 0 { self.panel.orderOut(nil) }
                }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
