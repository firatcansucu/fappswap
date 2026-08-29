import AppKit
import FappSwapCore
import SwiftUI
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "StatusPanel")

/// A panel that takes keyboard focus without activating the app — the
/// `ClipboardPanel` recipe. The app the user was in stays active while they type
/// in the panel's fields, so nothing about their frontmost window changes just
/// because they opened settings.
final class StatusPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the status item and the panel hanging under it. It builds no UI itself:
/// the panel hosts one SwiftUI view over `StatusPanelModel`, and every mutation
/// goes through the closure structs below, exactly as the menu's did. This
/// controller never touches a store, a model, or `AppActivator`; confirmation
/// and error alerts live behind the closures in `AppDelegate`.
final class StatusPanelController: NSObject {
    struct ClipboardActions {
        let open: () -> Void
        let togglePause: () -> Void
        let isPaused: () -> Bool
    }

    /// Everything the Reminders tab does, as closures, like `ClipboardActions`.
    /// Confirmation and error alerts live behind these in `AppDelegate`.
    struct ReminderActions {
        /// The ⌥R panel's parser and label, so the tab's inline add reads a time
        /// exactly the way the quick-add panel does.
        let parse: (String) -> Result<Date, ReminderTimeParser.Failure>
        let previewLabel: (Date) -> String
        let create: (String, Date) -> String?
        /// On-screen first, then pending, earliest first.
        let pending: () -> [Reminder]
        let log: () -> [Reminder]
        let dueLabel: (Reminder) -> String
        let logLabel: (Reminder) -> String
        let cancel: (Reminder) -> Void
        let hotkeyDisplay: () -> String
        let validateHotkey: (UInt16, Set<Modifier>) -> String?
        let saveHotkey: (UInt16, Set<Modifier>) -> Void
        let isSoundEnabled: () -> Bool
        let setSoundEnabled: (Bool) -> Void
        let clearLog: () -> Void
    }

    /// Everything the settings rows do, as closures, in the style of
    /// `ClipboardActions`: the tabs call these; they never touch a store or a
    /// model. Confirmation alerts and error alerts live behind these closures in
    /// `AppDelegate`.
    struct SettingsActions {
        /// Why the combination can't be bound, or nil. The inline recorder asks
        /// before saving, and keeps listening after a rejection.
        let validateShortcut: (UInt16, Set<Modifier>) -> String?
        /// Picks an app and binds the combination to it. Runs a modal picker, so
        /// callers go through `StatusPanelModel.perform`.
        let saveShortcut: (UInt16, Set<Modifier>) -> Void
        /// Re-recording an existing shortcut: the same validation, minus the row's
        /// own combination, which would otherwise reject itself.
        let validateShortcutEdit: (FappSwapCore.Binding, UInt16, Set<Modifier>) -> String?
        /// Rebinds the row to the new combination, keeping its app.
        let saveShortcutEdit: (FappSwapCore.Binding, UInt16, Set<Modifier>) -> Void
        let removeShortcut: (FappSwapCore.Binding) -> Void
        let removeSnippet: (Snippet) -> Void
        /// Validate-and-save in one call: returns the rejection to show inline, or
        /// nil when saved. The editor stays open on a rejection so nothing typed
        /// is lost.
        let saveSnippet: (SnippetDraft) -> String?
        let savePrefix: (String) -> String?
        let snippetRecoveryNotice: () -> String?
        let isWindowCyclingEnabled: () -> Bool
        let setWindowCycling: (Bool) -> Void
        let isStartAtLoginEnabled: () -> Bool
        let setStartAtLogin: (Bool) -> Void
        let isClipboardEnabled: () -> Bool
        let setClipboardEnabled: (Bool) -> Void
        let clipboardHotkeyDisplay: () -> String
        let validateClipboardHotkey: (UInt16, Set<Modifier>) -> String?
        let saveClipboardHotkey: (UInt16, Set<Modifier>) -> Void
        let retention: () -> RetentionDays
        let selectRetention: (RetentionDays) -> Void
        let revealHistory: () -> Void
        let clearHistory: () -> Void
        let openAccessibilitySettings: () -> Void
    }

    static let width: CGFloat = 420
    static let height: CGFloat = 460

    private let statusItem: NSStatusItem
    private let panel: StatusPanelWindow
    private let tap: HotkeyTap
    let model: StatusPanelModel
    private var keyMonitor: Any?
    /// Same discipline as `ClipboardPanelController.swallowedKeyCodes`: a key-down
    /// consumed by the monitor must have its key-up consumed too, or AppKit beeps.
    private var swallowedKeyCodes: Set<UInt16> = []
    /// True while an alert or the app picker is running modally on the panel's
    /// behalf. Losing key status to a modal must not close the panel.
    private var isPresentingModal = false

    var isVisible: Bool { panel.isVisible }

    init(tap: HotkeyTap,
         snippets: @escaping () -> (prefix: String, snippets: [Snippet]),
         bindings: @escaping () -> [FappSwapCore.Binding],
         clipboard: ClipboardActions,
         settings: SettingsActions,
         reminders: ReminderActions,
         activate: @escaping (String) -> Void,
         updateAction: @escaping () -> Void) {
        self.tap = tap
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = StatusPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // Appears over a full-screen app and on whichever Space is current — the
        // app's whole point is not caring which Space you are on.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        model = StatusPanelModel(
            tap: tap, snippets: snippets, bindings: bindings, clipboard: clipboard,
            settings: settings, reminders: reminders, activate: activate,
            updateAction: updateAction)

        super.init()

        // Set after init so the model can hand modal work back to the panel.
        model.runPreservingPanel = { [weak self] body in
            guard let self else { body(); return }
            self.runPreservingPanel(body)
        }
        // Recorder editors suspend the tap so an already-bound combination can be
        // typed; every close path resumes it (see `didChangeEditor` and `close`).
        model.onEditorChange = { [weak self] editor in self?.didChangeEditor(editor) }

        statusItem.button?.image = MenuBarIcon.listening
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        panel.contentView = NSHostingView(rootView: StatusPanelView(model: model).ignoresSafeArea())

        // Clicking anywhere outside a non-activating panel makes it resign key:
        // that is "click outside closes" — unless the click is a modal we opened,
        // or the status button itself (whose action must see the panel still
        // visible so its toggle closes rather than close-then-reopen).
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isPresentingModal, !self.mouseIsOverStatusButton else { return }
            self.close()
        }
        refreshStatus()
    }

    @objc private func statusItemClicked() { toggle() }

    func toggle() { panel.isVisible ? close() : open() }

    func open() {
        model.reload()
        positionUnderStatusItem()
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
        logger.notice("status panel opened")
    }

    func close() {
        guard panel.isVisible else { return }
        model.activeEditor = nil  // resumes the tap via didChangeEditor
        swallowedKeyCodes.removeAll()
        panel.orderOut(nil)
        logger.notice("status panel closed")
    }

    /// Runs a modal (alert, app picker) without the resulting loss of key status
    /// closing the panel, and takes key back afterwards.
    func runPreservingPanel(_ body: () -> Void) {
        isPresentingModal = true
        body()
        isPresentingModal = false
        if panel.isVisible { panel.makeKeyAndOrderFront(nil) }
    }

    private var mouseIsOverStatusButton: Bool {
        guard let window = statusItem.button?.window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    private func positionUnderStatusItem() {
        guard let buttonWindow = statusItem.button?.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            panel.center()
            return
        }
        let anchor = buttonWindow.frame
        var x = anchor.midX - Self.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - Self.width - 8)
        let y = anchor.minY - Self.height - 5
        panel.setFrame(NSRect(x: x, y: y, width: Self.width, height: Self.height), display: true)
    }

    private func didChangeEditor(_ editor: StatusPanelModel.ActiveEditor?) {
        // Unconditional resume when no recorder is open: a tap left suspended is a
        // silently dead app (the rule the deleted task dialogs enforced too).
        tap.isSuspended = editor?.suspendsTap == true
    }

    // MARK: - Keys (⎋ closes the editor first, then the panel)

    /// Installed once and kept for the controller's lifetime, like
    /// `ClipboardPanelController`'s: a monitor torn down on close can never see
    /// the trailing key-up of the ⎋ that closed the panel, and AppKit beeps.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyUp {
                return self.swallowedKeyCodes.remove(event.keyCode) != nil ? nil : event
            }
            guard self.panel.isKeyWindow, event.keyCode == 53 else { return event }  // ⎋
            if self.model.activeEditor != nil {
                self.model.activeEditor = nil
            } else {
                self.close()
            }
            self.swallowedKeyCodes.insert(event.keyCode)
            return nil
        }
    }

    // MARK: - Status line and update state

    /// Same three-way health logic `MenuBarController.refreshStatus` had: a healthy
    /// tap that is suspended for key recording is not a permission problem and must
    /// not be reported as one.
    func refreshStatus() {
        let healthy = tap.isRunning
        if !healthy {
            model.statusLine = .noPermission
        } else if !tap.isListening {
            model.statusLine = .recording
        } else if !model.settings.isClipboardEnabled() {
            model.statusLine = .active(clipboard: false, paused: false)
        } else if model.clipboard.isPaused() {
            model.statusLine = .active(clipboard: true, paused: true)
        } else {
            model.statusLine = .active(clipboard: true, paused: false)
        }
        // The image says permission, not pause: a suspended-for-recording tap is
        // healthy, and the footer line carries that state on its own.
        statusItem.button?.image = healthy ? MenuBarIcon.listening : MenuBarIcon.noPermission
    }

    func refreshUpdateState(_ state: UpdateController.State) {
        model.updateState = state
    }
}
