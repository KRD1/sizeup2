// Renders AppIcon.iconset (run via build.sh). Usage: swift make_icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.55, blue: 1.0, alpha: 1),
                        NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.75, alpha: 1)])!.draw(in: bg, angle: -90)

    // A "screen" split into two windows with a third in the corner.
    let screen = body.insetBy(dx: body.width * 0.16, dy: body.height * 0.2)
    let gap = s * 0.025
    let r = screen.width * 0.06
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: NSRect(x: screen.minX, y: screen.minY, width: screen.width / 2 - gap / 2, height: screen.height),
                 xRadius: r, yRadius: r).fill()
    NSColor.white.withAlphaComponent(0.7).setFill()
    NSBezierPath(roundedRect: NSRect(x: screen.midX + gap / 2, y: screen.midY + gap / 2,
                                     width: screen.width / 2 - gap / 2, height: screen.height / 2 - gap / 2),
                 xRadius: r, yRadius: r).fill()
    NSColor.white.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: NSRect(x: screen.midX + gap / 2, y: screen.minY,
                                     width: screen.width / 2 - gap / 2, height: screen.height / 2 - gap / 2),
                 xRadius: r, yRadius: r).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
