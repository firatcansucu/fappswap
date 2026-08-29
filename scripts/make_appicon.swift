#!/usr/bin/env swift
// Regenerates Resources/fappswap.icns from the approved design.
// The numbers here are the spec: change one here and in make_brand.swift together, or not at all.
//   swift scripts/make_appicon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
let icns = root.appendingPathComponent("Resources/fappswap.icns")

let sizes = [16, 32, 64, 128, 256, 512, 1024]
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(px: Int) -> NSBitmapImageRep {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Tile: 22.37% corner radius (Apple's icon grid).
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                 xRadius: s * 0.2237, yRadius: s * 0.2237).addClip()

    // Field: #FFFFFF -> #F0EFF2 (52%) -> #DCDAE0, 165deg.
    NSGradient(colors: [NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                        NSColor(srgbRed: 0.941, green: 0.937, blue: 0.949, alpha: 1),
                        NSColor(srgbRed: 0.863, green: 0.855, blue: 0.878, alpha: 1)],
               atLocations: [0, 0.52, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -75)

    // Top sheen: white 75% -> clear at 46% of the height.
    NSGradient(colors: [NSColor(white: 1, alpha: 0.75), NSColor(white: 1, alpha: 0)],
               atLocations: [0, 0.46], colorSpace: .sRGB)!
        .draw(in: NSRect(x: 0, y: s * 0.54, width: s, height: s * 0.46), angle: -90)

    // Glyph: U+2325 OPTION KEY, SF Pro Display Medium, 104/180 of the tile.
    let font = NSFont.systemFont(ofSize: s * (104.0 / 180.0), weight: .medium)
    func drawGlyph(_ color: NSColor) {
        let str = NSAttributedString(string: "\u{2325}",
                                     attributes: [.font: font, .foregroundColor: color])
        let sz = str.size()
        str.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2))
    }
    drawGlyph(NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1))   // #1C1C1E

    // Accent: the same glyph clipped to the top 38% — the stub and the floating
    // rail. Clipped, not redrawn, so the two layers stay in register at any size.
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: 0, y: s * 0.62, width: s, height: s * 0.38)).addClip()
    drawGlyph(NSColor(srgbRed: 1.0, green: 0.584, blue: 0.0, alpha: 1))       // #FF9500
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) throws {
    try rep.representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent(name))
}

for px in sizes {
    let rep = drawIcon(px: px)
    if px == 1024 {
        try write(rep, "icon_512x512@2x.png")
    } else {
        try write(rep, "icon_\(px)x\(px).png")
        try write(drawIcon(px: px * 2), "icon_\(px)x\(px)@2x.png")
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("wrote \(icns.path)")
