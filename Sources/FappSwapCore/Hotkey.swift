/// A key combination without an action attached — what the clipboard panel is
/// opened with, and what `⌥⇥` is. `Binding` is a `Hotkey` plus a bundle ID.
public struct Hotkey: Codable, Equatable, Sendable {
    /// Hardware virtual key code — layout independent.
    public let keyCode: UInt16
    public let modifiers: Set<Modifier>

    public init(keyCode: UInt16, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// `⌥⌘V`. Collides only with Finder's Move Items Here; `⌘⇧V` was rejected
    /// because it is Paste and Match Style in most apps.
    public static let clipboardDefault = Hotkey(keyCode: 9, modifiers: [.option, .command])
    /// `⌥⇥`, reserved for window cycling.
    public static let windowCycle = Hotkey(keyCode: 48, modifiers: [.option])
    /// `⌥R`, the reminder hotkey. On the Option layer like everything else the app
    /// does; there were no users to collide with when it was chosen. Unlike the
    /// clipboard hotkey it is never nil — the feature has no off switch.
    public static let reminderDefault = Hotkey(keyCode: 15, modifiers: [.option])

    public func matches(keyCode: UInt16, modifiers: Set<Modifier>) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    /// Symbols in `Modifier.allCases` order, then the key name — e.g. `⌘⌥V`.
    public var displayKey: String {
        let mods = Modifier.allCases.filter { modifiers.contains($0) }
        return mods.map(\.symbol).joined() + KeyNames.name(for: keyCode)
    }
}
