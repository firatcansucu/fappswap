import AppKit
import ApplicationServices
import FappSwapCore
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "AppActivator")

enum AppActivator {
    private static let bindingModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]

    /// Bumped on every call to `activate(bundleID:)` (always on the main
    /// thread — see `HotkeyTap`'s doc comment on `onMatch`). Captured by a
    /// fresh launch, or by an Apple-Event escalation, before it starts
    /// waiting; if a newer call has bumped it by the time the wait finishes,
    /// the user has pressed a different binding in the meantime and the
    /// stale request must not steal focus back from whatever they asked for
    /// instead.
    ///
    /// Shared with `WindowCycler`: a ⌥Tab cycle and an app binding must
    /// supersede *each other's* focus polls too, or the two poll loops fight
    /// over focus for seconds. Internal (not private) and bumped only through
    /// `bumpGeneration()`, always on the main thread.
    private(set) static var generation = 0

    /// Starts a new activation request, invalidating every in-flight focus
    /// poll (this file's and `WindowCycler`'s). Main thread only.
    static func bumpGeneration() -> Int {
        generation &+= 1
        return generation
    }

    /// Brings the app to the front, launching it if it is not running.
    /// Does nothing when the app is already frontmost.
    static func activate(bundleID: String) {
        let requestGeneration = bumpGeneration()
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let running = instances.first(where: { $0.activationPolicy == .regular }) ?? instances.first {
            finishActivation(
                running, bundleID: bundleID, requestGeneration: requestGeneration, reason: "already running")
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.error("No installed application found for bundle ID \(bundleID, privacy: .public)")
            return
        }
        launchWhenModifiersClear(url: url, bundleID: bundleID, requestGeneration: requestGeneration)
    }

    /// Apps read live hardware modifier state at startup — Firefox opens in
    /// troubleshoot mode if Option is down, for example. `HotkeyTap` swallowing the
    /// keystroke does not change that, so wait for the user to let go before
    /// launching. Capped at ~1 second so a stuck or deliberately held key cannot
    /// block the launch forever.
    private static func launchWhenModifiersClear(
        url: URL, bundleID: String, requestGeneration: Int, attemptsRemaining: Int = 50
    ) {
        // `.hidSystemState` reflects genuine hardware input; `.combinedSessionState`
        // also folds in any software-posted (synthetic) events from other
        // processes in the session, which is not what "is the key physically
        // still down" means. See CGEventSource.h.
        let held = CGEventSource.flagsState(.hidSystemState).intersection(bindingModifiers)
        if !held.isEmpty, attemptsRemaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                launchWhenModifiersClear(
                    url: url, bundleID: bundleID, requestGeneration: requestGeneration,
                    attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }
        if !held.isEmpty {
            logger.notice("launching \(bundleID, privacy: .public) with modifiers still held")
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            if let error {
                logger.error("Failed to launch \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let app else { return }
            // `openApplication`'s `activates` default is true, so this launch
            // already made `app` frontmost — but at launch time, before it has
            // restored any windows. With no window yet, there is nothing for
            // macOS's "switch to a Space with open windows for the application"
            // behavior to follow, so the Space never changes (see
            // spikes/launchtimeline.swift). Firefox then finishes restoring its
            // window on its original Space, leaving the user stranded looking at
            // whatever they had in front. Wait for the app to actually produce a
            // window — anywhere, not necessarily on this Space — and then run it
            // through the same fast-activate-or-escalate decision every other
            // call goes through.
            DispatchQueue.main.async {
                waitForWindowThenActivate(
                    app, bundleID: bundleID, requestGeneration: requestGeneration,
                    deadline: .now() + 5)
            }
        }
    }

    /// Polls until `app` reports finished-launching *and* has produced a window
    /// somewhere — not necessarily on the current Space, just anywhere — or the
    /// deadline passes, then hands off to `finishActivation`.
    ///
    /// `isFinishedLaunching` alone is not enough: it reflects Cocoa's launch
    /// sequence (Info.plist processing, main nib, `applicationDidFinishLaunching`),
    /// which for an app like Firefox that restores windows asynchronously can
    /// flip to true before any window exists — the same race this fix is
    /// working around, just moved slightly later. Checking for an actual window
    /// owned by the launched process (via `CGWindowListCopyWindowInfo` without
    /// `.optionOnScreenOnly`, since the window may be restoring onto a Space
    /// other than the current one) confirms there is something to act on.
    /// Measured window-appearance time was ~785ms (spikes/launchtimeline.swift),
    /// so poll every 50ms rather than sleep a fixed amount; the 5s deadline
    /// exists because a cold launch (or an app with no windows at all) must not
    /// hang this forever — past it we proceed anyway on a best-effort basis.
    private static func waitForWindowThenActivate(
        _ app: NSRunningApplication, bundleID: String, requestGeneration: Int, deadline: DispatchTime
    ) {
        let ready = app.isFinishedLaunching && hasWindow(forPID: app.processIdentifier, onCurrentSpaceOnly: false)
        let timedOut = DispatchTime.now() >= deadline
        guard ready || timedOut else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                waitForWindowThenActivate(
                    app, bundleID: bundleID, requestGeneration: requestGeneration, deadline: deadline)
            }
            return
        }

        // The user pressed a binding meaning "take me to this app". Completing
        // that intent a moment later, once the window exists, is correct even
        // if some time has passed. But if they have since pressed a *different*
        // binding, that later press is the current intent, and re-activating
        // this stale launch would steal focus back out from under them.
        guard requestGeneration == generation else {
            logger.notice(
                "skipping post-launch activation of \(bundleID, privacy: .public); superseded by a newer request")
            return
        }

        if timedOut, !ready {
            logger.notice(
                "timed out waiting for \(bundleID, privacy: .public) to show a window; activating anyway")
        }
        finishActivation(app, bundleID: bundleID, requestGeneration: requestGeneration, reason: "post-launch")
    }

    /// The common-path decision: is a plain `activate()` enough, or does this
    /// need the Apple Event escalation to pull the Space across first?
    ///
    /// The current-Space window test MUST run before any `isActive`/frontmost
    /// check, not after. `NSRunningApplication.isActive` answers "is this the
    /// frontmost app", which is not the same question as "can the user see it" —
    /// `NSWorkspace.openApplication`'s `activates: true` default makes a freshly
    /// launched app frontmost before it has restored any window, so a fresh
    /// launch onto another Space is `isActive == true` while completely
    /// invisible. An earlier version of this function checked `!app.isActive`
    /// first and returned early in exactly that state, which made the escalation
    /// below unreachable for a launch-onto-another-Space and left the user
    /// keyboard-focused on an app they could not see, with no Automation prompt
    /// ever firing (see spikes/launchtimeline.swift and spikes/strategies.swift,
    /// which measured `activate()` as a no-op with no Space switch whenever the
    /// app had no window on the current Space — regardless of `isActive`).
    /// `isActive` is only safe to consult once we already know there is a window
    /// here for it to mean anything.
    private static func finishActivation(
        _ app: NSRunningApplication, bundleID: String, requestGeneration: Int, reason: String
    ) {
        guard hasWindow(forPID: app.processIdentifier, onCurrentSpaceOnly: true) else {
            // No window on the current Space — on another Space, or launched
            // but not yet restored one here. Escalate regardless of isActive;
            // frontmost-but-invisible is precisely the state this must catch.
            logger.notice(
                "\(reason, privacy: .public): no window on current Space for \(bundleID, privacy: .public); escalating via Apple Event")
            activateAcrossSpaces(app, bundleID: bundleID, requestGeneration: requestGeneration)
            return
        }
        guard !app.isActive else {
            // Window is on the current Space and it's already frontmost:
            // genuinely nothing to do.
            return
        }
        logger.notice(
            "\(reason, privacy: .public): fast-activating \(bundleID, privacy: .public) — window already on current Space")
        app.activate()
    }

    /// Pulls the target app's Space across with an Apple Event, then takes
    /// focus once it has had a moment to settle.
    ///
    /// `spikes/osathenfocus.swift` established both halves are needed: the
    /// Apple Event alone (`tell application id "..." to activate`) switched the
    /// Space in ~302ms by making the target app raise its own window, but did
    /// not reliably take keyboard focus — on a fresh launch the Space switched
    /// while Finder stayed frontmost. Following it with `NSRunningApplication.
    /// activate()` fixed that, because by then the target is genuinely inactive
    /// and there is a real transition for macOS to follow (the same reason a
    /// bare `activate()` fails when called on an already-active app).
    ///
    /// The send itself must happen off the main thread — it takes ~343ms
    /// (`spikes/aethread.swift`), and this code runs on the same main thread
    /// `HotkeyTap`'s CGEventTap callback runs on, where blocking that long
    /// would risk `.tapDisabledByTimeout`. `generation`, `app.isActive`, and
    /// `app.activate()` are only ever touched back on the main queue.
    private static func activateAcrossSpaces(
        _ app: NSRunningApplication, bundleID: String, requestGeneration: Int
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let sent = sendActivateAppleEvent(bundleID: bundleID)
            DispatchQueue.main.async {
                guard requestGeneration == generation else {
                    logger.notice(
                        "skipping post-Apple-Event activation of \(bundleID, privacy: .public); superseded by a newer request")
                    return
                }
                guard sent else {
                    // osascript failed or timed out — see sendActivateAppleEvent's
                    // logging for why. Degrade to a plain activate() — no Space
                    // switch, but the user still ends up focused on the right app
                    // once they find it, rather than the request silently doing
                    // nothing.
                    if !app.isActive { app.activate() }
                    return
                }
                // A successful exit means osascript's own Apple Event round trip
                // has completed, but that is not the same thing as the Space
                // switch having landed. Measured directly from a user's log:
                // osascript can make the target `frontmostApplication` while it
                // is STILL on the other Space (observed at 488ms), well before
                // the WindowServer's Space-switch animation actually lands and
                // macOS reassigns focus on arrival — typically back to Finder
                // (spikes/osathenfocus.swift). A poll that treats "frontmost"
                // alone as success stops right there, declares victory, and
                // leaves nothing running to catch the focus loss that follows.
                // `pollForFocus` requires the switch to have landed first — see
                // its doc comment for the two-part exit condition.
                pollForFocus(
                    app, bundleID: bundleID, requestGeneration: requestGeneration,
                    deadline: .now() + focusPollBudget)
            }
        }
    }

    /// How often `pollForFocus` checks, how many consecutive good ticks count
    /// as "settled", and how long it keeps trying before giving up on a single
    /// escalation.
    ///
    /// The interval is 100ms — frequent enough to catch the Space switch
    /// settling without hammering `activate()` in a tight loop (explicitly
    /// avoided: repeated `activate()` calls with no gap between them is not
    /// what fixed this in spikes/osathenfocus.swift, spacing did).
    ///
    /// The stability threshold is 5 ticks (500ms of continuously-correct
    /// state) — a single successful observation is not enough. A user's log
    /// showed the *previous* version of this poll exit successfully at 733ms
    /// (switch landed, target frontmost) and still end up with Finder holding
    /// the menu bar moments later: this was the post-launch path, and the
    /// launching app plausibly finishes settling its window (and macOS
    /// reshuffles focus as a result) after that single good sample. Requiring
    /// several consecutive good ticks, and resetting the counter and
    /// re-correcting on any drift, is what actually holds focus rather than
    /// just observing it once. This costs the user nothing extra — the app is
    /// idle and already has focus during that window — so the delay is not
    /// worth trimming to make the logs look faster.
    ///
    /// The budget is 5s, raised again from 3s. 3s had been sized to cover the
    /// Space switch landing (~2s established baseline, see the earlier budget
    /// history in git blame) plus room for roughly one corrective `activate()`
    /// cycle. That is no longer enough: success now additionally requires 500ms
    /// of continuous stability, and a genuinely bumpy launch (a window still
    /// settling, an update-check prompt briefly stealing focus, etc.) can drift
    /// more than once, with each drift resetting the stability counter and
    /// costing another full 500ms to re-settle. 5s gives room for several such
    /// cycles on top of the landing time. This is effectively free from a
    /// responsiveness standpoint — the poll never blocks the main thread or
    /// the event tap, it only reschedules itself on the run loop — so a longer
    /// budget costs nothing but a little extra background nudging in the rare
    /// unstable case, while remaining a hard, finite stop rather than fighting
    /// the user for focus indefinitely.
    private static let focusPollInterval: TimeInterval = 0.1
    private static let focusStabilityThreshold = 5
    private static let focusPollBudget: TimeInterval = 5.0

    /// Polls for `app` to actually hold the menu bar after an Apple-Event
    /// escalation, taking focus back from whatever else has it (typically
    /// Finder — see spikes/osathenfocus.swift) and requiring it to *stay*
    /// held for `focusStabilityThreshold` consecutive ticks before declaring
    /// success, or giving up at the budget.
    ///
    /// The exit condition has two gates, evaluated in order on every tick:
    ///
    /// 1. `hasWindow(forPID:onCurrentSpaceOnly: true)` — has the switch landed
    ///    at all? The target's window only appears on the *current* Space once
    ///    it has. While this is false the switch is still in flight:
    ///    `activate()` would be premature (and is plausibly what produces
    ///    misleadingly-early `frontmostApplication` reads in the first place),
    ///    stability doesn't count, and the tick just reschedules.
    /// 2. Once landed, `frontmostApplication?.bundleIdentifier == bundleID` —
    ///    the same signal the menu bar shows and the one the user judges the
    ///    app by. A match increments a consecutive-good-ticks counter, which
    ///    must reach `focusStabilityThreshold` before the poll declares
    ///    success and stops; a *single* good sample proved insufficient (see
    ///    `focusStabilityThreshold`'s doc comment). A mismatch resets the
    ///    counter to zero and unconditionally triggers a corrective
    ///    `activate()`.
    ///
    /// There is deliberately no exception for "the user might have clicked
    /// somewhere else." An earlier version tried to detect that by comparing
    /// against whatever app was frontmost when the escalation started and
    /// bailing out the moment frontmost became a third value — but that value
    /// is almost always Finder in practice (the exact app the Space-switch
    /// machinery hands transient focus to on its own, per
    /// spikes/osathenfocus.swift), which is neither the target nor whatever
    /// the user had been looking at before pressing the binding. So the guard
    /// bailed out on the very case this whole poll exists to correct, and a
    /// user's log confirmed it: `"stopped correcting focus ... frontmost
    /// changed to com.apple.finder, which looks like deliberate user
    /// action"`, 758ms in, correction loop never completing. Removed. The
    /// accepted tradeoff: if the user deliberately clicks into some other app
    /// during the roughly 1s this poll can run, `activate()` may pull focus
    /// back once before the next `generation` bump (from a fresh binding
    /// press) or the poll's own budget stops it. That is judged better than a
    /// feature that does not work at all.
    private static func pollForFocus(
        _ app: NSRunningApplication, bundleID: String, requestGeneration: Int, deadline: DispatchTime,
        consecutiveGoodTicks: Int = 0, correctionCount: Int = 0
    ) {
        guard requestGeneration == generation else {
            logger.notice(
                "skipping post-Apple-Event focus poll for \(bundleID, privacy: .public); superseded by a newer request")
            return
        }
        guard hasWindow(forPID: app.processIdentifier, onCurrentSpaceOnly: true) else {
            // Switch still in flight — `frontmostApplication` may already
            // (misleadingly) be the target, but there is nothing to correct or
            // count as stable yet, and calling activate() now would be
            // premature.
            guard DispatchTime.now() < deadline else {
                logger.error(
                    "gave up waiting for the Space switch to land for \(bundleID, privacy: .public) after \(correctionCount, privacy: .public) correction(s); menu bar may still show another app (\(focusLogSuffix(), privacy: .public))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + focusPollInterval) {
                pollForFocus(
                    app, bundleID: bundleID, requestGeneration: requestGeneration, deadline: deadline,
                    consecutiveGoodTicks: 0, correctionCount: correctionCount)
            }
            return
        }

        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if frontmostBundleID == bundleID {
            let goodTicks = consecutiveGoodTicks + 1
            guard goodTicks >= focusStabilityThreshold else {
                guard DispatchTime.now() < deadline else {
                    logger.error(
                        "gave up waiting for focus on \(bundleID, privacy: .public) to stabilize after \(correctionCount, privacy: .public) correction(s); menu bar may still show another app (\(focusLogSuffix(), privacy: .public))")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + focusPollInterval) {
                    pollForFocus(
                        app, bundleID: bundleID, requestGeneration: requestGeneration, deadline: deadline,
                        consecutiveGoodTicks: goodTicks, correctionCount: correctionCount)
                }
                return
            }
            if correctionCount > 0 {
                logger.notice(
                    "\(bundleID, privacy: .public) held focus after \(correctionCount, privacy: .public) correction(s) (\(focusLogSuffix(), privacy: .public))")
            } else {
                logger.notice(
                    "\(bundleID, privacy: .public) held focus once the Space switch landed (\(focusLogSuffix(), privacy: .public))")
            }
            return
        }

        guard DispatchTime.now() < deadline else {
            logger.error(
                "gave up taking focus for \(bundleID, privacy: .public) after \(correctionCount, privacy: .public) correction(s); menu bar may still show another app (\(focusLogSuffix(), privacy: .public))")
            return
        }
        logger.notice(
            "Space switch landed for \(bundleID, privacy: .public) but focus drifted away; correcting (attempt \(correctionCount + 1, privacy: .public)) (\(focusLogSuffix(), privacy: .public))")
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + focusPollInterval) {
            pollForFocus(
                app, bundleID: bundleID, requestGeneration: requestGeneration, deadline: deadline,
                consecutiveGoodTicks: 0, correctionCount: correctionCount + 1)
        }
    }

    /// Two independent readings of "who has focus", for diagnosing a future
    /// failure without another rebuild-and-report cycle. Every decision in
    /// `pollForFocus` is made from `NSWorkspace.shared.frontmostApplication`
    /// alone — there had been no proof that it agrees with what the user
    /// actually sees in the menu bar, given how much of this file's history
    /// is exactly that kind of surprise. `axFocusedBundleID()` reads the same
    /// question through the Accessibility API instead (the app already holds
    /// Accessibility permission for `HotkeyTap`'s event tap), as a second,
    /// differently-sourced signal logged alongside the first. If the two ever
    /// disagree in a log, that proves the decision signal itself is
    /// unreliable rather than requiring another guess; this function does not
    /// change what `pollForFocus` decides on.
    private static func focusLogSuffix() -> String {
        let nsworkspaceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        let axBundleID = axFocusedBundleID() ?? "nil"
        return "nsworkspace=\(nsworkspaceBundleID) ax=\(axBundleID)"
    }

    /// The Accessibility API's view of which app is focused, read via the
    /// system-wide element's focused-application attribute rather than
    /// `NSWorkspace`. Returns `nil` on any failure (no Accessibility
    /// permission, no focused application reported, or an unexpected element
    /// type) — this is diagnostic logging only, so a failure here must never
    /// throw or block anything `pollForFocus` decides.
    private static func axFocusedBundleID() -> String? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                system, kAXFocusedApplicationAttribute as CFString, &value) == .success,
              let element = value else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element as! AXUIElement, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Runs `osascript -e 'tell application id "..." to activate'` and returns
    /// whether it exited 0. Must be called off the main thread — this blocks
    /// for the process's lifetime.
    ///
    /// This shells out rather than sending the Apple Event in-process with
    /// `NSAppleEventDescriptor`, despite the ~343ms process-spawn cost that was
    /// the whole reason to avoid it originally. `spikes/aethread.swift` measured
    /// `NSAppleEventDescriptor.sendEvent(.waitForReply)` timing out with -1712
    /// (`errAETimeout`) after the full 8s timeout, identically on the main
    /// thread and on a background queue — so the earlier fix's diagnosis (that
    /// the failure was `.noReply` swallowing a synchronous TCC prompt) was
    /// wrong; the in-process API simply never gets a reply here, on either
    /// thread, for reasons that don't matter for a personal tool when a working
    /// alternative exists. `osascript` targeting the same bundle ID with the
    /// same 'activate' event worked every time it was measured (this spike and
    /// `spikes/strategies.swift`/`spikes/osaonly.swift`/`spikes/osathenfocus.swift`),
    /// in ~343ms, with the Space switching. No TCC Automation prompt was
    /// observed for either mechanism, and no `kTCCServiceAppleEvents` request
    /// appeared in the TCC log — activation events appear not to be
    /// Automation-gated on this machine, so nothing here should assume a prompt
    /// will appear (`NSAppleEventsUsageDescription` stays in the bundle's
    /// `Info.plist` regardless, since a prompt may still appear on another
    /// machine or for a different target app).
    ///
    /// Bounds the wait: `waitUntilExit()` alone has no timeout, so a hung
    /// `osascript` would block this background thread forever. A work item
    /// scheduled ~5s out calls `terminate()` if the process is still running by
    /// then; `waitUntilExit()` returns as soon as the process exits either way
    /// (normally, or via that SIGTERM), and the work item is cancelled
    /// afterward so it can't fire on a process that already exited on its own.
    private static func sendActivateAppleEvent(bundleID: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application id \(AppleScript.quoted(bundleID)) to activate",
        ]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            logger.error(
                "Failed to launch osascript to activate \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }

        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                logger.error("osascript activating \(bundleID, privacy: .public) timed out after 5s; terminating")
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5, execute: timeoutWorkItem)

        process.waitUntilExit()
        timeoutWorkItem.cancel()

        guard process.terminationStatus == 0 else {
            let stderrText = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger.error(
                "osascript activating \(bundleID, privacy: .public) exited \(process.terminationStatus, privacy: .public): \(stderrText, privacy: .public)")
            return false
        }
        return true
    }

    /// `onCurrentSpaceOnly: true` (`.optionOnScreenOnly`) only reports windows
    /// on the current Space — that is exactly the test needed to decide whether
    /// a plain `activate()` has something to follow. `onCurrentSpaceOnly: false`
    /// reports windows anywhere, which is what the launch path needs to know
    /// "has this app produced a window at all yet", regardless of which Space
    /// it landed on.
    private static func hasWindow(forPID pid: pid_t, onCurrentSpaceOnly: Bool) -> Bool {
        var options: CGWindowListOption = [.excludeDesktopElements]
        if onCurrentSpaceOnly {
            options.insert(.optionOnScreenOnly)
        }
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == pid
                && (window[kCGWindowLayer as String] as? Int) == 0
        }
    }
}
