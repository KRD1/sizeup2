# SizeUp2

Native Apple silicon version of the original [SizeUp](https://www.irradiatedsoftware.com/sizeup/), the
keyboard-driven window manager for macOS.

SizeUp 1.7.4 was last built for Intel (i386/x86_64) and needs Rosetta on Apple silicon Macs.
SizeUp2 is a from-scratch Swift rewrite of its features. It builds as a universal binary
(arm64 + x86_64) and needs no third-party dependencies.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (Swift 5.10+) to build

## Build and install

```sh
git clone https://github.com/KRD1/sizeup2.git
cd sizeup2
Scripts/build.sh            # builds build/SizeUp2.app
Scripts/build.sh --install  # also copies it to /Applications (quits a running copy first)
```

Then:

1. Quit the original SizeUp if it is running. Both apps use the same shortcuts.
2. Open **SizeUp2**. It lives in the menu bar.
3. Turn on SizeUp2 under **System Settings › Privacy & Security › Accessibility**. Settings › General
   turns green once access has been granted.

### Signing and Accessibility permission

`build.sh` signs the app ad hoc, with a designated requirement tied to the bundle identifier
(`local.sizeup2.SizeUp2`). macOS ties Accessibility permission to that requirement, so the
permission survives rebuilds. To sign with your own certificate, run:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/build.sh
```

If the toggle shows as on but SizeUp2 still says it needs access, reset the permission and grant it again:

```sh
tccutil reset Accessibility local.sizeup2.SizeUp2
```

## Importing settings from SizeUp

On first launch, SizeUp2 copies your shortcuts, margins, partitions, options and statistics from the
original SizeUp (`com.irradiatedsoftware.SizeUp`). You can run the import again at any time from
**Settings › General › Import Settings**.

## Features

| Feature | Notes |
|---|---|
| Split screen: Left, Right, Up, Down | Default ⌃⌥⌘ + arrow keys |
| Quarter screen: Upper/Lower Left/Right | Default ⌃⌥⇧ + arrow keys |
| Full Screen, Center | Center can resize to an absolute size or a percentage of the screen |
| Next / Previous Monitor | Optional proportional resize |
| SnapBack | Restores the window's previous position and size. Press again to toggle back. |
| Thirds and move-without-resizing actions | AppleScript-only in SizeUp. SizeUp2 lets you bind them to shortcuts too. |
| Send window to next / previous Space | Best effort, see [Spaces](#spaces) |
| Screen edge margins and partition (between-window) margins | |
| Adjustable split and quarter partitions | Live preview in Settings |
| Move on first trigger, resize on second | |
| Cycle sizes (½ → ⅔ → ⅓) on repeated Left/Right/Up/Down | |
| Keep windows in bounds and center windows that can't resize | |
| Menu bar menu | Show or hide each action. The icon itself can be hidden; reopen the app to get Settings. |
| Disable shortcuts globally or per application | |
| Visual action overlay | |
| Launch at login | Uses `SMAppService` |
| Statistics | Windows moved and minutes saved |
| AppleScript | See below |

Not carried over: Space Above/Below (it only worked on Mac OS X 10.5/10.6), speakable actions,
licensing, and Sparkle updates.

### Spaces

macOS has no public API for moving a window to another Space. Like the original, SizeUp2 holds the
window by its title bar and sends **⌃←** / **⌃→** (or **⌃1…⌃9** for `send to space`). Turn those
shortcuts on in **System Settings › Keyboard › Keyboard Shortcuts › Mission Control**. Recent versions
of macOS don't always respect this trick.

## AppleScript

```applescript
tell application "SizeUp2"
    do action Left
    do action Upper Right on monitor 2
    do action Third Center
    send to monitor 2
    send to space 3
    move to {100, 50}
    resize to {1280, 800}
    move and resize to {0, 0, 1200, 800}
    fit to grid {0, 0, 4, 6} grid size {6, 6}
    set enabled to false -- turn keyboard shortcuts off
end tell
```

Coordinates are relative to the top-left corner of the monitor's usable area (excluding the menu bar,
the Dock and any screen edge margins). Monitor indices are 1-based, and 1 is the main display.

## Project layout

```
Package.swift                 Swift package (single executable target)
Resources/Info.plist          App bundle metadata (LSUIElement menu bar app)
Resources/SizeUp2.sdef        AppleScript dictionary
Scripts/build.sh              Builds, bundles, signs (and optionally installs) the app
Scripts/make_icon.swift       Generates the app icon
Sources/SizeUp2/
  main.swift                  Entry point
  AppDelegate.swift           Menu bar item and menu, app lifecycle
  Action.swift                All actions, default shortcuts, AppleScript codes
  WindowManager.swift         Window geometry, SnapBack, monitors (Accessibility API)
  SpaceMover.swift            Moving windows between Spaces
  Accessibility.swift         AXUIElement helpers and coordinate conversion
  HotKeyManager.swift         Global shortcuts (Carbon hot keys)
  Shortcut.swift              Key combinations and key names
  Prefs.swift                 Defaults, plus import from the original SizeUp
  PreferencesView.swift       Settings window (SwiftUI)
  ShortcutRecorder.swift      Shortcut recording control
  Overlay.swift               Visual action overlay
  Scripting.swift             AppleScript command handling
```

## Acknowledgements

SizeUp was created by [Irradiated Software](https://www.irradiatedsoftware.com/). SizeUp2 is an
independent re-implementation and is not affiliated with or endorsed by Irradiated Software. It
contains no code or assets from the original app.

## License

[MIT](LICENSE)
