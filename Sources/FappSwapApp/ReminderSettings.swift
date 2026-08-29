import FappSwapCore
import Foundation

/// `UserDefaults` access for reminders. Missing keys read as the defaults, so a
/// fresh install needs nothing written. Same pattern as `ClipboardSettings`.
enum ReminderSettings {
    static let hotkeyKey = "reminderHotkey"
    static let soundKey = "reminderSoundEnabled"

    /// Stored as JSON under one key so key code and modifiers can't drift apart.
    static var hotkey: Hotkey {
        get {
            guard let data = UserDefaults.standard.data(forKey: hotkeyKey),
                  let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data)
            else { return .reminderDefault }
            return hotkey
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: hotkeyKey)
        }
    }

    /// The **Play a Sound** checkmark (spec decision 26). On by default.
    static var isSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }
}
