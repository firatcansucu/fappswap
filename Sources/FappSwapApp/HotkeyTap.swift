import AppKit
import FappSwapCore
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "HotkeyTap")

/// Owns the CGEventTap. Swallows keystrokes that match a binding and passes
/// everything else through untouched.
///
/// The instance must outlive its tap: the C callback holds an unretained pointer
/// back to `self`, with nothing enforcing that lifetime. `start()`, `stop()`, and
/// `reArm()` must all be called from the main thread, since they use
/// `CFRunLoopGetCurrent()` to install and remove the run loop source.
///
/// The tap callback also runs on the main run loop — that is what makes `lookup`,
/// `isSuspended` and `swallowedKeyCodes` safe to touch without locking. It also
/// means any main-thread stall (a modal panel, a spinning beachball) is what
/// causes `.tapDisabledByTimeout`, so every recovery path below must hold.
final class HotkeyTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?
    /// True from `start()` until `stop()`. Lets the watchdog tell a tap that died
    /// apart from one that was deliberately torn down.
    private var wantsRunning = false
    /// Suppresses repeat logging while the tap cannot be created at all.
    private var didLogWatchdogFailure = false
    /// Key codes whose key-down we swallowed, so the matching key-up is swallowed
    /// too even when the modifiers were released first.
    private var swallowedKeyCodes = Set<UInt16>()

    private static let watchdogInterval: TimeInterval = 5

    /// Returns the binding for a keystroke, or nil if there is none.
    var lookup: (UInt16, Set<Modifier>) -> Binding? = { _, _ in nil }
    /// Called on the main thread when a binding matches.
    var onMatch: (Binding) -> Void = { _ in }
    /// Called on the main thread when ⌥Tab is pressed (window cycling).
    var onCycleWindows: () -> Void = {}
    /// ⌥Tab is a reserved binding, checked ahead of the user's table. Set at
    /// launch from the stored preference and kept live by the menu's
    /// `Cycle Windows with ⌥⇥ (Option-Tab)` toggle. Main-thread only, like
    /// `lookup`. Logged because an off toggle makes ⌥Tab look exactly like a
    /// dead tap for one key while everything else works.
    var windowCycleEnabled = true {
        didSet {
            guard windowCycleEnabled != oldValue else { return }
            logger.notice(
                "window cycling \(self.windowCycleEnabled ? "enabled" : "disabled", privacy: .public)")
        }
    }
    /// The clipboard-history combination, reserved ahead of the user's table
    /// like `⌥⇥`. nil while the feature is disabled, so the keystroke passes
    /// through untouched. Main-thread only, like `lookup`. Logged for the same
    /// reason as `windowCycleEnabled`.
    var clipboardHotkey: Hotkey? = Hotkey.clipboardDefault {
        didSet {
            guard clipboardHotkey != oldValue else { return }
            logger.notice("clipboard hotkey is now \(self.clipboardHotkey?.displayKey ?? "off", privacy: .public)")
        }
    }
    /// Called on the main thread when the clipboard hotkey is pressed. Opens
    /// the panel, or closes it if it is already open.
    var onShowClipboard: () -> Void = {}
    /// The reminder combination, reserved ahead of the user's table like the
    /// clipboard hotkey. Never nil: the feature has no off switch, and the menu's
    /// `Add Reminder…` is the fallback if the tap is dead. Main-thread only, like
    /// `lookup`. Logged for the same reason as `windowCycleEnabled`.
    var reminderHotkey: Hotkey = Hotkey.reminderDefault {
        didSet {
            guard reminderHotkey != oldValue else { return }
            logger.notice("reminder hotkey is now \(self.reminderHotkey.displayKey, privacy: .public)")
        }
    }
    /// Called on the main thread when the reminder hotkey is pressed. Opens the
    /// input panel — or, while a reminder card is showing, focuses the card
    /// instead (spec decision 23); `AppDelegate` makes that choice.
    var onReminder: () -> Void = {}
    /// Called on the main thread for every key-down no binding claimed, so the
    /// text expander can watch ordinary typing.
    ///
    /// Never called for our own injected events, and never for a keystroke a
    /// binding swallowed. Auto-repeat *is* reported, unlike `onMatch`: holding a
    /// key genuinely types repeated characters, and the buffer has to reflect that.
    var onUnmatchedKeyDown: (TypedKey) -> Void = { _ in }
    /// Called on the main thread when the tap dies or heals on its own, so the
    /// menu bar can reflect it without polling.
    ///
    /// Single-subscriber: this is one closure property, not a multicast, and
    /// `AppDelegate` already claims it to drive both `menuBar?.refreshStatus()`
    /// and `popMenuOnFirstRunIfNeeded()`. Reassigning it from elsewhere would
    /// silently clobber that and break both. Additional consumers must be chained
    /// through `AppDelegate`'s existing assignment, not attached by overwriting this.
    var onHealthChange: () -> Void = {}

    /// While true the tap passes every event through — used during key recording,
    /// so an already-bound combination can be typed into the recorder.
    ///
    /// Not cleared on change: suspension does not interrupt event delivery, so a
    /// key-up whose key-down was swallowed still reaches the balance check below.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            // Logged because this single flag silently disables *both* hotkeys and
            // text expansion, produces no other trace, and stays set for as long
            // as a recorder is open in the status panel — `StatusPanelController`
            // resumes it on every close path, but "everything stopped working"
            // with a healthy tap is otherwise indistinguishable in the log from
            // a dead one.
            logger.notice(
                "isSuspended=\(self.isSuspended, privacy: .public) — hotkeys and expansion \(self.isSuspended ? "paused" : "resumed", privacy: .public)")
            onHealthChange()
        }
    }

    var isRunning: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// `isRunning` is the health signal the watchdog acts on; this is for display,
    /// so the menu bar cannot claim to be listening while suspended for recording.
    var isListening: Bool { isRunning && !isSuspended }

    @discardableResult
    func start() -> Bool {
        wantsRunning = true
        let ok = install()
        if !ok {
            logger.error("tapCreate failed — likely missing Accessibility permission")
        }
        startWatchdog()
        onHealthChange()
        return ok
    }

    func stop() {
        wantsRunning = false
        watchdog?.invalidate()
        watchdog = nil
        teardown()
        logger.notice("tap stopped deliberately")
    }

    /// Rebuilds the tap from scratch. Called after wake and by the watchdog.
    /// Always rebuilds rather than trusting `CGEvent.tapIsEnabled`, which can
    /// report a tap the WindowServer has already dropped across sleep.
    @discardableResult
    func reArm() -> Bool {
        logger.notice("reArm entered, tapIsEnabled=\(self.isRunning, privacy: .public)")
        let ok = start()
        logger.notice("reArm finished, succeeded=\(ok, privacy: .public)")
        return ok
    }

    /// Creates the tap and installs it on the current run loop, replacing any
    /// existing one. Silent on failure — callers decide how loudly to complain.
    private func install() -> Bool {
        teardown()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        tap = newTap
        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        didLogWatchdogFailure = false
        logger.notice("tap created and enabled")
        return true
    }

    private func teardown() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
        swallowedKeyCodes.removeAll()
    }

    /// macOS can drop a tap across sleep without ever calling the callback, and
    /// `tapCreate` can fail transiently right after wake. Without this, one failed
    /// rebuild leaves the app silently dead until the user relaunches it.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            guard let self, self.wantsRunning, !self.isRunning else { return }
            if self.install() {
                logger.notice("watchdog rebuilt a dead tap")
            } else if !self.didLogWatchdogFailure {
                logger.error("watchdog found a dead tap and cannot rebuild it")
                self.didLogWatchdogFailure = true
            }
            self.onHealthChange()
        }
        RunLoop.current.add(timer, forMode: .common)
        watchdog = timer
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        // macOS disables taps that run too slowly or on some input transitions.
        // Without this the app silently stops working.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let reason = type == .tapDisabledByTimeout ? "timeout" : "userInput"
            logger.error("tap disabled by system, reason=\(reason, privacy: .public)")
            swallowedKeyCodes.removeAll()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if CGEvent.tapIsEnabled(tap: tap) {
                    logger.notice("tap re-enabled in place")
                    return passthrough
                }
            }
            // Rebuilding here would be re-entrant: `teardown()` invalidates the
            // very Mach port whose callback is running, and removes the run loop
            // source the run loop is dispatching from. Defer to the next turn.
            logger.error("re-enable did not take — scheduling a rebuild")
            DispatchQueue.main.async { self.reArm() }
            return passthrough
        }

        // Our own injected backspaces and ⌘V come back through this tap. Feeding
        // them to the expander would append the replacement to the buffer and
        // could re-trigger the same snippet — a feedback loop. Checked ahead of
        // everything else because these events must not touch any state here.
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticKey.eventMarker {
            return passthrough
        }

        // A key-up is swallowed if and only if its key-down was, so the focused app
        // never sees half a pair. Checked ahead of `isSuspended` and the binding
        // lookup, because the modifiers may have been released first, a recording
        // dialog may have opened, or the binding may have been removed since the
        // key went down.
        if type == .keyUp {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return swallowedKeyCodes.remove(keyCode) == nil ? passthrough : nil
        }

        guard !isSuspended, type == .keyDown else { return passthrough }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Modifier.set(from: event.flags)

        // ⌥Tab (kVK_Tab = 48) cycles the frontmost app's windows. Reserved
        // ahead of the user's bindings, swallowed and auto-repeat-guarded
        // exactly like one — holding the key must not queue up a burst of
        // osascript escalations.
        if windowCycleEnabled, keyCode == 48, modifiers == [.option] {
            swallowedKeyCodes.insert(keyCode)
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                logger.notice("matched ⌥⇥ -> window cycle")
                DispatchQueue.main.async { self.onCycleWindows() }
            }
            return nil
        }

        // Clipboard history. Reserved ahead of the user's bindings, swallowed
        // and auto-repeat-guarded like ⌥⇥ — holding the key must toggle the
        // panel once, not flicker it.
        if let hotkey = clipboardHotkey, hotkey.matches(keyCode: keyCode, modifiers: modifiers) {
            swallowedKeyCodes.insert(keyCode)
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                logger.notice("matched \(hotkey.displayKey, privacy: .public) -> clipboard history")
                DispatchQueue.main.async { self.onShowClipboard() }
            }
            return nil
        }

        // Reminders. Same reserved-slot treatment as the clipboard hotkey, and
        // checked after it so a combination that is somehow both is reported the
        // way `HotkeyValidation` orders them.
        if reminderHotkey.matches(keyCode: keyCode, modifiers: modifiers) {
            swallowedKeyCodes.insert(keyCode)
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                logger.notice("matched \(self.reminderHotkey.displayKey, privacy: .public) -> reminder")
                DispatchQueue.main.async { self.onReminder() }
            }
            return nil
        }

        guard let binding = lookup(keyCode, modifiers) else {
            let typed = TypedKey.classify(
                keyCode: keyCode, modifiers: modifiers, text: Self.unicodeString(from: event))
            // Dispatched rather than called inline for the same reason `onMatch`
            // is: the handler posts events, and doing that from inside the
            // callback risks re-entrant delivery.
            DispatchQueue.main.async { self.onUnmatchedKeyDown(typed) }
            return passthrough
        }

        swallowedKeyCodes.insert(keyCode)
        // Auto-repeat still has to be swallowed or holding the key types the
        // character, but one press means one activation, so it must not re-fire.
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            // `.notice`, not `.debug`: this is the one line that proves the tap
            // saw the keystroke and matched it, and `.debug` is not persisted.
            // It names the binding, never what was typed.
            logger.notice("matched \(binding.displayKey, privacy: .public) -> \(binding.bundleID, privacy: .public)")
            DispatchQueue.main.async { self.onMatch(binding) }
        }
        return nil
    }

    /// The characters this event would type, or "" if it types nothing.
    /// Layout-independent, which is what makes a `§` prefix work at all.
    private static func unicodeString(from event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: min(length, buffer.count))
    }
}

private let hotkeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
