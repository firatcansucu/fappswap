import FappSwapCore
import Foundation

/// `UserDefaults` access for the clipboard feature. Missing keys read as the
/// defaults, so a fresh install needs nothing written. Same pattern as
/// `WindowCycleModel.storedEnabled`.
enum ClipboardSettings {
    static let enabledKey = "clipboardHistoryEnabled"
    static let retentionKey = "clipboardRetentionDays"
    static let hotkeyKey = "clipboardHotkey"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var retention: RetentionDays {
        get { RetentionDays(rawValue: UserDefaults.standard.integer(forKey: retentionKey)) ?? .thirty }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: retentionKey) }
    }

    /// Stored as JSON under one key so key code and modifiers can't drift apart.
    static var hotkey: Hotkey {
        get {
            guard let data = UserDefaults.standard.data(forKey: hotkeyKey),
                  let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data)
            else { return .clipboardDefault }
            return hotkey
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: hotkeyKey)
        }
    }

    static var policy: RetentionPolicy { RetentionPolicy(days: retention) }
}
