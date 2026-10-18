import AppKit

/// User defaults keys. Names match the original SizeUp where a counterpart exists.
enum PrefKey {
    static let menuEnabled = "MenuEnabled"
    static let showPrefsOnLaunch = "ShowPrefsOnLaunch"
    static let showOverlay = "ShowOverlay"
    static let shortcutsDisabled = "ShortcutsDisabled"
    static let moveFirstResizeSecond = "MoveOnFirstTrigger"
    static let cycleWindowSizes = "CycleWindowSizes"
    static let keepWindowsInBounds = "KeepWindowsInBounds"
    static let centerNonResizableWindows = "CenterNonResizableWindows"
    static let multiMonitorProportional = "MultiMonitorResizeWindowProportionally"
    static let centerResizeEnabled = "CenterResizeEnabled"
    static let centerResizeType = "CenterResizeType" // 0 = absolute, 1 = relative
    static let centerResizeWidth = "CenterResizeWidth"
    static let centerResizeHeight = "CenterResizeHeight"
    static let centerRelativeWidth = "CenterRelativeResizeWidth"
    static let centerRelativeHeight = "CenterRelativeResizeHeight"
    static let screenEdgeMarginsEnabled = "ScreenEdgeMarginsEnabled"
    static let marginUp = "MarginUp"
    static let marginDown = "MarginDown"
    static let marginLeft = "MarginLeft"
    static let marginRight = "MarginRight"
    static let partitionMarginsEnabled = "PartitionMarginsEnabled"
    static let marginHorizontal = "MarginHorizontal"
    static let marginVertical = "MarginVertical"
    static let splitHorizontal = "SplitScreenHorizontal" // percent
    static let splitVertical = "SplitScreenVertical"
    static let quarterHorizontal = "QuarterScreenHorizontal"
    static let quarterVertical = "QuarterScreenVertical"
    static let disabledApplications = "DisabledApplications" // [bundle id]
    static let windowsMoved = "WindowsMoved"
    static let importedFromSizeUp = "ImportedFromSizeUp"
}

@MainActor
enum Prefs {
    static let defaults = UserDefaults.standard
    static let originalDomain = "com.irradiatedsoftware.SizeUp"

    static func registerDefaults() {
        var d: [String: Any] = [
            PrefKey.menuEnabled: true,
            PrefKey.showPrefsOnLaunch: false,
            PrefKey.showOverlay: true,
            PrefKey.shortcutsDisabled: false,
            PrefKey.moveFirstResizeSecond: false,
            PrefKey.cycleWindowSizes: false,
            PrefKey.keepWindowsInBounds: true,
            PrefKey.centerNonResizableWindows: true,
            PrefKey.multiMonitorProportional: true,
            PrefKey.centerResizeEnabled: true,
            PrefKey.centerResizeType: 1,
            PrefKey.centerResizeWidth: 1024.0,
            PrefKey.centerResizeHeight: 768.0,
            PrefKey.centerRelativeWidth: 75.0,
            PrefKey.centerRelativeHeight: 75.0,
            PrefKey.screenEdgeMarginsEnabled: false,
            PrefKey.marginUp: 0.0, PrefKey.marginDown: 0.0, PrefKey.marginLeft: 0.0, PrefKey.marginRight: 0.0,
            PrefKey.partitionMarginsEnabled: false,
            PrefKey.marginHorizontal: 0.0, PrefKey.marginVertical: 0.0,
            PrefKey.splitHorizontal: 50.0, PrefKey.splitVertical: 50.0,
            PrefKey.quarterHorizontal: 50.0, PrefKey.quarterVertical: 50.0,
            PrefKey.disabledApplications: [String](),
            PrefKey.windowsMoved: 0,
        ]
        for action in Action.allCases {
            d[action.rawValue] = action.defaultShortcut?.dictionary ?? Shortcut.emptyDictionary
            d[action.menuKey] = action.isClassic
        }
        defaults.register(defaults: d)
    }

    // MARK: Accessors

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func double(_ key: String) -> Double { defaults.double(forKey: key) }
    static func set(_ value: Any?, _ key: String) { defaults.set(value, forKey: key) }

    static func shortcut(for action: Action) -> Shortcut? {
        (defaults.dictionary(forKey: action.rawValue)).flatMap(Shortcut.init(dictionary:))
    }

    /// Assigns a shortcut, removing it from any other action that already uses it.
    static func setShortcut(_ shortcut: Shortcut?, for action: Action) {
        if let shortcut {
            for other in Action.allCases where other != action && self.shortcut(for: other) == shortcut {
                defaults.set(Shortcut.emptyDictionary, forKey: other.rawValue)
            }
        }
        defaults.set(shortcut?.dictionary ?? Shortcut.emptyDictionary, forKey: action.rawValue)
    }

    static func showsInMenu(_ action: Action) -> Bool { bool(action.menuKey) }

    static var disabledApplications: [String] {
        get { defaults.stringArray(forKey: PrefKey.disabledApplications) ?? [] }
        set { defaults.set(newValue, forKey: PrefKey.disabledApplications) }
    }

    static func isDisabled(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return disabledApplications.contains(bundleID)
    }

    static var windowsMoved: Int { defaults.integer(forKey: PrefKey.windowsMoved) }
    /// SizeUp's estimate: each action saves about 3 seconds of manual dragging.
    static var minutesSaved: Int { windowsMoved * 3 / 60 }

    static func recordWindowMoved() {
        defaults.set(windowsMoved + 1, forKey: PrefKey.windowsMoved)
    }

    // MARK: Import from the original SizeUp

    static var originalSettingsAvailable: Bool {
        defaults.persistentDomain(forName: originalDomain) != nil
    }

    static func importFromSizeUpIfNeeded() {
        guard !bool(PrefKey.importedFromSizeUp) else { return }
        importFromSizeUp()
        set(true, PrefKey.importedFromSizeUp)
    }

    /// Copies shortcuts, margins, partitions and options from SizeUp's preferences.
    @discardableResult
    static func importFromSizeUp() -> Bool {
        guard let src = defaults.persistentDomain(forName: originalDomain) else { return false }

        for action in Action.allCases {
            if let combo = src[action.rawValue] as? [String: Any], combo["ComboCode"] != nil {
                let s = Shortcut(dictionary: combo)
                defaults.set(s?.dictionary ?? Shortcut.emptyDictionary, forKey: action.rawValue)
            }
            if let shown = src[action.menuKey] as? NSNumber { set(shown.boolValue, action.menuKey) }
        }

        let boolKeys = [PrefKey.menuEnabled, PrefKey.showPrefsOnLaunch, PrefKey.showOverlay, PrefKey.shortcutsDisabled,
                        PrefKey.cycleWindowSizes, PrefKey.keepWindowsInBounds, PrefKey.centerNonResizableWindows,
                        PrefKey.multiMonitorProportional, PrefKey.centerResizeEnabled,
                        PrefKey.screenEdgeMarginsEnabled, PrefKey.partitionMarginsEnabled]
        for key in boolKeys { if let v = src[key] as? NSNumber { set(v.boolValue, key) } }

        let numberKeys = [PrefKey.centerResizeType, PrefKey.centerResizeWidth, PrefKey.centerResizeHeight,
                          PrefKey.centerRelativeWidth, PrefKey.centerRelativeHeight,
                          PrefKey.marginUp, PrefKey.marginDown, PrefKey.marginLeft, PrefKey.marginRight,
                          PrefKey.marginHorizontal, PrefKey.marginVertical]
        for key in numberKeys { if let v = src[key] as? NSNumber { set(v.doubleValue, key) } }

        // Partitions may have been stored as fractions or percentages.
        for key in [PrefKey.splitHorizontal, PrefKey.splitVertical, PrefKey.quarterHorizontal, PrefKey.quarterVertical] {
            if let v = (src[key] as? NSNumber)?.doubleValue {
                set(v <= 1 ? v * 100 : v, key)
            }
        }

        if let moved = (src[PrefKey.windowsMoved] as? NSNumber)?.intValue, moved > windowsMoved {
            set(moved, PrefKey.windowsMoved)
        }
        if let apps = src[PrefKey.disabledApplications] as? [String] {
            disabledApplications = Array(Set(disabledApplications + apps)).sorted()
        }
        return true
    }
}
