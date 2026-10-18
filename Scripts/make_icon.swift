// Renders the SizeUp2 app icon.
// Usage: swift make_icon.swift <output.iconset> [logo.png]
import AppKit

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws a window tile: gradient fill, glossy top highlight, title bar with traffic lights.
func drawTile(_ ctx: CGContext, _ rect: CGRect, _ top: UInt32, _ bottom: UInt32, unit u: CGFloat, lights: Bool) {
    let radius = u * 3.2
    let path = roundedPath(rect, radius)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -u * 1.2), blur: u * 4, color: color(0x000000, 0.45))
    ctx.addPath(path)
    ctx.setFillColor(color(bottom))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(top), color(bottom)]),
                           start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // Title bar band
    let bar = CGRect(x: rect.minX, y: rect.maxY - u * 6.5, width: rect.width, height: u * 6.5)
    ctx.setFillColor(color(0xFFFFFF, 0.22))
    ctx.fill(bar)
    // Gloss on the upper half
    ctx.drawLinearGradient(gradient([color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)]),
                           start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    ctx.restoreGState()

    if lights {
        let d = u * 2.2
        for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            let cx = rect.minX + u * 4 + CGFloat(i) * u * 3.4
            ctx.setFillColor(color(UInt32(c)))
            ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: bar.midY - d / 2, width: d, height: d))
        }
    }

    // Hairline rim
    ctx.addPath(roundedPath(rect.insetBy(dx: u * 0.25, dy: u * 0.25), radius - u * 0.25))
    ctx.setStrokeColor(color(0xFFFFFF, 0.35))
    ctx.setLineWidth(u * 0.5)
    ctx.strokePath()
}

/// A bold diagonal double-headed arrow (↙↗) — the "size up" gesture.
func drawResizeArrow(_ ctx: CGContext, in rect: CGRect, unit u: CGFloat) {
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let half = min(rect.width, rect.height) * 0.30
    let a = CGPoint(x: c.x - half, y: c.y - half), b = CGPoint(x: c.x + half, y: c.y + half)
    let head = u * 5.2

    let path = CGMutablePath()
    path.move(to: CGPoint(x: a.x + head * 0.55, y: a.y + head * 0.55))
    path.addLine(to: CGPoint(x: b.x - head * 0.55, y: b.y - head * 0.55))
    let heads = CGMutablePath()
    heads.addLines(between: [b, CGPoint(x: b.x - head, y: b.y), CGPoint(x: b.x, y: b.y - head)])
    heads.closeSubpath()
    heads.addLines(between: [a, CGPoint(x: a.x + head, y: a.y), CGPoint(x: a.x, y: a.y + head)])
    heads.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -u * 0.6), blur: u * 2, color: color(0x0B1E6B, 0.55))
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(u * 2.6)
    ctx.setLineCap(.round)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.setFillColor(color(0xFFFFFF))
    ctx.setLineJoin(.round)
    ctx.setLineWidth(u * 1.2)
    ctx.addPath(heads)
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let u = s / 100 // design unit: the canvas is 100×100

    // Squircle body, following the macOS icon grid (824/1024 with a soft shadow).
    let body = CGRect(x: u * 9.8, y: u * 10.8, width: u * 80.4, height: u * 80.4)
    let bodyPath = roundedPath(body, u * 18)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -u * 1), blur: u * 3, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x1B1446))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    // Deep indigo → violet background with a glow behind the tiles.
    ctx.drawLinearGradient(gradient([color(0x3A1C8C), color(0x1A1250), color(0x0B0B2A)], [0, 0.55, 1]),
                           start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    ctx.drawRadialGradient(gradient([color(0x7B5CFF, 0.55), color(0x7B5CFF, 0)]),
                           startCenter: CGPoint(x: body.midX, y: body.midY + u * 4), startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.midY + u * 4), endRadius: u * 46, options: [])
    // Subtle grid lines (the "snap" grid)
    ctx.setStrokeColor(color(0xFFFFFF, 0.06))
    ctx.setLineWidth(u * 0.35)
    for i in 1..<6 {
        let x = body.minX + body.width * CGFloat(i) / 6, y = body.minY + body.height * CGFloat(i) / 6
        ctx.move(to: CGPoint(x: x, y: body.minY)); ctx.addLine(to: CGPoint(x: x, y: body.maxY))
        ctx.move(to: CGPoint(x: body.minX, y: y)); ctx.addLine(to: CGPoint(x: body.maxX, y: y))
    }
    ctx.strokePath()
    // Top sheen
    ctx.drawLinearGradient(gradient([color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)]),
                           start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.midY + u * 10), options: [])
    ctx.restoreGState()

    // Window tiles snapped into a split layout.
    let area = body.insetBy(dx: u * 12, dy: u * 13)
    let gap = u * 3
    let leftW = (area.width - gap) * 0.54
    let rightX = area.minX + leftW + gap
    let rightW = area.maxX - rightX
    let halfH = (area.height - gap) / 2

    let main = CGRect(x: area.minX, y: area.minY, width: leftW, height: area.height)
    drawTile(ctx, main, 0x3EE0FF, 0x2563EB, unit: u, lights: true)
    drawResizeArrow(ctx, in: CGRect(x: main.minX, y: main.minY, width: main.width, height: main.height - u * 6.5), unit: u)
    drawTile(ctx, CGRect(x: rightX, y: area.minY + halfH + gap, width: rightW, height: halfH),
             0xFF7AD9, 0xA21CAF, unit: u, lights: px >= 64)
    drawTile(ctx, CGRect(x: rightX, y: area.minY, width: rightW, height: halfH),
             0xFFD25A, 0xF97316, unit: u, lights: px >= 64)

    // Body rim highlight
    ctx.addPath(roundedPath(body.insetBy(dx: u * 0.3, dy: u * 0.3), u * 17.7))
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(u * 0.6)
    ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if args.count > 2 {
    try render(512).write(to: URL(fileURLWithPath: args[2]))
}
