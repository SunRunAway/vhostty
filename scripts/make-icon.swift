// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.13, blue: 0.36, alpha: 1),
                        NSColor(red: 0.07, green: 0.06, blue: 0.12, alpha: 1)])!.draw(in: path, angle: -90)
    let w = rect.width
    let accent = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    // Vertical tab strip on the left; the second tab is selected.
    let tabW = w * 0.2, tabH = w * 0.11, gap = w * 0.05
    let tabX = rect.minX + w * 0.11
    let stackH = 4 * tabH + 3 * gap
    for i in 0..<4 {
        let y = rect.midY + stackH / 2 - tabH - CGFloat(i) * (tabH + gap)
        let tab = NSBezierPath(roundedRect: NSRect(x: tabX, y: y, width: tabW, height: tabH),
                               xRadius: tabH * 0.3, yRadius: tabH * 0.3)
        (i == 1 ? accent : NSColor(white: 1, alpha: 0.16)).setFill()
        tab.fill()
    }
    // Soft glow behind the ghost
    let ghostCenter = NSPoint(x: rect.minX + w * 0.64, y: rect.midY)
    let glowR = w * 0.3
    let glow = NSBezierPath(ovalIn: NSRect(x: ghostCenter.x - glowR, y: ghostCenter.y - glowR, width: 2 * glowR, height: 2 * glowR))
    NSGradient(colors: [accent.withAlphaComponent(0.45), .clear])!
        .draw(in: glow, relativeCenterPosition: .zero)
    let ghost = NSAttributedString(string: "👻", attributes: [.font: NSFont.systemFont(ofSize: w * 0.4)])
    let g = ghost.size()
    ghost.draw(at: NSPoint(x: ghostCenter.x - g.width / 2, y: ghostCenter.y - g.height / 2 - w * 0.02))
    let spark = NSAttributedString(string: "✳", attributes: [
        .font: NSFont.systemFont(ofSize: rect.width * 0.2, weight: .bold),
        .foregroundColor: NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)])
    spark.draw(at: NSPoint(x: rect.maxX - rect.width * 0.3, y: rect.maxY - rect.width * 0.32))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
print(iconset.path)
