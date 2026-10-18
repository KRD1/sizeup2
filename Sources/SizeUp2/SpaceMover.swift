import AppKit
import ApplicationServices

/// macOS has no public API for moving a window between Spaces. Like the original SizeUp,
/// we hold the window by its title bar and trigger the Mission Control "Move left/right a
/// space" (⌃← / ⌃→) or "Switch to Desktop N" (⌃N) shortcut, so the window is carried along.
/// Those shortcuts must be enabled in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.
@MainActor
enum SpaceMover {
    static func move(window: AXUIElement, frame: CGRect, keyCode: UInt16) {
        let grab = grabPoint(for: window, frame: frame)
        let originalMouse = CGEvent(source: nil)?.location ?? grab
        let source = CGEventSource(stateID: .hidSystemState)

        func post(_ type: CGEventType, at point: CGPoint) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }

        post(.mouseMoved, at: grab)
        post(.leftMouseDown, at: grab)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            post(.leftMouseDragged, at: CGPoint(x: grab.x + 1, y: grab.y))
            post(.leftMouseDragged, at: grab)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
                    e?.flags = .maskControl
                    e?.post(tap: .cghidEventTap)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    post(.leftMouseUp, at: grab)
                    CGWarpMouseCursorPosition(originalMouse)
                    CGAssociateMouseAndMouseCursorPosition(1)
                }
            }
        }
    }

    /// An empty spot of the title bar: just right of the traffic-light buttons when available.
    private static func grabPoint(for window: AXUIElement, frame: CGRect) -> CGPoint {
        for attr in [kAXZoomButtonAttribute, kAXFullScreenButtonAttribute, kAXMinimizeButtonAttribute] {
            if let button = window.element(attr as String), let f = button.frame, f.width > 0 {
                return CGPoint(x: f.maxX + 12, y: f.midY)
            }
        }
        return CGPoint(x: frame.minX + 80, y: frame.minY + 12)
    }
}
