import CoreGraphics
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "SyntheticKey")

/// Posts a key-down/key-up pair stamped with the app's marker, so `HotkeyTap`
/// recognises the app's own keystrokes and never feeds them back into the
/// expander or matches them as shortcuts. Shared by `TextInjector` (backspaces
/// and ⌘V for expansion) and the clipboard panel (⌘V for paste).
enum SyntheticKey {
    /// `"fapp"`. Read back by `HotkeyTap` from `.eventSourceUserData`.
    static let eventMarker: Int64 = 0x6661_7070
    static let backspaceKeyCode: CGKeyCode = 51
    static let vKeyCode: CGKeyCode = 9

    static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else {
                logger.error("could not create event for keyCode \(keyCode, privacy: .public)")
                continue
            }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
