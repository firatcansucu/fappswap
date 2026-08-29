import AppKit

/// The status item's two images.
///
/// The healthy state is the identity mark, U+2325 OPTION KEY — the key every
/// shortcut in the app begins with, and the same character the app icon is
/// built from. It is drawn as a template image so macOS keeps owning its
/// colour: light bars, dark bars and the pressed (inverted) state all keep
/// working exactly as they did for the SF Symbol this replaced.
enum MenuBarIcon {
    /// 15pt SF Pro Text Medium in an 18pt box reads at the weight of the Wi-Fi
    /// and battery items beside it.
    static let listening: NSImage = {
        let side: CGFloat = 18                       // 16pt glyph + 1pt breathing room
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let str = NSAttributedString(
                string: "\u{2325}",
                attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium),
                             .foregroundColor: NSColor.black])
            let size = str.size()
            str.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
            return true
        }
        image.isTemplate = true                      // required: macOS owns the colour
        image.accessibilityDescription = "fappswap"
        return image
    }()

    /// Shown only when the tap isn't running, which is almost always a missing
    /// Accessibility grant. Deliberately not the mark: a broken app should not
    /// look like a working one.
    static let noPermission: NSImage = {
        let image = NSImage(systemSymbolName: "exclamationmark.triangle",
                            accessibilityDescription: "fappswap — no permission")!
        image.isTemplate = true
        return image
    }()
}
