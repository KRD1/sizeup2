import AppKit
import ApplicationServices

/// Performs SizeUp actions on the focused window of the frontmost application.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private struct SnapBackEntry { let window: AXUIElement; var frame: CGRect }
    private struct LastAction { let window: AXUIElement; let action: Action; let frame: CGRect; let step: Int }

    private var snapBackEntries: [SnapBackEntry] = []
    private var lastAction: LastAction?
    private var promptedForAccess = false

    // MARK: - Public entry points

    func perform(_ action: Action, monitorIndex: Int? = nil) {
        guard let target = focusedWindow() else { return }
        let (app, window) = target

        switch action {
        case .spaceNext: moveToSpace(window, keyCode: KeyCode.rightArrow, action: action)
        case .spacePrev: moveToSpace(window, keyCode: KeyCode.leftArrow, action: action)
        case .snapBack: performSnapBack(app: app, window: window)
        default: performLayout(action, app: app, window: window, monitorIndex: monitorIndex)
        }
    }

    /// Moves/resizes the front window to a rect relative to a monitor's usable area.
    /// Any nil component keeps the window's current value.
    func place(x: CGFloat?, y: CGFloat?, width: CGFloat?, height: CGFloat?, monitorIndex: Int?) {
        guard let (app, window) = focusedWindow(), let current = window.frame else { return }
        let screen = monitorIndex.flatMap(ScreenGeometry.screen(index:)) ?? ScreenGeometry.screen(containing: current)
        guard let screen else { return }
        let area = usableArea(of: screen)
        let currentScreenArea = usableArea(of: ScreenGeometry.screen(containing: current) ?? screen)
        let rect = CGRect(x: x.map { area.minX + $0 } ?? (area.minX + current.minX - currentScreenArea.minX),
                          y: y.map { area.minY + $0 } ?? (area.minY + current.minY - currentScreenArea.minY),
                          width: width ?? current.width,
                          height: height ?? current.height)
        rememberForSnapBack(window, frame: current)
        let final = apply(rect, to: window, app: app, bounds: area)
        finish(nil, window: window, frame: final, step: 0)
    }

    func fitToGrid(_ cell: CGRect, columns: Int, rows: Int, monitorIndex: Int?) {
        guard let (app, window) = focusedWindow(), let current = window.frame else { return }
        let screen = monitorIndex.flatMap(ScreenGeometry.screen(index:)) ?? ScreenGeometry.screen(containing: current)
        guard let screen, columns > 0, rows > 0 else { return }
        let area = usableArea(of: screen)
        let rect = region(in: area,
                          x0: cell.minX / CGFloat(columns), x1: cell.maxX / CGFloat(columns),
                          y0: cell.minY / CGFloat(rows), y1: cell.maxY / CGFloat(rows))
        rememberForSnapBack(window, frame: current)
        let final = apply(rect, to: window, app: app, bounds: area)
        finish(nil, window: window, frame: final, step: 0)
    }

    func sendToMonitor(_ index: Int) {
        guard let (app, window) = focusedWindow(), let current = window.frame,
              let from = ScreenGeometry.screen(containing: current),
              let dest = ScreenGeometry.screen(index: index) else { NSSound.beep(); return }
        guard dest != from else { return }
        rememberForSnapBack(window, frame: current)
        let final = apply(monitorTarget(for: current, from: from, to: dest), to: window, app: app, bounds: usableArea(of: dest))
        finish(.nextMonitor, window: window, frame: final, step: 0)
    }

    func sendToSpace(_ number: Int) {
        guard (1...9).contains(number), let (_, window) = focusedWindow() else { NSSound.beep(); return }
        let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        moveToSpace(window, keyCode: digitKeys[number - 1], action: nil)
    }

    // MARK: - Window lookup

    private func focusedWindow() -> (NSRunningApplication, AXUIElement)? {
        guard AccessibilityPermission.isTrusted else {
            // Prompt once per launch; after that just beep instead of nagging.
            if !promptedForAccess { promptedForAccess = true; AccessibilityPermission.request() } else { NSSound.beep() }
            return nil
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { NSSound.beep(); return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
        guard let window = appElement.element(kAXFocusedWindowAttribute) ?? appElement.element(kAXMainWindowAttribute) else {
            NSSound.beep()
            return nil
        }
        if window.boolValue("AXFullScreen") == true { NSSound.beep(); return nil }
        return (app, window)
    }

    // MARK: - Layout actions

    private func performLayout(_ action: Action, app: NSRunningApplication, window: AXUIElement, monitorIndex: Int?) {
        guard let current = window.frame,
              let currentScreen = ScreenGeometry.screen(containing: current) else { NSSound.beep(); return }
        let screen = monitorIndex.flatMap(ScreenGeometry.screen(index:)) ?? currentScreen
        let area = usableArea(of: screen)

        let repeated: Bool = {
            guard let last = lastAction, last.action == action, CFEqual(last.window, window) else { return false }
            return last.frame.isApproximately(current)
        }()

        var step = 0
        var target: CGRect

        switch action {
        case .nextMonitor, .prevMonitor:
            guard let t = monitorTarget(for: current, from: currentScreen, next: action == .nextMonitor) else {
                NSSound.beep(); return
            }
            target = t.rect
            rememberForSnapBack(window, frame: current)
            let final = apply(target, to: window, app: app, bounds: usableArea(of: t.screen))
            finish(action, window: window, frame: final, step: 0)
            return

        case .center:
            target = centerTarget(for: current, in: area)

        case .moveLeft, .moveRight, .moveUp, .moveDown,
             .moveUpperLeft, .moveUpperRight, .moveLowerLeft, .moveLowerRight, .moveCenter:
            target = moveTarget(action, current: current, area: area)

        default:
            // Region actions (halves, quarters, thirds, full screen), with optional size cycling.
            if Prefs.bool(PrefKey.cycleWindowSizes), repeated, let last = lastAction,
               [.left, .right, .up, .down].contains(action) {
                step = last.step + 1
            }
            target = regionTarget(action, in: area, cycleStep: step)
        }

        // "Move on first trigger, resize on second."
        let supportsMoveFirst = [.split, .quarter, .other, .thirds].contains(action.group)
        if Prefs.bool(PrefKey.moveFirstResizeSecond), supportsMoveFirst, !repeated {
            target = moveOnly(current: current, toward: target, area: area, centered: action == .fullScreen || action == .center)
            step = -1
        }

        rememberForSnapBack(window, frame: current)
        let final = apply(target, to: window, app: app, bounds: area)
        finish(action, window: window, frame: final, step: step)
    }

    private func finish(_ action: Action?, window: AXUIElement, frame: CGRect, step: Int) {
        lastAction = action.map { LastAction(window: window, action: $0, frame: frame, step: step) }
        Prefs.recordWindowMoved()
        if let action, Prefs.bool(PrefKey.showOverlay) {
            OverlayController.shared.show(action, on: ScreenGeometry.screen(containing: frame))
        }
    }

    /// The visible area of a screen (minus menu bar and Dock) inset by the screen edge margins.
    func usableArea(of screen: NSScreen) -> CGRect {
        var r = ScreenGeometry.visibleFrame(of: screen)
        if Prefs.bool(PrefKey.screenEdgeMarginsEnabled) {
            let top = Prefs.double(PrefKey.marginUp), bottom = Prefs.double(PrefKey.marginDown)
            let left = Prefs.double(PrefKey.marginLeft), right = Prefs.double(PrefKey.marginRight)
            r = CGRect(x: r.minX + left, y: r.minY + top,
                       width: max(100, r.width - left - right), height: max(100, r.height - top - bottom))
        }
        return r
    }

    /// A fractional region of `area`, honoring partition (between window) margins on interior edges.
    private func region(in area: CGRect, x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat) -> CGRect {
        let partitions = Prefs.bool(PrefKey.partitionMarginsEnabled)
        let gapX = partitions ? Prefs.double(PrefKey.marginHorizontal) / 2 : 0
        let gapY = partitions ? Prefs.double(PrefKey.marginVertical) / 2 : 0
        let minX = area.minX + area.width * x0 + (x0 > 0.001 ? gapX : 0)
        let maxX = area.minX + area.width * x1 - (x1 < 0.999 ? gapX : 0)
        let minY = area.minY + area.height * y0 + (y0 > 0.001 ? gapY : 0)
        let maxY = area.minY + area.height * y1 - (y1 < 0.999 ? gapY : 0)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    private func regionTarget(_ action: Action, in area: CGRect, cycleStep: Int) -> CGRect {
        let sh = Prefs.double(PrefKey.splitHorizontal) / 100
        let sv = Prefs.double(PrefKey.splitVertical) / 100
        let qh = Prefs.double(PrefKey.quarterHorizontal) / 100
        let qv = Prefs.double(PrefKey.quarterVertical) / 100

        // Cycling sequence for split actions: partition → 2/3 → 1/3.
        func cycled(_ base: CGFloat) -> CGFloat { [base, 2.0 / 3.0, 1.0 / 3.0][cycleStep % 3] }

        switch action {
        case .left: return region(in: area, x0: 0, x1: cycled(sh), y0: 0, y1: 1)
        case .right: return region(in: area, x0: cycleStep == 0 ? sh : 1 - cycled(1 - sh), x1: 1, y0: 0, y1: 1)
        case .up: return region(in: area, x0: 0, x1: 1, y0: 0, y1: cycled(sv))
        case .down: return region(in: area, x0: 0, x1: 1, y0: cycleStep == 0 ? sv : 1 - cycled(1 - sv), y1: 1)
        case .upperLeft: return region(in: area, x0: 0, x1: qh, y0: 0, y1: qv)
        case .upperRight: return region(in: area, x0: qh, x1: 1, y0: 0, y1: qv)
        case .lowerLeft: return region(in: area, x0: 0, x1: qh, y0: qv, y1: 1)
        case .lowerRight: return region(in: area, x0: qh, x1: 1, y0: qv, y1: 1)
        case .thirdLeft: return region(in: area, x0: 0, x1: 1.0 / 3, y0: 0, y1: 1)
        case .thirdCenter: return region(in: area, x0: 1.0 / 3, x1: 2.0 / 3, y0: 0, y1: 1)
        case .thirdRight: return region(in: area, x0: 2.0 / 3, x1: 1, y0: 0, y1: 1)
        case .thirdUpper: return region(in: area, x0: 0, x1: 1, y0: 0, y1: 1.0 / 3)
        case .thirdMiddle: return region(in: area, x0: 0, x1: 1, y0: 1.0 / 3, y1: 2.0 / 3)
        case .thirdLower: return region(in: area, x0: 0, x1: 1, y0: 2.0 / 3, y1: 1)
        default: return area // Full Screen
        }
    }

    private func centerTarget(for current: CGRect, in area: CGRect) -> CGRect {
        var size = current.size
        if Prefs.bool(PrefKey.centerResizeEnabled) {
            if Prefs.defaults.integer(forKey: PrefKey.centerResizeType) == 0 {
                size = CGSize(width: Prefs.double(PrefKey.centerResizeWidth), height: Prefs.double(PrefKey.centerResizeHeight))
            } else {
                size = CGSize(width: area.width * Prefs.double(PrefKey.centerRelativeWidth) / 100,
                              height: area.height * Prefs.double(PrefKey.centerRelativeHeight) / 100)
            }
        }
        size = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                      width: size.width, height: size.height).integral
    }

    private func moveTarget(_ action: Action, current: CGRect, area: CGRect) -> CGRect {
        var r = current
        switch action {
        case .moveLeft: r.origin.x = area.minX
        case .moveRight: r.origin.x = area.maxX - r.width
        case .moveUp: r.origin.y = area.minY
        case .moveDown: r.origin.y = area.maxY - r.height
        case .moveUpperLeft: r.origin = CGPoint(x: area.minX, y: area.minY)
        case .moveUpperRight: r.origin = CGPoint(x: area.maxX - r.width, y: area.minY)
        case .moveLowerLeft: r.origin = CGPoint(x: area.minX, y: area.maxY - r.height)
        case .moveLowerRight: r.origin = CGPoint(x: area.maxX - r.width, y: area.maxY - r.height)
        default: r.origin = CGPoint(x: area.midX - r.width / 2, y: area.midY - r.height / 2)
        }
        return r.clamped(to: area).integral
    }

    /// Keeps the window's size but aligns it with the edges of `target`.
    private func moveOnly(current: CGRect, toward target: CGRect, area: CGRect, centered: Bool) -> CGRect {
        var r = current
        func align(_ tMin: CGFloat, _ tMax: CGFloat, _ aMin: CGFloat, _ aMax: CGFloat, _ cur: CGFloat, _ len: CGFloat) -> CGFloat {
            let touchesMin = abs(tMin - aMin) < 1, touchesMax = abs(tMax - aMax) < 1
            if centered { return (tMin + tMax) / 2 - len / 2 }
            if touchesMin && touchesMax { return cur }
            if touchesMin { return tMin }
            if touchesMax { return tMax - len }
            return (tMin + tMax) / 2 - len / 2
        }
        r.origin.x = align(target.minX, target.maxX, area.minX, area.maxX, current.minX, current.width)
        r.origin.y = align(target.minY, target.maxY, area.minY, area.maxY, current.minY, current.height)
        return r.clamped(to: area).integral
    }

    private func monitorTarget(for current: CGRect, from screen: NSScreen, next: Bool) -> (rect: CGRect, screen: NSScreen)? {
        let screens = ScreenGeometry.spatiallyOrdered
        guard screens.count > 1, let i = screens.firstIndex(of: screen) else { return nil }
        let dest = screens[(i + (next ? 1 : -1) + screens.count) % screens.count]
        return (monitorTarget(for: current, from: screen, to: dest), dest)
    }

    /// Maps a window frame from one screen to another, proportionally or preserving size.
    private func monitorTarget(for current: CGRect, from screen: NSScreen, to dest: NSScreen) -> CGRect {
        let from = usableArea(of: screen), to = usableArea(of: dest)

        if Prefs.bool(PrefKey.multiMonitorProportional) {
            let rx = (current.minX - from.minX) / from.width, ry = (current.minY - from.minY) / from.height
            let rw = current.width / from.width, rh = current.height / from.height
            let r = CGRect(x: to.minX + rx * to.width, y: to.minY + ry * to.height,
                           width: rw * to.width, height: rh * to.height)
            return r.clamped(to: to).integral
        }
        let size = CGSize(width: min(current.width, to.width), height: min(current.height, to.height))
        let freeFrom = CGSize(width: max(1, from.width - current.width), height: max(1, from.height - current.height))
        let px = min(max((current.minX - from.minX) / freeFrom.width, 0), 1)
        let py = min(max((current.minY - from.minY) / freeFrom.height, 0), 1)
        let r = CGRect(x: to.minX + px * (to.width - size.width), y: to.minY + py * (to.height - size.height),
                       width: size.width, height: size.height)
        return r.integral
    }

    // MARK: - SnapBack

    private func rememberForSnapBack(_ window: AXUIElement, frame: CGRect) {
        if let i = snapBackEntries.firstIndex(where: { CFEqual($0.window, window) }) {
            snapBackEntries[i].frame = frame
        } else {
            snapBackEntries.append(SnapBackEntry(window: window, frame: frame))
            if snapBackEntries.count > 100 { snapBackEntries.removeFirst() }
        }
    }

    private func performSnapBack(app: NSRunningApplication, window: AXUIElement) {
        guard let i = snapBackEntries.firstIndex(where: { CFEqual($0.window, window) }),
              let current = window.frame else { NSSound.beep(); return }
        let previous = snapBackEntries[i].frame
        // Store the current frame so pressing SnapBack again toggles between the two states.
        snapBackEntries[i].frame = current
        let final = apply(previous, to: window, app: app, bounds: nil)
        finish(.snapBack, window: window, frame: final, step: 0)
    }

    // MARK: - Applying frames

    @discardableResult
    private func apply(_ target: CGRect, to window: AXUIElement, app: NSRunningApplication, bounds: CGRect?) -> CGRect {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Apps with AXEnhancedUserInterface enabled (e.g. when VoiceOver-style clients are active)
        // animate frame changes and often end up in the wrong place; disable it temporarily.
        let enhanced = appElement.boolValue("AXEnhancedUserInterface") == true
        if enhanced { appElement.setBool("AXEnhancedUserInterface", false) }
        defer { if enhanced { appElement.setBool("AXEnhancedUserInterface", true) } }

        // Size → position → size so moves across displays of different sizes work reliably.
        window.setSize(target.size)
        window.setPosition(target.origin)
        window.setSize(target.size)

        guard var actual = window.frame else { return target }
        var adjusted = actual

        if Prefs.bool(PrefKey.centerNonResizableWindows),
           abs(actual.width - target.width) > 30 || abs(actual.height - target.height) > 30 {
            adjusted.origin = CGPoint(x: target.midX - actual.width / 2, y: target.midY - actual.height / 2)
        }
        if Prefs.bool(PrefKey.keepWindowsInBounds), let bounds {
            adjusted = adjusted.clamped(to: bounds)
        }
        adjusted = adjusted.integral
        if adjusted.origin != actual.origin {
            window.setPosition(adjusted.origin)
            actual = window.frame ?? adjusted
        }
        return actual
    }

    // MARK: - Spaces

    private func moveToSpace(_ window: AXUIElement, keyCode: UInt16, action: Action?) {
        guard let frame = window.frame else { NSSound.beep(); return }
        SpaceMover.move(window: window, frame: frame, keyCode: keyCode)
        Prefs.recordWindowMoved()
        if let action, Prefs.bool(PrefKey.showOverlay) {
            OverlayController.shared.show(action, on: ScreenGeometry.screen(containing: frame))
        }
    }
}

extension CGRect {
    /// Shifts the rect so it lies within `bounds` (top-left aligned if it is larger).
    func clamped(to bounds: CGRect) -> CGRect {
        var r = self
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        return r
    }

    func isApproximately(_ other: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
