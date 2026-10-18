import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var preferences: PreferencesWindowController?
    private var observers: [NSObjectProtocol] = []

    /// Exposed to AppleScript as the application's `enabled` property.
    @objc var enabled: Bool {
        get { !Prefs.bool(PrefKey.shortcutsDisabled) }
        set { Prefs.set(!newValue, PrefKey.shortcutsDisabled) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        Prefs.importFromSizeUpIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "SizeUp2")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        statusItem.menu = menu

        HotKeyManager.shared.install()
        refresh()

        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HotKeyManager.shared.sync() }
        })

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.request()
            showPreferences(nil)
        } else if Prefs.bool(PrefKey.showPrefsOnLaunch) {
            showPreferences(nil)
        }
    }

    /// When the menu bar icon is hidden, launching the app again (e.g. from Finder) opens Preferences.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences(nil)
        return false
    }

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        key == "enabled"
    }

    private func refresh() {
        statusItem?.isVisible = Prefs.bool(PrefKey.menuEnabled)
        HotKeyManager.shared.sync()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let disabled = Prefs.bool(PrefKey.shortcutsDisabled)

        var previousGroup: Action.Group?
        for action in Action.allCases where Prefs.showsInMenu(action) {
            if let previousGroup, previousGroup != action.group { menu.addItem(.separator()) }
            previousGroup = action.group
            let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            let image = action.image.copy() as! NSImage
            image.size = NSSize(width: 16, height: 16)
            item.image = image
            if let s = Prefs.shortcut(for: action), let key = s.menuKeyEquivalent {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = s.modifiers
            }
            menu.addItem(item)
        }
        if previousGroup != nil { menu.addItem(.separator()) }

        let toggle = NSMenuItem(title: "Disable Shortcuts", action: #selector(toggleShortcuts(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.state = disabled ? .on : .off
        menu.addItem(toggle)

        if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let name = app.localizedName ?? id
            let item = NSMenuItem(title: "Disable Shortcuts in \(name)", action: #selector(toggleApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = Prefs.isDisabled(bundleID: id) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let about = NSMenuItem(title: "About SizeUp2", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SizeUp2", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = Action(rawValue: raw) else { return }
        // Let the menu close and focus return to the target app first.
        DispatchQueue.main.async { WindowManager.shared.perform(action) }
    }

    @objc private func toggleShortcuts(_ sender: NSMenuItem) {
        Prefs.set(!Prefs.bool(PrefKey.shortcutsDisabled), PrefKey.shortcutsDisabled)
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var list = Prefs.disabledApplications
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.append(id) }
        Prefs.disabledApplications = list
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferences == nil { preferences = PreferencesWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        preferences?.showWindow(nil)
        preferences?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Keyboard-driven window sizing for macOS.\nA native Apple silicon re-implementation of SizeUp.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }
}
