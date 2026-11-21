// Renders LocalFlow's app icon (violet→cyan squircle with a white waveform) to an .iconset, then iconutil builds the .icns.
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = s * 0.098, r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    // drop shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    let path = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
    NSColor.black.setFill(); path.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    path.addClip()
    let g = NSGradient(colors: [NSColor(red: 0.42, green: 0.30, blue: 0.96, alpha: 1),
                                NSColor(red: 0.36, green: 0.45, blue: 0.99, alpha: 1),
                                NSColor(red: 0.16, green: 0.78, blue: 1.0, alpha: 1)])!
    g.draw(in: r, angle: -55)
    // soft top highlight
    let hl = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    hl.draw(in: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), angle: -90)
    // waveform bars
    let heights: [CGFloat] = [0.20, 0.38, 0.62, 0.42, 0.74, 0.50, 0.30, 0.18]
    let barW = r.width * 0.062, gap = r.width * 0.045
    let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    var x = r.midX - total / 2
    NSColor.white.setFill()
    for h in heights {
        let bh = r.height * h
        NSBezierPath(roundedRect: NSRect(x: x, y: r.midY - bh / 2, width: barW, height: bh), xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
