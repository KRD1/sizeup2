import AppKit

/// Handles every command in SizeUp2.sdef (the `<cocoa class="SizeUpCommand"/>` entries).
@objc(SizeUpCommand)
final class SizeUpCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated { run() }
    }

    @MainActor
    private func run() -> Any? {
        let args = evaluatedArguments ?? [:]
        let monitor = (args["monitor"] as? NSNumber)?.intValue
        let wm = WindowManager.shared

        switch commandDescription.commandName {
        case "do action":
            guard let action = resolveAction(directParameter) else {
                return fail("Unknown action.")
            }
            wm.perform(action, monitorIndex: monitor)

        case "send to monitor":
            guard let index = (directParameter as? NSNumber)?.intValue, ScreenGeometry.screen(index: index) != nil else {
                return fail("Invalid monitor index.")
            }
            wm.sendToMonitor(index)

        case "send to space":
            guard let n = (directParameter as? NSNumber)?.intValue else { return fail("Invalid space number.") }
            wm.sendToSpace(n)

        case "move to":
            let v = numbers(directParameter)
            guard v.count >= 2 else { return fail("Expected {x, y}.") }
            wm.place(x: v[0], y: v[1], width: nil, height: nil, monitorIndex: monitor)

        case "resize to":
            let v = numbers(directParameter)
            guard v.count >= 2 else { return fail("Expected {width, height}.") }
            wm.place(x: nil, y: nil, width: v[0], height: v[1], monitorIndex: monitor)

        case "move and resize to":
            let v = numbers(directParameter)
            guard v.count >= 4 else { return fail("Expected {x, y, width, height}.") }
            wm.place(x: v[0], y: v[1], width: v[2], height: v[3], monitorIndex: monitor)

        case "fit to grid":
            let v = numbers(directParameter)
            guard v.count >= 4 else { return fail("Expected {x, y, width, height} in grid cells.") }
            let grid = numbers(args["gridSize"])
            wm.fitToGrid(CGRect(x: v[0], y: v[1], width: v[2], height: v[3]),
                         columns: Int(grid.first ?? 6), rows: Int(grid.count > 1 ? grid[1] : 6),
                         monitorIndex: monitor)

        case "show menu":
            (NSApp.delegate as? AppDelegate)?.showMenu()

        default:
            return fail("Unsupported command.")
        }
        return nil
    }

    private func resolveAction(_ value: Any?) -> Action? {
        if let s = value as? String { return Action(rawValue: s) }
        if let n = value as? NSNumber { return Action(scriptCode: n.uint32Value) }
        if let d = value as? NSAppleEventDescriptor { return Action(scriptCode: d.enumCodeValue) }
        return nil
    }

    private func numbers(_ value: Any?) -> [CGFloat] {
        if let a = value as? [Any] { return a.compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } } }
        if let n = value as? NSNumber { return [CGFloat(n.doubleValue)] }
        return []
    }

    private func fail(_ message: String) -> Any? {
        scriptErrorNumber = -1708
        scriptErrorString = message
        return nil
    }
}
