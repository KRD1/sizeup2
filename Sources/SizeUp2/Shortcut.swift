import AppKit
import Carbon.HIToolbox

enum KeyCode {
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
}

/// A key combination. Stored in user defaults as {ComboCode, ComboFlags} using Cocoa
/// modifier flags, the same format the original SizeUp used.
struct Shortcut: Hashable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    init?(dictionary: [String: Any]) {
        guard let code = (dictionary["ComboCode"] as? NSNumber)?.intValue, code >= 0, code < 0xFFFF else { return nil }
        let flags = (dictionary["ComboFlags"] as? NSNumber)?.uintValue ?? 0
        self.init(keyCode: UInt16(code), modifiers: NSEvent.ModifierFlags(rawValue: flags))
    }

    static let emptyDictionary: [String: Any] = ["ComboCode": -1, "ComboFlags": 0]

    var dictionary: [String: Any] {
        ["ComboCode": Int(keyCode), "ComboFlags": Int(modifiers.rawValue)]
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var modifierSymbols: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s
    }

    var displayString: String { modifierSymbols + Self.keyName(for: keyCode) }

    /// Whether a combination is acceptable as a global shortcut.
    var isValid: Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty || Self.functionKeys[keyCode] != nil
    }

    /// Key equivalent for NSMenuItem so the menu shows the shortcut.
    var menuKeyEquivalent: String? {
        let scalar: Int?
        switch keyCode {
        case KeyCode.leftArrow: scalar = NSLeftArrowFunctionKey
        case KeyCode.rightArrow: scalar = NSRightArrowFunctionKey
        case KeyCode.upArrow: scalar = NSUpArrowFunctionKey
        case KeyCode.downArrow: scalar = NSDownArrowFunctionKey
        default:
            if let f = Self.functionKeys[keyCode] { scalar = NSF1FunctionKey + f - 1 }
            else if let named = Self.namedKeys[keyCode] {
                switch named {
                case "Space": return " "
                case "↩": return "\r"
                case "⇥": return "\t"
                default: return nil
                }
            } else {
                return Self.character(for: keyCode)?.lowercased()
            }
        }
        return scalar.flatMap { UnicodeScalar($0) }.map { String(Character($0)) }
    }

    // MARK: - Key names

    static let functionKeys: [UInt16: Int] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10,
        103: 11, 111: 12, 105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20,
    ]

    static let namedKeys: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 76: "⌤", 48: "⇥", 49: "Space",
        51: "⌫", 117: "⌦", 53: "⎋", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 71: "⌧",
    ]

    static let keypadKeys: [UInt16: String] = [
        65: ".", 67: "*", 69: "+", 75: "/", 78: "-", 81: "=",
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
    ]

    static func keyName(for keyCode: UInt16) -> String {
        if let n = namedKeys[keyCode] { return n }
        if let f = functionKeys[keyCode] { return "F\(f)" }
        if let k = keypadKeys[keyCode] { return "Pad \(k)" }
        return character(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// Character produced by a key code in the current keyboard layout.
    static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let s = String(utf16CodeUnits: chars, count: length)
            return s.trimmingCharacters(in: .controlCharacters).isEmpty ? nil : s
        }
    }
}
