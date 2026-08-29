import AppKit
import FappSwapCore
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "Reminders")

/// Reminder logic and the one timer. A plain class like `ClipboardModel`: the
/// menu is rebuilt on open, the two panels hold their own state, and every
/// error comes back as a return value for `AppDelegate` to show.
///
/// One non-repeating `Timer`, armed for the earliest pending reminder and
/// re-armed after every change, on wake, and on a system clock change. A `Timer`
/// does not fire while the Mac sleeps; the wake observer is what makes a reminder
/// that came due during sleep appear the moment the lid opens (spec decision 14).
/// `start()` fires anything already overdue, which covers a reminder that came
/// due while the app wasn't running (decision 15).
final class ReminderModel {
    static let snoozeChoices = [5, 15]

    private let store: ReminderStore
    private let bindings: BindingStore
    private let now: () -> Date
    private let onDue: ([Reminder]) -> Void
    private let onHotkeyChange: (Hotkey) -> Void
    private var timer: Timer?

    init(store: ReminderStore, bindings: BindingStore, now: @escaping () -> Date = Date.init,
         onDue: @escaping ([Reminder]) -> Void, onHotkeyChange: @escaping (Hotkey) -> Void) {
        self.store = store
        self.bindings = bindings
        self.now = now
        self.onDue = onDue
        self.onHotkeyChange = onHotkeyChange
    }

    /// Called once after launch. Fires what is already overdue, arms the timer,
    /// and starts watching for wake and clock changes. Observers are never
    /// removed: this object lives as long as the app.
    func start() {
        if store.didRecoverFromCorruptFile {
            logger.notice("reminders file was unreadable and has been backed up; starting empty")
        }
        // A reminder that was on the card when the app quit is still `.due` in the
        // file, and `fireDue` only ever transitions *from* `.pending` — so nothing
        // would put it back on screen. Carry it over before checking the clock.
        // `ReminderAlertModel.add` dedupes by id, so the `checkDue()` below can
        // safely fire more without double-showing these.
        let carried = store.due
        if !carried.isEmpty {
            logger.notice("\(carried.count, privacy: .public) reminders were still on the card at quit")
            onDue(carried)
        }
        checkDue()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            logger.notice("wake: checking reminders")
            self?.checkDue()
        }
        // Timezone or clock change: the stored instants are right, the timer's
        // wall-clock fire date may not be.
        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            logger.notice("system clock changed: checking reminders")
            self?.checkDue()
        }
    }

    // MARK: - Reads

    /// What the menu's pending section shows: on-screen first, then waiting.
    var pending: [Reminder] { store.due + store.pending }
    var log: [Reminder] { store.log }
    var hotkey: Hotkey { ReminderSettings.hotkey }

    var soundEnabled: Bool {
        get { ReminderSettings.isSoundEnabled }
        set { ReminderSettings.isSoundEnabled = newValue }
    }

    func parse(_ input: String) -> Result<Date, ReminderTimeParser.Failure> {
        ReminderTimeParser.parse(input, now: now())
    }

    // MARK: - Writes

    func add(text: String, dueDate: Date) -> String? {
        do {
            let reminder = try store.add(text: text, dueDate: dueDate, now: now())
            // Lead time and counts only — never the text.
            logger.notice("reminder added, due in \(Int(reminder.dueDate.timeIntervalSince(self.now())), privacy: .public) s; \(self.store.pending.count, privacy: .public) pending")
            rearm()
            return nil
        } catch {
            return failure("save", error)
        }
    }

    func cancel(_ reminder: Reminder) -> String? {
        do {
            try store.cancel(id: reminder.id, now: now())
            logger.notice("reminder cancelled; \(self.store.pending.count, privacy: .public) pending")
            rearm()
            return nil
        } catch {
            return failure("cancel", error)
        }
    }

    func dismiss(ids: Set<UUID>) -> String? {
        do {
            try store.dismiss(ids: ids, now: now())
            logger.notice("\(ids.count, privacy: .public) reminders dismissed")
            return nil
        } catch {
            return failure("dismiss", error)
        }
    }

    func snooze(ids: Set<UUID>, minutes: Int) -> String? {
        do {
            try store.snooze(ids: ids, minutes: minutes, now: now())
            logger.notice("\(ids.count, privacy: .public) reminders snoozed \(minutes, privacy: .public) min")
            rearm()
            return nil
        } catch {
            return failure("snooze", error)
        }
    }

    func clearLog() -> String? {
        do {
            let removed = try store.clearLog()
            logger.notice("reminder log cleared: \(removed, privacy: .public) removed")
            return nil
        } catch {
            // The shared template would read "clear the log for the reminder".
            logger.error("could not clear the reminder log: \(error.localizedDescription, privacy: .public)")
            return "Could not clear the reminder log: \(error.localizedDescription)"
        }
    }

    /// Called at launch and hourly by `AppDelegate`'s prune timer (decision 29).
    func pruneLog() {
        do {
            let removed = try store.pruneLog(now: now())
            if removed > 0 {
                logger.notice("pruned \(removed, privacy: .public) reminders from the log")
            }
        } catch {
            logger.error("reminder log prune failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Hotkey

    /// Why the combination can't be the reminder shortcut, or nil if it can.
    func rejection(keyCode: UInt16, modifiers: Set<Modifier>) -> String? {
        let clipboard = ClipboardSettings.isEnabled ? ClipboardSettings.hotkey : nil
        return HotkeyValidation.forReminder(
            Hotkey(keyCode: keyCode, modifiers: modifiers),
            bindings: bindings.bindings, clipboardHotkey: clipboard)?.message
    }

    /// Validates, stores and notifies the tap. Returns the rejection, or nil when set.
    func setHotkey(keyCode: UInt16, modifiers: Set<Modifier>) -> String? {
        if let message = rejection(keyCode: keyCode, modifiers: modifiers) { return message }
        let candidate = Hotkey(keyCode: keyCode, modifiers: modifiers)
        ReminderSettings.hotkey = candidate
        onHotkeyChange(candidate)
        return nil
    }

    // MARK: - Timer

    private func checkDue() {
        do {
            let fired = try store.fireDue(now: now())
            if !fired.isEmpty {
                logger.notice("\(fired.count, privacy: .public) reminders fired")
                onDue(fired)
            }
        } catch {
            logger.error("could not record fired reminders: \(error.localizedDescription, privacy: .public)")
            // `fireDue` flipped statuses in memory before the write that threw. The
            // reminders are due whether or not the file says so, so still show them:
            // a failed write costs persistence, not the card.
            onDue(store.due)
        }
        rearm()
    }

    /// One timer for the next pending reminder. A fire date already in the past
    /// fires on the next run-loop turn, which is what a reminder that came due
    /// during a modal alert needs.
    private func rearm() {
        timer?.invalidate()
        timer = nil
        // Silent when there is nothing to arm: `rearm()` runs on launch, on every
        // wake, on every clock change and after every mutation, and a persisted
        // notice line each time would bury the log for a user with no reminders.
        guard let next = store.nextDueDate else { return }
        let armed = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            self?.checkDue()
        }
        armed.tolerance = 0.5
        RunLoop.main.add(armed, forMode: .common)
        timer = armed
        logger.notice("reminder timer armed for \(next.description, privacy: .public)")
    }

    private func failure(_ what: String, _ error: Error) -> String {
        logger.error("could not \(what, privacy: .public) reminder: \(error.localizedDescription, privacy: .public)")
        return "Could not \(what) the reminder: \(error.localizedDescription)"
    }
}
