import Foundation
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "TextInjector")

/// Deletes a typed trigger and inserts the replacement in its place.
///
/// Nothing here may block. This runs on the main run loop — the same thread
/// `HotkeyTap`'s callback runs on — where a synchronous wait is exactly what
/// produces `.tapDisabledByTimeout` and silently kills every hotkey in the app.
/// Every delay is therefore an `asyncAfter` hop, never a sleep. This is the same
/// constraint that forced `AppActivator`'s `osascript` call off the main thread.
///
/// Pastes rather than synthesising the replacement character by character:
/// snippets may be multi-line and hundreds of characters long, where synthetic
/// typing is slow and drops keys in some apps.
final class TextInjector {
    private let writer: PasteboardWriter

    init(writer: PasteboardWriter) {
        self.writer = writer
    }

    /// True from the first backspace until the clipboard has been restored.
    /// Read by `AppDelegate` to ignore keystrokes while an injection is in flight.
    private(set) var isInjecting = false

    // Starting values, confirmed by the manual verification pass in four apps
    // (TextEdit, Chrome, Terminal, Slack): 4 ms between backspaces and a 50 ms
    // settle before ⌘V. Raise them if an app is ever seen pasting before the
    // deletion has finished.
    private static let backspaceInterval: TimeInterval = 0.004
    private static let settleBeforePaste: TimeInterval = 0.05
    /// The paste has to have been consumed before the clipboard changes back.
    private static let pasteToRestore: TimeInterval = 0.15

    func inject(deleteCount: Int, text: String) {
        guard !isInjecting, deleteCount > 0, !text.isEmpty else { return }
        isInjecting = true
        // `.notice`, not `.debug`: debug-level messages are not persisted to the
        // log store, so a `log show` after the fact cannot see them — which is
        // exactly when you need to know whether an injection started and
        // finished. Lengths only, never the replacement text.
        logger.notice(
            "injection started: deleting \(deleteCount, privacy: .public), inserting \(text.count, privacy: .public) chars")
        deleteBackwards(remaining: deleteCount) { [weak self] in
            self?.paste(text)
        }
    }

    private func deleteBackwards(remaining: Int, then completion: @escaping () -> Void) {
        guard remaining > 0 else {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.settleBeforePaste, execute: completion)
            return
        }
        SyntheticKey.post(keyCode: SyntheticKey.backspaceKeyCode, flags: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.backspaceInterval) { [weak self] in
            self?.deleteBackwards(remaining: remaining - 1, then: completion)
        }
    }

    private func paste(_ text: String) {
        let snapshot = writer.snapshot()
        writer.write(text: text)
        SyntheticKey.post(keyCode: SyntheticKey.vKeyCode, flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteToRestore) { [weak self] in
            self?.writer.restore(snapshot)
            self?.isInjecting = false
            // The matching half of "injection started". A start with no finish is
            // how a stuck `isInjecting` would show up.
            logger.notice("injection finished, clipboard restored")
        }
    }
}
