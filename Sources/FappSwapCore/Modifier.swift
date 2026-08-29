import CoreGraphics

public enum Modifier: String, Codable, CaseIterable, Sendable, Comparable {
    case command
    case control
    case option
    case shift

    public static func < (lhs: Modifier, rhs: Modifier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public extension Modifier {
    /// Reads only the four modifiers we bind on. Caps lock, fn, numeric pad and
    /// device-dependent bits are ignored, so a binding matches regardless of them.
    ///
    /// Mirrors `Modifier.set(from: NSEvent.ModifierFlags)` in
    /// `FappSwapApp/KeyRecorder.swift` — the two must stay in agreement, or the
    /// tap (this one) and the recorder (that one) will disagree about what a
    /// keystroke's modifiers are and a recorded shortcut will silently never fire.
    static func set(from flags: CGEventFlags) -> Set<Modifier> {
        var result = Set<Modifier>()
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    /// Symbol used in the UI, e.g. ⌥.
    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        }
    }
}
