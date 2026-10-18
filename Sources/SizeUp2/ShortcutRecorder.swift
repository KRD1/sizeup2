import AppKit
import SwiftUI

/// Click to record a key combination. Esc cancels, Delete clears.
final class ShortcutRecorderView: NSView {
    var shortcut: Shortcut? { didSet { needsDisplay = true } }
    var onChange: ((Shortcut?) -> Void)?
    var failed = false { didSet { needsDisplay = true } }

    private var recording = false {
        didSet {
            needsDisplay = true
            MainActor.assumeIsolated { HotKeyManager.shared.suspended = recording }
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 22) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        let mods = event.modifierFlags.intersection(Shortcut.relevantModifiers)
        switch event.keyCode {
        case KeyCode.escape where mods.isEmpty:
            window?.makeFirstResponder(nil)
        case KeyCode.delete where mods.isEmpty, KeyCode.forwardDelete where mods.isEmpty:
            shortcut = nil
            onChange?(nil)
            window?.makeFirstResponder(nil)
        default:
            let candidate = Shortcut(keyCode: event.keyCode, modifiers: mods)
            guard candidate.isValid else { NSSound.beep(); return }
            shortcut = candidate
            onChange?(candidate)
            window?.makeFirstResponder(nil)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        let color: NSColor
        if recording {
            text = "Type shortcut…"; color = .secondaryLabelColor
        } else if let shortcut {
            text = shortcut.displayString; color = failed ? .systemRed : .labelColor
        } else {
            text = "Click to record"; color = .tertiaryLabelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: shortcut != nil && !recording ? .medium : .regular),
            .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: Shortcut?
    var failed: Bool
    var onChange: (Shortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let v = ShortcutRecorderView()
        v.setContentHuggingPriority(.required, for: .vertical)
        return v
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.failed = failed
        view.onChange = onChange
        view.toolTip = failed ? "This shortcut is already in use by another application or the system." : nil
    }
}
