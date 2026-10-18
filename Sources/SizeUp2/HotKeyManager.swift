import AppKit
import Carbon.HIToolbox

/// Registers global shortcuts with the Carbon hot key API (no Accessibility permission needed
/// for the key handling itself; it is only needed to move windows).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// True while a shortcut recorder is capturing keys, so existing shortcuts don't fire.
    var suspended = false { didSet { sync() } }

    private var registered: [Action: (Shortcut, EventHotKeyRef)] = [:]
    private var actionsByID: [UInt32: Action] = [:]
    private var handler: EventHandlerRef?
    private(set) var failed: Set<Action> = []

    func install() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            MainActor.assumeIsolated { HotKeyManager.shared.fire(id: hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, &handler)
        for (i, action) in Action.allCases.enumerated() { actionsByID[UInt32(i + 1)] = action }
        sync()
    }

    private func fire(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        WindowManager.shared.perform(action)
    }

    /// Brings registrations in line with preferences and the frontmost application.
    func sync() {
        var desired: [Action: Shortcut] = [:]
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if !suspended, !Prefs.bool(PrefKey.shortcutsDisabled), !Prefs.isDisabled(bundleID: frontmost) {
            for action in Action.allCases {
                if let s = Prefs.shortcut(for: action) { desired[action] = s }
            }
        }

        for (action, (shortcut, ref)) in registered where desired[action] != shortcut {
            UnregisterEventHotKey(ref)
            registered[action] = nil
        }
        failed = failed.filter { desired[$0] != nil && registered[$0] == nil }

        for (action, shortcut) in desired where registered[action] == nil {
            guard let id = actionsByID.first(where: { $0.value == action })?.key else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                             EventHotKeyID(signature: OSType(0x537A5570 /* SzUp */), id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[action] = (shortcut, ref)
                failed.remove(action)
            } else {
                failed.insert(action)
                NSLog("SizeUp2: could not register %@ for %@ (%d)", shortcut.displayString, action.rawValue, status)
            }
        }
    }
}
