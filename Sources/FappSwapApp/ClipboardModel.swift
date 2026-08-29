import AppKit
import FappSwapCore
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "ClipboardSettings")

/// Clipboard settings logic. The retention shrink that needs a confirmation is
/// reported as a return value; `AppDelegate` runs the alert and calls
/// `applyRetention` if the user agrees.
final class ClipboardModel {
    enum RetentionChange: Equatable {
        case unchanged
        case applied(error: String?)
        case needsConfirmation(count: Int)
    }

    private let store: ClipboardHistoryStore
    private let bindings: BindingStore
    private let onEnabledChange: (Bool) -> Void
    private let onHotkeyChange: (Hotkey) -> Void
    /// Called after a prune or clear so an open panel reloads.
    private let onHistoryChange: () -> Void

    init(store: ClipboardHistoryStore, bindings: BindingStore,
         onEnabledChange: @escaping (Bool) -> Void,
         onHotkeyChange: @escaping (Hotkey) -> Void,
         onHistoryChange: @escaping () -> Void) {
        self.store = store
        self.bindings = bindings
        self.onEnabledChange = onEnabledChange
        self.onHotkeyChange = onHotkeyChange
        self.onHistoryChange = onHistoryChange
    }

    var enabled: Bool {
        get { ClipboardSettings.isEnabled }
        set {
            guard newValue != ClipboardSettings.isEnabled else { return }
            ClipboardSettings.isEnabled = newValue
            onEnabledChange(newValue)
        }
    }

    var hotkey: Hotkey { ClipboardSettings.hotkey }
    var retention: RetentionDays { ClipboardSettings.retention }
    var itemCount: Int { store.items.count }

    // MARK: - Hotkey

    /// Why the combination can't be the clipboard shortcut, or nil if it can.
    func rejection(keyCode: UInt16, modifiers: Set<Modifier>) -> String? {
        HotkeyValidation.forClipboard(
            Hotkey(keyCode: keyCode, modifiers: modifiers), bindings: bindings.bindings,
            reminderHotkey: ReminderSettings.hotkey)?.message
    }

    /// Validates, stores and notifies the tap. Returns the rejection, or nil when set.
    func setHotkey(keyCode: UInt16, modifiers: Set<Modifier>) -> String? {
        if let message = rejection(keyCode: keyCode, modifiers: modifiers) { return message }
        let candidate = Hotkey(keyCode: keyCode, modifiers: modifiers)
        ClipboardSettings.hotkey = candidate
        onHotkeyChange(candidate)
        return nil
    }

    // MARK: - Retention

    /// Shrinking with something to delete asks first; anything else applies
    /// immediately, carrying along any prune error rather than discarding it.
    func selectRetention(_ new: RetentionDays) -> RetentionChange {
        guard new != retention else { return .unchanged }
        let count = store.countThatWouldBeRemoved(by: RetentionPolicy(days: new))
        if new.rawValue < retention.rawValue, count > 0 {
            return .needsConfirmation(count: count)
        }
        return .applied(error: applyRetention(new))
    }

    /// Stores the new retention and prunes immediately. Returns a prune error, or nil.
    func applyRetention(_ new: RetentionDays) -> String? {
        ClipboardSettings.retention = new
        defer { onHistoryChange() }
        do {
            let removed = try store.prune(policy: RetentionPolicy(days: new))
            // Counts only — never the items themselves. Matches
            // `AppDelegate.pruneClipboardHistory()`'s shape for the periodic prune.
            if !removed.isEmpty {
                logger.notice("clipboard retention set to \(new.rawValue, privacy: .public) days: pruned \(removed.count, privacy: .public) items, \(self.store.items.count, privacy: .public) remain")
            }
            return nil
        } catch {
            logger.error("clipboard retention prune failed: \(error.localizedDescription, privacy: .public)")
            return "Could not prune the history: \(error.localizedDescription)"
        }
    }

    // MARK: - Storage

    func revealInFinder() {
        try? store.ensureDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    func clearHistory() -> String? {
        let countBeforeClear = store.items.count
        defer { onHistoryChange() }
        do {
            try store.clear()
            // Counts only — never the items themselves.
            logger.notice("clipboard history cleared: \(countBeforeClear, privacy: .public) items removed")
            return nil
        } catch {
            logger.error("clipboard clear failed: \(error.localizedDescription, privacy: .public)")
            return "Could not clear the history: \(error.localizedDescription)"
        }
    }
}
