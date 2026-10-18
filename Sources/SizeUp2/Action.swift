import AppKit

/// Every window action SizeUp2 can perform. Raw values match the original SizeUp
/// preference keys and AppleScript enumerator names so settings can be imported.
enum Action: String, CaseIterable, Identifiable {
    case left = "Left", right = "Right", up = "Up", down = "Down"
    case upperLeft = "Upper Left", upperRight = "Upper Right"
    case lowerLeft = "Lower Left", lowerRight = "Lower Right"
    case fullScreen = "Full Screen", center = "Center"
    case prevMonitor = "Prev Monitor", nextMonitor = "Next Monitor"
    case snapBack = "SnapBack"
    case spacePrev = "Space Prev", spaceNext = "Space Next"
    case moveLeft = "Move Left", moveRight = "Move Right", moveUp = "Move Up", moveDown = "Move Down"
    case moveUpperLeft = "Move Upper Left", moveUpperRight = "Move Upper Right"
    case moveLowerLeft = "Move Lower Left", moveLowerRight = "Move Lower Right"
    case moveCenter = "Move Center"
    case thirdLeft = "Third Left", thirdCenter = "Third Center", thirdRight = "Third Right"
    case thirdUpper = "Third Upper", thirdMiddle = "Third Middle", thirdLower = "Third Lower"

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case split = "Split Screen"
        case quarter = "Quarter Screen"
        case multiMonitor = "Multiple Monitors"
        case spaces = "Spaces"
        case other = "Other"
        case thirds = "Thirds"
        case move = "Move Without Resizing"

        var actions: [Action] { Action.allCases.filter { $0.group == self } }

        var blurb: String {
            switch self {
            case .split: "Move and resize a window to fill half of the screen."
            case .quarter: "Move and resize a window to fill a quarter of the screen (quadrant)."
            case .multiMonitor: "Move a window from one monitor to another, optionally resizing it proportionally."
            case .spaces: "Move a window from one Space to another (uses the Mission Control keyboard shortcuts)."
            case .other: "Full Screen fills the screen; Center centers (and optionally resizes); SnapBack restores the previous position and size."
            case .thirds: "Move and resize a window to fill a third of the screen."
            case .move: "Move a window to an edge, corner or center without resizing it."
            }
        }
    }

    var group: Group {
        switch self {
        case .left, .right, .up, .down: .split
        case .upperLeft, .upperRight, .lowerLeft, .lowerRight: .quarter
        case .prevMonitor, .nextMonitor: .multiMonitor
        case .spacePrev, .spaceNext: .spaces
        case .fullScreen, .center, .snapBack: .other
        case .thirdLeft, .thirdCenter, .thirdRight, .thirdUpper, .thirdMiddle, .thirdLower: .thirds
        default: .move
        }
    }

    /// Human readable label, e.g. for menus and the overlay.
    var title: String {
        switch self {
        case .prevMonitor: "Previous Monitor"
        case .spacePrev: "Previous Space"
        case .spaceNext: "Next Space"
        default: rawValue
        }
    }

    /// Preference key that controls whether the action is shown in the menu bar menu
    /// (same naming scheme as SizeUp, e.g. "UpperLeftEnabled").
    var menuKey: String { rawValue.replacingOccurrences(of: " ", with: "") + "Enabled" }

    /// The 15 actions the original app exposed in its menu by default.
    var isClassic: Bool { ![.move, .thirds].contains(group) }

    var symbolName: String {
        switch self {
        case .left: "rectangle.lefthalf.filled"
        case .right: "rectangle.righthalf.filled"
        case .up: "rectangle.tophalf.filled"
        case .down: "rectangle.bottomhalf.filled"
        case .upperLeft: "rectangle.inset.topleft.filled"
        case .upperRight: "rectangle.inset.topright.filled"
        case .lowerLeft: "rectangle.inset.bottomleft.filled"
        case .lowerRight: "rectangle.inset.bottomright.filled"
        case .fullScreen: "rectangle.inset.filled"
        case .center: "rectangle.center.inset.filled"
        case .prevMonitor: "arrow.left.square"
        case .nextMonitor: "arrow.right.square"
        case .snapBack: "arrow.uturn.backward.square"
        case .spacePrev: "chevron.left.square"
        case .spaceNext: "chevron.right.square"
        case .moveLeft: "arrow.left.to.line"
        case .moveRight: "arrow.right.to.line"
        case .moveUp: "arrow.up.to.line"
        case .moveDown: "arrow.down.to.line"
        case .moveUpperLeft: "arrow.up.left"
        case .moveUpperRight: "arrow.up.right"
        case .moveLowerLeft: "arrow.down.left"
        case .moveLowerRight: "arrow.down.right"
        case .moveCenter: "dot.square"
        case .thirdLeft, .thirdCenter, .thirdRight: "rectangle.split.3x1"
        case .thirdUpper, .thirdMiddle, .thirdLower: "rectangle.split.1x2"
        }
    }

    var image: NSImage {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: title)!
    }

    /// Four-char AppleScript enumerator code (matches the original sdef).
    var scriptCode: String {
        switch self {
        case .left: "SUlt"; case .right: "SUrt"; case .up: "SUup"; case .down: "SUdn"
        case .upperLeft: "SUul"; case .upperRight: "SUur"; case .lowerLeft: "SUll"; case .lowerRight: "SUlr"
        case .fullScreen: "SUfs"; case .center: "SUcr"
        case .prevMonitor: "SUpm"; case .nextMonitor: "SUnm"; case .snapBack: "SUsb"
        case .spacePrev: "SUsp"; case .spaceNext: "SUnt"
        case .moveLeft: "SAlt"; case .moveRight: "SArt"; case .moveUp: "SAup"; case .moveDown: "SAdn"
        case .moveUpperLeft: "SMul"; case .moveUpperRight: "SMur"
        case .moveLowerLeft: "SMll"; case .moveLowerRight: "SMlr"; case .moveCenter: "SMcr"
        case .thirdLeft: "STlt"; case .thirdCenter: "STcr"; case .thirdRight: "STrt"
        case .thirdUpper: "STup"; case .thirdMiddle: "STmd"; case .thirdLower: "STlw"
        }
    }

    init?(scriptCode code: UInt32) {
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> $0) & 0xFF))) }
        let str = String(chars)
        guard let match = Action.allCases.first(where: { $0.scriptCode == str }) else { return nil }
        self = match
    }

    /// SizeUp's out-of-the-box shortcuts.
    var defaultShortcut: Shortcut? {
        let cao: NSEvent.ModifierFlags = [.control, .option, .command]
        let cas: NSEvent.ModifierFlags = [.control, .option, .shift]
        let co: NSEvent.ModifierFlags = [.control, .option]
        switch self {
        case .left: return Shortcut(keyCode: KeyCode.leftArrow, modifiers: cao)
        case .right: return Shortcut(keyCode: KeyCode.rightArrow, modifiers: cao)
        case .up: return Shortcut(keyCode: KeyCode.upArrow, modifiers: cao)
        case .down: return Shortcut(keyCode: KeyCode.downArrow, modifiers: cao)
        case .upperLeft: return Shortcut(keyCode: KeyCode.leftArrow, modifiers: cas)
        case .upperRight: return Shortcut(keyCode: KeyCode.upArrow, modifiers: cas)
        case .lowerLeft: return Shortcut(keyCode: KeyCode.downArrow, modifiers: cas)
        case .lowerRight: return Shortcut(keyCode: KeyCode.rightArrow, modifiers: cas)
        case .fullScreen: return Shortcut(keyCode: 46 /* M */, modifiers: cao)
        case .center: return Shortcut(keyCode: 8 /* C */, modifiers: cao)
        case .snapBack: return Shortcut(keyCode: 44 /* / */, modifiers: cao)
        case .prevMonitor: return Shortcut(keyCode: KeyCode.leftArrow, modifiers: co)
        case .nextMonitor: return Shortcut(keyCode: KeyCode.rightArrow, modifiers: co)
        default: return nil
        }
    }
}
