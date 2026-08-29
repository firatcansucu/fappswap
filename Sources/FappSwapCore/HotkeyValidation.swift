/// Why a key combination can't be bound. One enum for the app-shortcut, clipboard
/// and reminder recorders, so they can't drift apart — before this existed the
/// clipboard check refused `⌥⇥` and the shortcut check didn't, so `⌥⇥` could be
/// bound to an app and silently never fire (window cycling is matched first in
/// `HotkeyTap`). Every reserved hotkey is refused on every *other* path.
public enum HotkeyConflict: Equatable, Sendable {
    case noModifier
    case windowCycle
    case clipboardHotkey
    case reminderHotkey
    case existingBinding

    /// The wording the dialogs show. Shared so the recorders say the same thing.
    public var message: String {
        switch self {
        case .noModifier: return "Use at least one modifier, for example ⌥F."
        case .windowCycle: return "⌥⇥ is window cycling. Pick another combination."
        case .clipboardHotkey:
            return "That's the clipboard history shortcut. Change it under Clipboard Settings first."
        case .reminderHotkey:
            return "That's the reminder shortcut. Change it under Reminders first."
        case .existingBinding: return "That combination is already in use."
        }
    }
}

public enum HotkeyValidation {
    /// Why `candidate` can't become an app shortcut, or nil if it can. Pass
    /// `clipboardHotkey` as nil when clipboard history is off: the combination is
    /// then genuinely free, and refusing it would send the user to a control they
    /// can't use to "fix" a conflict that doesn't exist. The reminder hotkey is
    /// always live, so it is never optional.
    public static func forBinding(_ candidate: Hotkey, bindings: [Binding],
                                  clipboardHotkey: Hotkey?, reminderHotkey: Hotkey) -> HotkeyConflict? {
        if let reserved = reservedConflict(candidate, clipboardHotkey: clipboardHotkey, reminderHotkey: reminderHotkey) {
            return reserved
        }
        return bindingConflict(candidate, bindings: bindings)
    }

    /// Why `candidate` can't become the clipboard shortcut, or nil if it can. The
    /// current clipboard shortcut is not passed: re-recording the same combination
    /// is a no-op, not a conflict.
    public static func forClipboard(_ candidate: Hotkey, bindings: [Binding],
                                    reminderHotkey: Hotkey) -> HotkeyConflict? {
        if let reserved = reservedConflict(candidate, clipboardHotkey: nil, reminderHotkey: reminderHotkey) {
            return reserved
        }
        return bindingConflict(candidate, bindings: bindings)
    }

    /// Why `candidate` can't become the reminder shortcut, or nil if it can. Same
    /// rule: the current reminder shortcut is not passed.
    public static func forReminder(_ candidate: Hotkey, bindings: [Binding],
                                   clipboardHotkey: Hotkey?) -> HotkeyConflict? {
        if let reserved = reservedConflict(candidate, clipboardHotkey: clipboardHotkey, reminderHotkey: nil) {
            return reserved
        }
        return bindingConflict(candidate, bindings: bindings)
    }

    /// The checks every path shares, in the order the tap matches: modifier,
    /// `⌥⇥`, clipboard, reminder. A path passes nil for its own hotkey.
    private static func reservedConflict(_ candidate: Hotkey, clipboardHotkey: Hotkey?,
                                         reminderHotkey: Hotkey?) -> HotkeyConflict? {
        if candidate.modifiers.isEmpty { return .noModifier }
        if candidate == .windowCycle { return .windowCycle }
        if let clipboardHotkey, candidate == clipboardHotkey { return .clipboardHotkey }
        if let reminderHotkey, candidate == reminderHotkey { return .reminderHotkey }
        return nil
    }

    private static func bindingConflict(_ candidate: Hotkey, bindings: [Binding]) -> HotkeyConflict? {
        bindings.contains { $0.matches(keyCode: candidate.keyCode, modifiers: candidate.modifiers) }
            ? .existingBinding : nil
    }
}
