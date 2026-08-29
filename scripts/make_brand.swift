#!/usr/bin/env swift
// Regenerates the brand rasters — the wordmark lockups and the GitHub social
// preview — from the same tokens as the app icon. The SVGs next to the output
// call SF Pro by name and so are correct on any Mac; these PNGs exist for
// GitHub and anywhere else a raster is required, and must be rendered here so
// the wordmark is true SF Pro rather than a fallback grotesque.
//   swift scripts/make_brand.swift
import AppKit
import CoreText

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let brand = root.appendingPathComponent("assets/brand")
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)

let ink = NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1)      // #1C1C1E
let accent = NSColor(srgbRed: 1.0, green: 0.584, blue: 0.0, alpha: 1)       // #FF9500
let subtle = NSColor(srgbRed: 0.431, green: 0.431, blue: 0.451, alpha: 1)   // #6E6E73
let canvas = NSColor(srgbRed: 0.961, green: 0.957, blue: 0.957, alpha: 1)   // #F5F4F4

// MARK: - The tile, identical to scripts/make_appicon.swift but placeable.

func drawTile(_ r: NSRect) {
    let ctx = NSGraphicsContext.current!
    ctx.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: r.width * 0.2237, yRadius: r.width * 0.2237).addClip()

    NSGradient(colors: [NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                        NSColor(srgbRed: 0.941, green: 0.937, blue: 0.949, alpha: 1),
                        NSColor(srgbRed: 0.863, green: 0.855, blue: 0.878, alpha: 1)],
               atLocations: [0, 0.52, 1], colorSpace: .sRGB)!.draw(in: r, angle: -75)

    NSGradient(colors: [NSColor(white: 1, alpha: 0.75), NSColor(white: 1, alpha: 0)],
               atLocations: [0, 0.46], colorSpace: .sRGB)!
        .draw(in: NSRect(x: r.minX, y: r.minY + r.height * 0.54,
                         width: r.width, height: r.height * 0.46), angle: -90)

    let font = NSFont.systemFont(ofSize: r.width * (104.0 / 180.0), weight: .medium)
    func glyph(_ color: NSColor) {
        let str = NSAttributedString(string: "\u{2325}",
                                     attributes: [.font: font, .foregroundColor: color])
        let sz = str.size()
        str.draw(at: NSPoint(x: r.minX + (r.width - sz.width) / 2,
                             y: r.minY + (r.height - sz.height) / 2))
    }
    glyph(ink)
    ctx.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: r.minX, y: r.minY + r.height * 0.62,
                              width: r.width, height: r.height * 0.38)).addClip()
    glyph(accent)
    ctx.restoreGraphicsState()

    ctx.restoreGraphicsState()
}

// MARK: - Type, placed by its ink rather than by its line box.

func line(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> CTLine {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return CTLineCreateWithAttributedString(NSAttributedString(
        string: text,
        attributes: [.font: font, .foregroundColor: color,
                     .kern: size * -0.025]))          // letter-spacing -0.025em
}

func inkBounds(_ l: CTLine) -> CGRect { CTLineGetBoundsWithOptions(l, .useGlyphPathBounds) }

/// The point size at which `text` inks exactly `width` wide.
func size(fitting text: String, weight: NSFont.Weight, width: CGFloat) -> CGFloat {
    var size = width / CGFloat(text.count) * 2
    for _ in 0..<6 { size *= width / inkBounds(line(text, size: size, weight: weight, color: ink)).width }
    return size
}

/// Draws so the ink's top-left lands on (`left`, `top`) measured from the top
/// of a canvas `height` tall — the same frame the design board measures in.
func draw(_ l: CTLine, left: CGFloat, top: CGFloat, height: CGFloat) {
    let b = inkBounds(l)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = CGPoint(x: left - b.minX, y: height - top - b.maxY)
    CTLineDraw(l, ctx)
}

func render(width: CGFloat, height: CGFloat, scale: CGFloat, _ body: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    body()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Lockup: the tile left of the wordmark, cap height optically centred.

let wordmark = "fappswap"
let lockupTile: CGFloat = 160
let lockupType: CGFloat = 120
let lockupGap = lockupTile * 0.47                    // 40px icon -> 14px gap
let lockupText = lockupTile + lockupGap
let lockupLine = line(wordmark, size: lockupType, weight: .semibold, color: ink)
let lockupWidth = (lockupText + CGFloat(CTLineGetTypographicBounds(lockupLine, nil, nil, nil))).rounded(.up)

func lockup(_ color: NSColor, scale: CGFloat) -> Data {
    render(width: lockupWidth, height: lockupTile, scale: scale) {
        drawTile(NSRect(x: 0, y: 0, width: lockupTile, height: lockupTile))
        let l = line(wordmark, size: lockupType, weight: .semibold, color: color)
        let cap = NSFont.systemFont(ofSize: lockupType, weight: .semibold).capHeight
        let b = inkBounds(l)
        // Baseline centres the cap-height box on the tile; x is the type origin,
        // so the wordmark's own side bearing sets the optical gap.
        draw(l, left: lockupText + b.minX, top: (lockupTile - cap) / 2 - (b.maxY - cap),
             height: lockupTile)
    }
}

for (name, color) in [("ink", ink), ("white", NSColor.white)] {
    try lockup(color, scale: 1).write(to: brand.appendingPathComponent("wordmark-lockup-\(name).png"))
    try lockup(color, scale: 2).write(to: brand.appendingPathComponent("wordmark-lockup-\(name)@2x.png"))
}

// MARK: - Social preview: GitHub's 1280x640 card.

let tagline = "Menu-bar app switching and text expansion for macOS"
let social = render(width: 1280, height: 640, scale: 1) {
    canvas.setFill()
    NSRect(x: 0, y: 0, width: 1280, height: 640).fill()
    drawTile(NSRect(x: 116, y: 640 - 182 - 276, width: 276, height: 276))
    draw(line(wordmark, size: size(fitting: wordmark, weight: .semibold, width: 393),
              weight: .semibold, color: ink),
         left: 469, top: 258, height: 640)
    draw(line(tagline, size: size(fitting: tagline, weight: .regular, width: 668),
              weight: .regular, color: subtle),
         left: 470, top: 352, height: 640)
    accent.setFill()
    NSRect(x: 470, y: 640 - 406 - 7, width: 118, height: 7).fill()
}
try social.write(to: brand.appendingPathComponent("social-preview-1280x640.png"))

print("wrote \(brand.path)")
