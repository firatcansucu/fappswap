import AppKit
import FappSwapCore

/// Bindings and start-at-login, with every mutation reporting its error as a return
/// value: the menu shows it in an alert, the Add Shortcut dialog shows it inline.
/// A plain class, not an `ObservableObject` — nothing observes it; the menu is
/// rebuilt on open and the dialog holds its own state.
final class BindingsModel {
    private let store: BindingStore

    init(store: BindingStore) {
        self.store = store
    }

    var bindings: [FappSwapCore.Binding] { store.bindings }

    /// Why the combination can't be bound, or nil if it can. `excluding` is the
    /// binding being re-recorded: a shortcut must not be rejected for clashing
    /// with itself.
    func rejection(keyCode: UInt16, modifiers: Set<Modifier>,
                   excluding: FappSwapCore.Binding? = nil) -> String? {
        // Only a conflict while the feature is on: with it off, `tap.clipboardHotkey`
        // is nil and the combination really is free. The reminder hotkey has no off.
        let clipboard = ClipboardSettings.isEnabled ? ClipboardSettings.hotkey : nil
        let others = store.bindings.filter { $0.id != excluding?.id }
        return HotkeyValidation.forBinding(
            Hotkey(keyCode: keyCode, modifiers: modifiers),
            bindings: others, clipboardHotkey: clipboard,
            reminderHotkey: ReminderSettings.hotkey)?.message
    }

    /// Adds and saves. Validate with `rejection` first; this does not re-check.
    func add(keyCode: UInt16, modifiers: Set<Modifier>, bundleID: String) -> String? {
        store.add(FappSwapCore.Binding(keyCode: keyCode, modifiers: modifiers, bundleID: bundleID))
        return persist()
    }

    /// Rebinds an existing shortcut to a new combination, keeping its app.
    /// Validate with `rejection(keyCode:modifiers:excluding:)` first; this does
    /// not re-check.
    func replace(_ binding: FappSwapCore.Binding,
                 keyCode: UInt16, modifiers: Set<Modifier>) -> String? {
        store.remove(id: binding.id)
        store.add(FappSwapCore.Binding(
            keyCode: keyCode, modifiers: modifiers, bundleID: binding.bundleID))
        return persist()
    }

    func remove(_ binding: FappSwapCore.Binding) -> String? {
        store.remove(id: binding.id)
        return persist()
    }

    private func persist() -> String? {
        do {
            try store.save()
            return nil
        } catch {
            return "Could not save shortcuts: \(error.localizedDescription)"
        }
    }

    /// Read from disk every time, so a login item plist added or removed
    /// externally shows correctly the next time the menu opens.
    var startAtLogin: Bool { LoginItem.isEnabled }

    func setStartAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try LoginItem.enable()
            } else {
                try LoginItem.disable()
            }
            return nil
        } catch {
            return "Could not change start at login: \(error.localizedDescription)"
        }
    }
}
