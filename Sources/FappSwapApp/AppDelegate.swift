import AppKit
import ApplicationServices
import Carbon
import FappSwapCore
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "Expansion")

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = BindingStore(url: BindingStore.defaultURL)
    let snippetStore = SnippetStore(url: SnippetStore.defaultURL)
    let tap = HotkeyTap()

    private let engine = ExpansionEngine()
    let pasteboardWriter = PasteboardWriter()
    private lazy var injector = TextInjector(writer: pasteboardWriter)
    let clipboardStore = ClipboardHistoryStore(directory: ClipboardHistoryStore.defaultDirectory)
    private(set) lazy var recorder = ClipboardRecorder(store: clipboardStore, writer: pasteboardWriter)
    private var pruneTimer: Timer?
    private var mouseMonitor: Any?

    private var clipboardPanel: ClipboardPanelController?
    private var statusPanel: StatusPanelController?
    private var bindingsModel: BindingsModel!
    private var snippetsModel: SnippetsModel!
    private var windowCycleModel: WindowCycleModel!
    private var clipboardModel: ClipboardModel!
    let reminderStore = ReminderStore(url: ReminderStore.defaultURL)
    private var reminderModel: ReminderModel!
    private var reminderInput: ReminderInputController?
    private var reminderAlert: ReminderAlertController?
    private let updater = UpdateController()
    private var didPopFirstRunMenu = false
    /// Last observed Secure Event Input state, so it is logged on transitions
    /// rather than on every keystroke.
    private var wasSecureInputActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        tap.lookup = { [weak self] keyCode, modifiers in
            self?.store.binding(keyCode: keyCode, modifiers: modifiers)
        }
        tap.onMatch = { binding in
            AppActivator.activate(bundleID: binding.bundleID)
        }
        tap.onCycleWindows = {
            WindowCycler.cycle()
        }
        // The menu toggle writes both UserDefaults and the live tap; this
        // covers launches, where only the stored value exists.
        tap.windowCycleEnabled = WindowCycleModel.storedEnabled
        tap.clipboardHotkey = ClipboardSettings.isEnabled ? ClipboardSettings.hotkey : nil
        clipboardPanel = ClipboardPanelController(
            store: clipboardStore, writer: pasteboardWriter,
            isPaused: { [weak self] in self?.recorder.isPaused ?? false },
            canPaste: { [weak self] in !(self?.injector.isInjecting ?? true) })
        tap.onShowClipboard = { [weak self] in
            self?.clipboardPanel?.toggle()
        }
        recorder.onChange = { [weak self] in
            guard let self, let panel = self.clipboardPanel, panel.isVisible else { return }
            panel.model.reload()
        }
        tap.onUnmatchedKeyDown = { [weak self] typed in
            self?.handleTyped(typed)
        }
        refreshEngine()

        bindingsModel = BindingsModel(store: store)
        snippetsModel = SnippetsModel(store: snippetStore) { [weak self] in self?.refreshEngine() }
        windowCycleModel = WindowCycleModel { [weak tap] enabled in
            tap?.windowCycleEnabled = enabled
        }
        clipboardModel = ClipboardModel(
            store: clipboardStore, bindings: store,
            onEnabledChange: { [weak self] enabled in
                guard let self else { return }
                if enabled { self.recorder.start() } else { self.recorder.stop() }
                self.tap.clipboardHotkey = enabled ? ClipboardSettings.hotkey : nil
                if !enabled { self.clipboardPanel?.close() }
            },
            onHotkeyChange: { [weak self] hotkey in
                // Only arm the tap if the feature is actually on: the Change dialog is
                // modeless, so history can be switched off from the menu while it is
                // still open, and an unconditional assignment here would leave a live
                // clipboard hotkey behind a disabled feature until the next launch.
                self?.tap.clipboardHotkey = ClipboardSettings.isEnabled ? hotkey : nil
            },
            onHistoryChange: { [weak self] in
                guard let self, let panel = self.clipboardPanel, panel.isVisible else { return }
                panel.model.reload()
            })

        // The card first: the model's `onDue` needs it. Then the model, then the
        // input panel, whose `onCreate` needs the model.
        reminderAlert = ReminderAlertController(
            soundEnabled: { ReminderSettings.isSoundEnabled },
            overdueLabel: { reminder in ReminderFormatting.overdueLabel(reminder.dueDate, now: Date()) },
            hotkeyDisplay: { ReminderSettings.hotkey.displayKey },
            onDismiss: { [weak self] ids in self?.showErrorIfAny(self?.reminderModel.dismiss(ids: ids)) },
            onSnooze: { [weak self] ids, minutes in
                self?.showErrorIfAny(self?.reminderModel.snooze(ids: ids, minutes: minutes))
            })
        reminderModel = ReminderModel(
            store: reminderStore, bindings: store,
            onDue: { [weak self] fired in self?.reminderAlert?.show(fired) },
            onHotkeyChange: { [weak self] hotkey in self?.tap.reminderHotkey = hotkey })
        reminderInput = ReminderInputController(
            parse: { [weak self] input in
                self?.reminderModel.parse(input) ?? .failure(.unrecognized)
            },
            dueLabel: { date in ReminderFormatting.dueLabel(date, now: Date()) },
            onCreate: { [weak self] text, dueDate in
                self?.reminderModel.add(text: text, dueDate: dueDate)
            })
        tap.reminderHotkey = ReminderSettings.hotkey
        // Decision 23: while a card is showing, the hotkey drives the card.
        tap.onReminder = { [weak self] in
            guard let self else { return }
            if let card = self.reminderAlert, card.isVisible {
                card.focus()
            } else {
                self.reminderInput?.open()
            }
        }

        if clipboardStore.didRecoverFromCorruptFile {
            logger.notice("clipboard history file was unreadable and has been backed up; starting empty")
        }
        pruneClipboardHistory()
        // Retention has to be enforced continuously, not only when the setting
        // changes — otherwise "30 days" quietly becomes however long the app
        // has been running.
        let prune = Timer(timeInterval: 3_600, repeats: true) { [weak self] _ in
            self?.pruneClipboardHistory()
            self?.reminderModel.pruneLog()
        }
        prune.tolerance = 0.1
        RunLoop.main.add(prune, forMode: .common)
        pruneTimer = prune
        if ClipboardSettings.isEnabled {
            recorder.start()
        }

        statusPanel = StatusPanelController(
            tap: tap,
            snippets: { [weak self] in
                guard let self else { return (prefix: SnippetStore.defaultPrefix, snippets: []) }
                return (prefix: self.snippetStore.prefix, snippets: self.snippetStore.snippets)
            },
            bindings: { [weak self] in self?.store.bindings ?? [] },
            clipboard: StatusPanelController.ClipboardActions(
                open: { [weak self] in self?.clipboardPanel?.open() },
                togglePause: { [weak self] in self?.recorder.isPaused.toggle() },
                isPaused: { [weak self] in self?.recorder.isPaused ?? false }),
            settings: StatusPanelController.SettingsActions(
                validateShortcut: { [weak self] keyCode, modifiers in
                    self?.bindingsModel.rejection(keyCode: keyCode, modifiers: modifiers)
                },
                saveShortcut: { [weak self] keyCode, modifiers in
                    guard let self else { return }
                    // Modal picker: NSApp.activate() first so its search field takes
                    // typing — the same reason the old Add Shortcut dialog did it.
                    // The panel survives because the panel layer wraps this action in
                    // runPreservingPanel.
                    NSApp.activate()
                    switch AppInfo.pickApplication() {
                    case .cancelled:
                        return
                    case .noBundleID(let name):
                        self.showErrorIfAny("\(name) has no bundle identifier, so it can't be bound.")
                    case .picked(let bundleID):
                        self.showErrorIfAny(self.bindingsModel.add(
                            keyCode: keyCode, modifiers: modifiers, bundleID: bundleID))
                    }
                },
                validateShortcutEdit: { [weak self] binding, keyCode, modifiers in
                    self?.bindingsModel.rejection(
                        keyCode: keyCode, modifiers: modifiers, excluding: binding)
                },
                saveShortcutEdit: { [weak self] binding, keyCode, modifiers in
                    self?.showErrorIfAny(self?.bindingsModel.replace(
                        binding, keyCode: keyCode, modifiers: modifiers))
                },
                removeShortcut: { [weak self] binding in
                    self?.showErrorIfAny(self?.bindingsModel.remove(binding))
                },
                removeSnippet: { [weak self] snippet in
                    self?.showErrorIfAny(self?.snippetsModel.remove(snippet))
                },
                saveSnippet: { [weak self] draft in self?.snippetsModel.save(draft) },
                savePrefix: { [weak self] new in self?.snippetsModel.setPrefix(new) },
                snippetRecoveryNotice: { [weak self] in self?.snippetsModel.recoveryNotice },
                isWindowCyclingEnabled: { [weak self] in self?.windowCycleModel.enabled ?? true },
                setWindowCycling: { [weak self] enabled in self?.windowCycleModel.enabled = enabled },
                isStartAtLoginEnabled: { [weak self] in self?.bindingsModel.startAtLogin ?? false },
                setStartAtLogin: { [weak self] enabled in
                    self?.showErrorIfAny(self?.bindingsModel.setStartAtLogin(enabled))
                },
                isClipboardEnabled: { ClipboardSettings.isEnabled },
                setClipboardEnabled: { [weak self] enabled in self?.clipboardModel.enabled = enabled },
                clipboardHotkeyDisplay: { ClipboardSettings.hotkey.displayKey },
                validateClipboardHotkey: { [weak self] keyCode, modifiers in
                    self?.clipboardModel.rejection(keyCode: keyCode, modifiers: modifiers)
                },
                saveClipboardHotkey: { [weak self] keyCode, modifiers in
                    // Validated by the recorder already; a rejection here can't happen.
                    _ = self?.clipboardModel.setHotkey(keyCode: keyCode, modifiers: modifiers)
                },
                retention: { ClipboardSettings.retention },
                selectRetention: { [weak self] days in self?.selectRetention(days) },
                revealHistory: { [weak self] in self?.clipboardModel.revealInFinder() },
                clearHistory: { [weak self] in self?.clearHistory() },
                openAccessibilitySettings: {
                    NSWorkspace.shared.open(URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }),
            reminders: StatusPanelController.ReminderActions(
                parse: { [weak self] input in
                    self?.reminderModel.parse(input) ?? .failure(.unrecognized)
                },
                previewLabel: { date in ReminderFormatting.dueLabel(date, now: Date()) },
                create: { [weak self] text, dueDate in
                    self?.reminderModel.add(text: text, dueDate: dueDate)
                },
                pending: { [weak self] in self?.reminderModel.pending ?? [] },
                log: { [weak self] in self?.reminderModel.log ?? [] },
                dueLabel: { reminder in
                    reminder.status == .due
                        ? "On screen"
                        : ReminderFormatting.dueLabel(reminder.dueDate, now: Date())
                },
                logLabel: { reminder in ReminderFormatting.logLabel(reminder, now: Date()) },
                cancel: { [weak self] reminder in
                    self?.showErrorIfAny(self?.reminderModel.cancel(reminder))
                },
                hotkeyDisplay: { ReminderSettings.hotkey.displayKey },
                validateHotkey: { [weak self] keyCode, modifiers in
                    self?.reminderModel.rejection(keyCode: keyCode, modifiers: modifiers)
                },
                saveHotkey: { [weak self] keyCode, modifiers in
                    _ = self?.reminderModel.setHotkey(keyCode: keyCode, modifiers: modifiers)
                },
                isSoundEnabled: { ReminderSettings.isSoundEnabled },
                setSoundEnabled: { [weak self] enabled in self?.reminderModel.soundEnabled = enabled },
                clearLog: { [weak self] in self?.clearReminderLog() }),
            // Same path the tap's own `onMatch` uses for a matched hotkey, so
            // clicking a row in the Shortcuts submenu does exactly what pressing
            // the shortcut itself does.
            activate: { bundleID in AppActivator.activate(bundleID: bundleID) },
            updateAction: { [weak self] in self?.updater.userAction() })

        updater.onStateChange = { [weak self] state in
            self?.statusPanel?.refreshUpdateState(state)
        }
        updater.startPeriodicChecks()

        // Fires anything that came due while the app wasn't running, arms the
        // timer, and watches for wake and clock changes.
        reminderModel.start()
        reminderModel.pruneLog()

        // The watchdog inside HotkeyTap changes health with no caller, so the menu
        // bar has to be pushed to rather than polled after each start().
        // `onHealthChange` is single-subscriber (see its doc comment in
        // HotkeyTap) — additional consumers are chained through here rather
        // than reassigning it elsewhere.
        tap.onHealthChange = { [weak self] in
            self?.statusPanel?.refreshStatus()
            self?.popMenuOnFirstRunIfNeeded()
        }

        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        // Fails quietly without permission and arms the watchdog, which retries
        // every 5s and succeeds as soon as the grant lands. No separate poll.
        tap.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tap.reArm()
        }

        // A different app means a different text field: whatever was half-typed
        // in the last one is not a trigger in progress here.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.engine.reset()
        }

        // A click moves the insertion point, so the buffer no longer describes
        // what is in front of the caret. Watched with a global NSEvent monitor
        // rather than by adding mouse events to the CGEventTap's mask: mouse
        // traffic on the tap runs on the main run loop, and every extra
        // millisecond there is another chance of `.tapDisabledByTimeout`.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.engine.reset()
        }
    }

    /// Rebuilds the engine's match table from the store. Called at launch and
    /// after any edit from the menu or a dialog.
    func refreshEngine() {
        engine.update(prefix: snippetStore.prefix, snippets: snippetStore.snippets)
        // Proves an edit actually reached the running engine, and shows
        // the count the engine is matching against. Triggers themselves are not
        // logged — they are user content.
        logger.notice(
            "engine refreshed: \(self.snippetStore.snippets.count, privacy: .public) snippets, prefix=\(self.snippetStore.prefix, privacy: .public)")
    }

    /// Applies the current retention policy. Called at launch and hourly.
    /// `ClipboardModel.applyRetention` enforces a retention change immediately by calling
    /// `store.prune` directly, not through this method.
    func pruneClipboardHistory() {
        do {
            let removed = try clipboardStore.prune(policy: ClipboardSettings.policy)
            if !removed.isEmpty {
                logger.notice("pruned \(removed.count, privacy: .public) clipboard items, \(self.clipboardStore.items.count, privacy: .public) remain")
                // `recorder.onChange` and `onClipboardHistoryChange` both reload a
                // visible panel after a change; this periodic path needs the same,
                // so a prune that lands while the panel is open doesn't leave it
                // showing rows that were just removed.
                if let panel = clipboardPanel, panel.isVisible {
                    panel.model.reload()
                }
            }
        } catch {
            logger.error("clipboard prune failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleTyped(_ key: TypedKey) {
        // Our own injected keystrokes are already filtered out in the tap; this
        // additionally ignores whatever the user types *during* an injection,
        // which would otherwise interleave with the backspaces.
        guard !injector.isInjecting else {
            // Repeated lines here mean the flag is stuck, which would silently
            // disable expansion while leaving hotkeys working. One line per
            // keystroke is acceptable precisely because it should be rare.
            logger.notice("keystroke ignored: an injection is in flight")
            return
        }

        // Typing in the clipboard panel's search field or the reminder input
        // still flows through the tap. Feeding it to the engine could expand a
        // snippet *into the field*.
        if clipboardPanel?.isVisible == true || reminderInput?.isVisible == true
            || statusPanel?.isVisible == true {
            engine.reset()
            return
        }

        // Secure Event Input means a password field or Terminal's secure entry.
        // Expansion is skipped entirely there — the same limitation the hotkeys
        // have, for the same reason — and the buffer is dropped rather than
        // accumulating characters typed into a password field.
        //
        // Note this is close to unreachable: secure input starves event taps of
        // keystrokes, so we normally never get called to skip them. It covers the
        // race where secure input turns on between the tap seeing an event and
        // this handler running, and its logging is how we would find out if
        // secure input were ever stuck on.
        let secureInputActive = IsSecureEventInputEnabled()
        if secureInputActive != wasSecureInputActive {
            wasSecureInputActive = secureInputActive
            logger.notice(
                "secure event input \(secureInputActive ? "active — expansion paused" : "cleared", privacy: .public)")
        }
        if secureInputActive {
            engine.reset()
            return
        }

        switch key {
        case .boundary:
            engine.reset()
        case .backspace:
            engine.consumeBackspace()
        case .text(let text):
            if case .expand(let deleteCount, let replacement) = engine.consume(text: text) {
                // Lengths only, never the trigger or the replacement text.
                logger.notice(
                    "trigger matched: deleting \(deleteCount, privacy: .public), inserting \(replacement.count, privacy: .public) chars")
                injector.inject(deleteCount: deleteCount, text: replacement)
            }
        }
    }

    /// Pops the menu open on first run, but only once the tap is live — otherwise
    /// it would fight the system Accessibility prompt at launch.
    private func popMenuOnFirstRunIfNeeded() {
        guard !didPopFirstRunMenu, tap.isRunning else { return }
        guard store.didRecoverFromCorruptFile || store.bindings.isEmpty else {
            didPopFirstRunMenu = true
            return
        }
        didPopFirstRunMenu = true
        statusPanel?.open()
    }

    // MARK: - Alerts
    //
    // `runModal` is safe for the tap: its run-loop source is in `.commonModes`
    // (`HotkeyTap.start`), which includes the modal-panel mode, so events keep
    // flowing while an alert is up — the same reason `AppInfo.pickApplication()`
    // has always been fine. `NSApp.activate()` first so ↩ and ⎋ reach the alert;
    // as an accessory app fappswap is otherwise not the one receiving keys.

    /// Destructive confirmation. Cancel is the default button, so `↩` declines and
    /// Delete has to be clicked or reached with `⇥` — the point being that no
    /// keystroke can delete. `⎋` does *not* decline: AppKit gives a button titled
    /// "Cancel" the Escape equivalent automatically, and setting `"\r"` below to make
    /// it the default button replaces that. A button can only hold one key
    /// equivalent, so this is a choice between `↩` and `⎋`, not a bug to fix.
    private func confirmDestructive(title: String, message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: button)
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showErrorIfAny(_ message: String??) {
        guard let message = message ?? nil else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    private func selectRetention(_ days: RetentionDays) {
        switch clipboardModel.selectRetention(days) {
        case .unchanged:
            return
        case .applied(let error):
            showErrorIfAny(error)
        case .needsConfirmation(let count):
            let ok = confirmDestructive(
                title: "Delete \(count) items older than \(days.label)?",
                message: "Shortening the history deletes what falls outside it. This can't be undone.",
                button: "Delete")
            if ok { showErrorIfAny(clipboardModel.applyRetention(days)) }
        }
    }

    private func clearHistory() {
        let ok = confirmDestructive(
            title: "Delete all \(clipboardModel.itemCount) items?",
            message: "Every recorded item and image is removed. This can't be undone.",
            button: "Delete")
        if ok { showErrorIfAny(clipboardModel.clearHistory()) }
    }

    private func clearReminderLog() {
        let count = reminderModel.log.count
        let ok = confirmDestructive(
            title: "Delete all \(count) past reminders?",
            message: "Pending reminders are kept. This can't be undone.",
            button: "Delete")
        if ok { showErrorIfAny(reminderModel.clearLog()) }
    }

}
