import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt asking the user to grant Accessibility access.
    @discardableResult
    static func request() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func element(_ name: String) -> AXUIElement? {
        guard let v = attribute(name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    var position: CGPoint? {
        guard let v = attribute(kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    var size: CGSize? {
        guard let v = attribute(kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    /// Frame in global "flipped" coordinates (origin at the top-left of the primary display).
    var frame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, v) }
    }

    func setSize(_ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, v) }
    }

    var boolValue: (String) -> Bool? {
        { name in (self.attribute(name) as? NSNumber)?.boolValue }
    }

    func setBool(_ name: String, _ value: Bool) {
        AXUIElementSetAttributeValue(self, name as CFString, value as CFBoolean)
    }
}

/// Converts between AppKit screen coordinates (bottom-left origin) and the flipped
/// coordinates used by the Accessibility API.
@MainActor
enum ScreenGeometry {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func flipped(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func frame(of screen: NSScreen) -> CGRect { flipped(screen.frame) }
    static func visibleFrame(of screen: NSScreen) -> CGRect { flipped(screen.visibleFrame) }

    /// Screen containing the largest part of `rect` (flipped coordinates).
    static func screen(containing rect: CGRect) -> NSScreen? {
        var best: (NSScreen, CGFloat)?
        for s in NSScreen.screens {
            let i = frame(of: s).intersection(rect)
            let area = i.isNull ? 0 : i.width * i.height
            if area > (best?.1 ?? 0) { best = (s, area) }
        }
        if let best { return best.0 }
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { frame(of: $0).contains(mid) } ?? NSScreen.main
    }

    /// Screens ordered left-to-right, then top-to-bottom (used for Next/Prev Monitor).
    static var spatiallyOrdered: [NSScreen] {
        NSScreen.screens.sorted {
            let a = frame(of: $0), b = frame(of: $1)
            return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
        }
    }

    /// 1-based index as used by AppleScript (1 = main display with the menu bar).
    static func screen(index: Int) -> NSScreen? {
        let screens = NSScreen.screens
        return (1...screens.count).contains(index) ? screens[index - 1] : nil
    }
}
