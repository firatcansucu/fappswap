/// What a keystroke means to the text expander.
///
/// Classified from the characters the event produces rather than from key codes,
/// so it is layout-independent: `§` is the ISO section key and does not exist at
/// all on ANSI layouts, and a key-code-based design would not survive being
/// shipped to another machine.
public enum TypedKey: Equatable, Sendable {
    case text(String)
    case backspace
    /// Not text, or text that ends the current word. Clears the buffer.
    case boundary

    /// Key code 51 — delete. Named because it is the one code with its own case.
    private static let deleteKeyCode: UInt16 = 51

    private static let boundaryKeyCodes: Set<UInt16> = [
        36,   // return
        76,   // keypad enter
        48,   // tab
        53,   // escape
        117,  // forward delete
        115,  // home
        119,  // end
        116,  // page up
        121,  // page down
        123, 124, 125, 126,  // arrows
    ]

    public static func classify(
        keyCode: UInt16, modifiers: Set<Modifier>, text: String
    ) -> TypedKey {
        // A chord is a command, not typing. Option is excluded on purpose: it is
        // a text-producing modifier, and the combinations bound to apps never
        // reach here because the tap swallows them first.
        if modifiers.contains(.command) || modifiers.contains(.control) { return .boundary }
        if keyCode == deleteKeyCode { return .backspace }
        if boundaryKeyCodes.contains(keyCode) { return .boundary }
        guard let first = text.unicodeScalars.first, !isControl(first) else { return .boundary }
        return .text(text)
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F
    }
}
