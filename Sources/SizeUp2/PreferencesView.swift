import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "SizeUp2 Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

/// Republishes whenever user defaults change so views that read `Prefs` directly stay current.
@MainActor
final class DefaultsObserver: ObservableObject {
    private var token: NSObjectProtocol?
    init() {
        token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }
}

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsPane().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            MarginsPane().tabItem { Label("Margins", systemImage: "rectangle.dashed") }
            PartitionsPane().tabItem { Label("Partitions", systemImage: "rectangle.split.2x2") }
            AdvancedPane().tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 620, height: 560)
    }
}

// MARK: - General

struct GeneralPane: View {
    @StateObject private var observer = DefaultsObserver()
    @AppStorage(PrefKey.menuEnabled) private var menuEnabled = true
    @AppStorage(PrefKey.showOverlay) private var showOverlay = true
    @AppStorage(PrefKey.showPrefsOnLaunch) private var showPrefsOnLaunch = false
    @AppStorage(PrefKey.shortcutsDisabled) private var shortcutsDisabled = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AccessibilityPermission.isTrusted
    @State private var importMessage: String?
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trusted ? "Accessibility access granted" : "Accessibility access required")
                        if !trusted {
                            Text("SizeUp2 needs permission to move and resize other apps' windows.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !trusted {
                        Button("Open System Settings") {
                            AccessibilityPermission.request()
                            AccessibilityPermission.openSettings()
                        }
                    }
                }
            }
            Section {
                Toggle("Start SizeUp2 automatically at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enable in
                        do {
                            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("SizeUp2: launch at login change failed: \(error)")
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Toggle("Show SizeUp2 in menu bar", isOn: $menuEnabled)
                if !menuEnabled {
                    Text("With the menu bar icon hidden, open SizeUp2 again from Finder to get back to Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Show visual action overlay", isOn: $showOverlay)
                Toggle("Show Settings on launch", isOn: $showPrefsOnLaunch)
                Toggle("Disable all keyboard shortcuts", isOn: $shortcutsDisabled)
            }
            Section("Statistics") {
                LabeledContent("Number of windows moved", value: Prefs.windowsMoved.formatted())
                LabeledContent("Minutes saved with SizeUp2", value: Prefs.minutesSaved.formatted())
            }
            Section("Original SizeUp") {
                HStack {
                    Text(Prefs.originalSettingsAvailable
                         ? "Copy shortcuts, margins and options from SizeUp's preferences."
                         : "No SizeUp preferences were found on this Mac.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Import Settings") {
                        importMessage = Prefs.importFromSizeUp() ? "Imported." : "Nothing to import."
                    }
                    .disabled(!Prefs.originalSettingsAvailable)
                }
                if let importMessage { Text(importMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = AccessibilityPermission.isTrusted }
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @StateObject private var observer = DefaultsObserver()

    var body: some View {
        Form {
            Section {
                Text("Shortcuts perform an action on the frontmost window in any application. Click the eye to show or hide the action in the menu bar menu. Press Delete while recording to clear a shortcut.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Action.Group.allCases, id: \.self) { group in
                Section {
                    ForEach(group.actions) { action in ShortcutRow(action: action) }
                } header: {
                    Text(group.rawValue)
                } footer: {
                    Text(group.blurb).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    let action: Action

    var body: some View {
        let shown = Prefs.showsInMenu(action)
        let shortcut = Prefs.shortcut(for: action)
        HStack(spacing: 10) {
            Button {
                Prefs.set(!shown, action.menuKey)
            } label: {
                Image(systemName: shown ? "eye" : "eye.slash")
                    .foregroundStyle(shown ? Color.accentColor : .secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(shown ? "Shown in menu" : "Hidden from menu")

            Image(nsImage: action.image)
                .frame(width: 22)
            Text(action.title)
            Spacer()
            ShortcutRecorder(shortcut: shortcut, failed: HotKeyManager.shared.failed.contains(action)) {
                Prefs.setShortcut($0, for: action)
            }
            .frame(width: 150, height: 22)
            Button {
                Prefs.setShortcut(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(shortcut == nil ? 0 : 1)
            .help("Clear shortcut")
        }
    }
}

// MARK: - Margins

struct MarginsPane: View {
    @AppStorage(PrefKey.screenEdgeMarginsEnabled) private var edgeEnabled = false
    @AppStorage(PrefKey.marginUp) private var up = 0.0
    @AppStorage(PrefKey.marginDown) private var down = 0.0
    @AppStorage(PrefKey.marginLeft) private var left = 0.0
    @AppStorage(PrefKey.marginRight) private var right = 0.0
    @AppStorage(PrefKey.partitionMarginsEnabled) private var partitionEnabled = false
    @AppStorage(PrefKey.marginHorizontal) private var horizontal = 0.0
    @AppStorage(PrefKey.marginVertical) private var vertical = 0.0

    var body: some View {
        Form {
            Section {
                Toggle("Screen edge margins", isOn: $edgeEnabled)
                Group {
                    PixelField(title: "Top", value: $up)
                    PixelField(title: "Bottom", value: $down)
                    PixelField(title: "Left", value: $left)
                    PixelField(title: "Right", value: $right)
                }
                .disabled(!edgeEnabled)
            } footer: {
                Text("Reserve space on the edges of your screen (in pixels).").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Partition (between window) margins", isOn: $partitionEnabled)
                Group {
                    PixelField(title: "Horizontal gap", value: $horizontal)
                    PixelField(title: "Vertical gap", value: $vertical)
                }
                .disabled(!partitionEnabled)
            } footer: {
                Text("Reserve space between windows for Split Screen, Quarter Screen and Thirds actions (in pixels).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preview") {
                LayoutPreview().frame(height: 150)
            }
        }
        .formStyle(.grouped)
    }
}

struct PixelField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Stepper("", value: $value, in: 0...500, step: 1).labelsHidden()
                Text("px").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Partitions

struct PartitionsPane: View {
    @AppStorage(PrefKey.splitHorizontal) private var splitH = 50.0
    @AppStorage(PrefKey.splitVertical) private var splitV = 50.0
    @AppStorage(PrefKey.quarterHorizontal) private var quarterH = 50.0
    @AppStorage(PrefKey.quarterVertical) private var quarterV = 50.0

    var body: some View {
        Form {
            Section {
                PercentSlider(title: "Left / Right split", value: $splitH)
                PercentSlider(title: "Up / Down split", value: $splitV)
            } header: {
                Text("Split Screen Partitions")
            } footer: {
                Text("Where the Left and Right actions, and the Up and Down actions, divide the screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                PercentSlider(title: "Horizontal split", value: $quarterH)
                PercentSlider(title: "Vertical split", value: $quarterV)
            } header: {
                Text("Quarter Screen Partitions")
            } footer: {
                Text("Where the Upper/Lower Left and Upper/Lower Right actions divide the screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preview") {
                LayoutPreview(showQuarters: true).frame(height: 150)
            }
            Section {
                Button("Reset to 50%") { splitH = 50; splitV = 50; quarterH = 50; quarterV = 50 }
            }
        }
        .formStyle(.grouped)
    }
}

struct PercentSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: 10...90, step: 1).frame(width: 260)
                Text("\(Int(value))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        }
    }
}

/// A small diagram of the screen showing partitions and margins.
struct LayoutPreview: View {
    var showQuarters = false
    @StateObject private var observer = DefaultsObserver()

    var body: some View {
        Canvas { ctx, size in
            let screen = CGRect(x: 0, y: 0, width: size.height * 16 / 10, height: size.height)
                .offsetBy(dx: (size.width - size.height * 16 / 10) / 2, dy: 0)
            ctx.fill(Path(roundedRect: screen, cornerRadius: 6), with: .color(.secondary.opacity(0.15)))
            let scale = screen.width / 1600
            var area = screen
            if Prefs.bool(PrefKey.screenEdgeMarginsEnabled) {
                area = CGRect(x: screen.minX + Prefs.double(PrefKey.marginLeft) * scale,
                              y: screen.minY + Prefs.double(PrefKey.marginUp) * scale,
                              width: screen.width - (Prefs.double(PrefKey.marginLeft) + Prefs.double(PrefKey.marginRight)) * scale,
                              height: screen.height - (Prefs.double(PrefKey.marginUp) + Prefs.double(PrefKey.marginDown)) * scale)
            }
            let gapX = Prefs.bool(PrefKey.partitionMarginsEnabled) ? Prefs.double(PrefKey.marginHorizontal) * scale / 2 : 0
            let gapY = Prefs.bool(PrefKey.partitionMarginsEnabled) ? Prefs.double(PrefKey.marginVertical) * scale / 2 : 0
            let fx = (showQuarters ? Prefs.double(PrefKey.quarterHorizontal) : Prefs.double(PrefKey.splitHorizontal)) / 100
            let fy = (showQuarters ? Prefs.double(PrefKey.quarterVertical) : 1)
            let splitX = area.minX + area.width * fx
            let splitY = showQuarters ? area.minY + area.height * fy / 100 : area.maxY

            let rects: [CGRect] = showQuarters ? [
                CGRect(x: area.minX, y: area.minY, width: splitX - gapX - area.minX, height: splitY - gapY - area.minY),
                CGRect(x: splitX + gapX, y: area.minY, width: area.maxX - splitX - gapX, height: splitY - gapY - area.minY),
                CGRect(x: area.minX, y: splitY + gapY, width: splitX - gapX - area.minX, height: area.maxY - splitY - gapY),
                CGRect(x: splitX + gapX, y: splitY + gapY, width: area.maxX - splitX - gapX, height: area.maxY - splitY - gapY),
            ] : [
                CGRect(x: area.minX, y: area.minY, width: splitX - gapX - area.minX, height: area.height),
                CGRect(x: splitX + gapX, y: area.minY, width: area.maxX - splitX - gapX, height: area.height),
            ]
            for r in rects where r.width > 0 && r.height > 0 {
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(.accentColor.opacity(0.35)))
                ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(.accentColor), lineWidth: 1)
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @AppStorage(PrefKey.moveFirstResizeSecond) private var moveFirst = false
    @AppStorage(PrefKey.cycleWindowSizes) private var cycle = false
    @AppStorage(PrefKey.keepWindowsInBounds) private var keepInBounds = true
    @AppStorage(PrefKey.centerNonResizableWindows) private var centerNonResizable = true
    @AppStorage(PrefKey.multiMonitorProportional) private var proportional = true
    @AppStorage(PrefKey.centerResizeEnabled) private var centerResize = true
    @AppStorage(PrefKey.centerResizeType) private var centerType = 1
    @AppStorage(PrefKey.centerResizeWidth) private var centerWidth = 1024.0
    @AppStorage(PrefKey.centerResizeHeight) private var centerHeight = 768.0
    @AppStorage(PrefKey.centerRelativeWidth) private var centerRelW = 75.0
    @AppStorage(PrefKey.centerRelativeHeight) private var centerRelH = 75.0
    @StateObject private var observer = DefaultsObserver()
    @State private var selectedApp: String?

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Move on first trigger, resize on second", isOn: $moveFirst)
                    .help("The first time an action is triggered the window is only moved; trigger it again to resize.")
                Toggle("Cycle sizes on repeated Left/Right/Up/Down (½ → ⅔ → ⅓)", isOn: $cycle)
                Toggle("Try to keep windows in bounds", isOn: $keepInBounds)
                    .help("If a window can't be resized to fit, shift it so it stays on screen (and inside margins).")
                Toggle("Center windows that don't resize fully", isOn: $centerNonResizable)
                    .help("Non-resizable windows and windows with size limits are centered in the chosen area.")
                Toggle("Resize windows proportionally when moving between monitors", isOn: $proportional)
            }
            Section("Center Action") {
                Toggle("Resize window when centering", isOn: $centerResize)
                Picker("Size", selection: $centerType) {
                    Text("Relative to screen size").tag(1)
                    Text("Absolute size").tag(0)
                }
                .pickerStyle(.radioGroup)
                .disabled(!centerResize)
                if centerType == 1 {
                    PercentSlider(title: "Width", value: $centerRelW).disabled(!centerResize)
                    PercentSlider(title: "Height", value: $centerRelH).disabled(!centerResize)
                } else {
                    PixelField(title: "Width", value: $centerWidth).disabled(!centerResize)
                    PixelField(title: "Height", value: $centerHeight).disabled(!centerResize)
                }
            }
            Section {
                List(selection: $selectedApp) {
                    ForEach(Prefs.disabledApplications, id: \.self) { id in
                        AppRow(bundleID: id).tag(id)
                    }
                }
                .frame(minHeight: 90)
                HStack {
                    Menu("Add Running App") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "") { add(app.bundleIdentifier) }
                        }
                    }
                    .fixedSize()
                    Button("Choose…") { chooseApp() }
                    Button("Remove") {
                        Prefs.disabledApplications.removeAll { $0 == selectedApp }
                        selectedApp = nil
                    }
                    .disabled(selectedApp == nil)
                }
            } header: {
                Text("Disabled Applications")
            } footer: {
                Text("SizeUp2 shortcuts are turned off while one of these applications is frontmost — useful for apps that use the same shortcuts, or remote control apps like Screen Sharing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ id: String?) {
        guard let id, !Prefs.disabledApplications.contains(id) else { return }
        Prefs.disabledApplications.append(id)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { add(Bundle(url: url)?.bundleIdentifier) }
        }
    }
}

struct AppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
            Spacer()
            Text(bundleID).font(.caption).foregroundStyle(.secondary)
        }
    }
}
