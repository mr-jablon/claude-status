// Renders Resources/AppIcon.icns: a gauge on a warm gradient tile.
// Usage: swift scripts/make-icon.swift   (needs iconutil, part of macOS)
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: tile is 824/1024 of the canvas, centered.
    let tile = CGRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.2237, yRadius: tile.width * 0.2237)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill(); path.fill()
    ctx.restoreGState()
    path.addClip()
    NSGradient(colors: [NSColor(red: 0.93, green: 0.55, blue: 0.38, alpha: 1),
                        NSColor(red: 0.74, green: 0.31, blue: 0.20, alpha: 1)])!.draw(in: tile, angle: -90)

    // Gauge: 270° arc, open at the bottom, filled to ~70 %.
    let c = CGPoint(x: s / 2, y: s * 0.49)
    let r = tile.width * 0.30
    let w = tile.width * 0.105
    let start: CGFloat = 225, sweep: CGFloat = 270
    func arc(_ frac: CGFloat, _ color: NSColor) {
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: r, startAngle: start, endAngle: start - sweep * frac, clockwise: true)
        p.lineWidth = w; p.lineCapStyle = .round
        color.setStroke(); p.stroke()
    }
    arc(1, NSColor.white.withAlphaComponent(0.28))
    arc(0.7, NSColor(red: 1, green: 0.97, blue: 0.93, alpha: 1))

    // Needle pointing at the end of the filled arc.
    let a = (start - sweep * 0.7) * .pi / 180
    let tip = CGPoint(x: c.x + cos(a) * r * 0.72, y: c.y + sin(a) * r * 0.72)
    let needle = NSBezierPath()
    needle.move(to: c); needle.line(to: tip)
    needle.lineWidth = w * 0.55; needle.lineCapStyle = .round
    NSColor(red: 1, green: 0.97, blue: 0.93, alpha: 1).setStroke(); needle.stroke()
    NSColor(red: 1, green: 0.97, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: c.x - w * 0.55, y: c.y - w * 0.55, width: w * 1.1, height: w * 1.1)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run(); p.waitUntilExit()
print("Wrote \(out.path)")
