import AppKit
import ApplicationServices
import FappSwapCore
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "WindowCycler")

/// ⌥Tab: brings the frontmost app's bottom-most window to the front, so
/// repeated presses cycle through all of its windows — including windows on
/// other Spaces and in full screen, which is what ⌘` cannot reach.
///
/// Two paths, mirroring `AppActivator`'s fast path/escalation split, and for
/// the same underlying reason: the Accessibility API cannot see a window on
/// another Space at all — off-Space windows are simply absent from
/// `kAXWindowsAttribute` (spikes/raisewindow.swift) — so anything cross-Space
/// is delegated to the app itself via AppleScript, where window ordering is
/// in-process and Space-blind. Raising within the current Space stays on the
/// fast AX path with no osascript round trip.
///
/// Space membership is read through two private symbols (`CGSCopySpacesForWindows`
/// and friends from SkyLight, `_AXUIElementGetWindow` from HIServices), both
/// read-only and resolved via `dlsym` with a graceful fallback: if either
/// vanishes in an OS update, cycling degrades to current-Space-only or to the
/// AppleScript path rather than breaking. The *mutating* CGS calls are known
/// dead ends and are not used (see the constraints notes in git history —
/// they return success codes while doing nothing).
enum WindowCycler {
    private typealias CGSConnectionID = Int32
    private typealias AXGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func skyLightSymbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let skyLight, let symbol = dlsym(skyLight, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static let mainConnectionID = skyLightSymbol(
        "CGSMainConnectionID", (@convention(c) () -> CGSConnectionID).self)
    private static let copyManagedDisplaySpaces = skyLightSymbol(
        "CGSCopyManagedDisplaySpaces", (@convention(c) (CGSConnectionID) -> CFArray?).self)
    private static let copySpacesForWindows = skyLightSymbol(
        "CGSCopySpacesForWindows", (@convention(c) (CGSConnectionID, Int32, CFArray) -> CFArray?).self)

    private static let axGetWindow: AXGetWindow? = {
        guard
            let handle = dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
                RTLD_NOW),
            let symbol = dlsym(handle, "_AXUIElementGetWindow")
        else { return nil }
        return unsafeBitCast(symbol, to: AXGetWindow.self)
    }()

    /// Entry point, called on the main thread from the tap's ⌥Tab match.
    static func cycle() {
        let requestGeneration = AppActivator.bumpGeneration()
        guard let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier
        else {
            logger.notice("no frontmost application to cycle")
            return
        }

        switch decision(forPID: app.processIdentifier) {
        case .nothingToCycle:
            logger.notice(
                "nothing to cycle for \(bundleID, privacy: .public): fewer than two windows")
        case .raise(let windowID):
            raiseOnCurrentSpace(
                windowID: windowID, app: app, bundleID: bundleID,
                requestGeneration: requestGeneration)
        case .escalate(let windowID):
            escalate(
                windowID: windowID, app: app, bundleID: bundleID,
                requestGeneration: requestGeneration)
        }
    }

    /// Builds the window set — every real window with its Space memberships
    /// and on-screen state — plus the focused window (the front of the
    /// on-screen z-order), and hands the choice to `WindowCycle.decide`.
    /// Ordering beyond "who is in front" is never taken from the full
    /// CGWindowList — its order is static, not z-order
    /// (spikes/ordertest.swift). Without the SkyLight symbols there is no
    /// Space information, so off-screen windows are ignored — cycling still
    /// works, just not across Spaces.
    private static func decision(forPID pid: pid_t) -> WindowCycle.Decision {
        let onScreen = windowIDs(forPID: pid, onCurrentSpaceOnly: true)
        let focused = onScreen.first
        guard let mainConnectionID, let copyManagedDisplaySpaces, let copySpacesForWindows,
            let displays = copyManagedDisplaySpaces(mainConnectionID()) as? [[String: Any]],
            let currentSpace = (displays.first?["Current Space"] as? [String: Any])?["ManagedSpaceID"]
                as? Int
        else {
            logger.error("SkyLight unavailable; cycling is limited to the current Space")
            let windows = onScreen.map {
                WindowCycle.Window(id: $0, spaceIDs: [1], isOnScreen: true)
            }
            return WindowCycle.decide(windows: windows, focusedWindowID: focused, currentSpace: 1)
        }
        let connection = mainConnectionID()
        let onScreenSet = Set(onScreen)
        let windows = windowIDs(forPID: pid, onCurrentSpaceOnly: false).map { id in
            WindowCycle.Window(
                id: id,
                spaceIDs: (copySpacesForWindows(connection, 0x7, [Int(id)] as CFArray) as? [UInt64])
                    ?? [],
                isOnScreen: onScreenSet.contains(id))
        }
        return WindowCycle.decide(
            windows: windows, focusedWindowID: focused, currentSpace: UInt64(currentSpace))
    }

    /// Layer-0, non-transparent windows owned by `pid`. The alpha filter
    /// drops full-screen toolbar companion windows, which are layer 0 and
    /// carry a Space but are invisible and unraisable (alpha 0, measured in
    /// spikes/wprops.swift). With `.optionOnScreenOnly` the order is live
    /// z-order, front to back; the full list's order means nothing.
    private static func windowIDs(forPID pid: pid_t, onCurrentSpaceOnly: Bool) -> [CGWindowID] {
        var options: CGWindowListOption = [.excludeDesktopElements]
        if onCurrentSpaceOnly {
            options.insert(.optionOnScreenOnly)
        }
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return list.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                (window[kCGWindowLayer as String] as? Int) == 0,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let number = window[kCGWindowNumber as String] as? Int
            else { return nil }
            return CGWindowID(number)
        }
    }

    /// Fast path: the target is on this Space, so AX can see it. Sub-ms per
    /// call, safe on the main thread. Falls through to the escalation if AX
    /// cannot produce the window CG promised — the app itself always can.
    private static func raiseOnCurrentSpace(
        windowID: CGWindowID, app: NSRunningApplication, bundleID: String, requestGeneration: Int
    ) {
        if let axGetWindow {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
                == .success,
                let windows = value as? [AXUIElement]
            {
                for element in windows {
                    var id: CGWindowID = 0
                    guard axGetWindow(element, &id) == .success, id == windowID else { continue }
                    let result = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    guard result == .success else { break }
                    logger.notice(
                        "raised window \(windowID, privacy: .public) of \(bundleID, privacy: .public) on the current Space")
                    if !app.isActive { app.activate() }
                    return
                }
            }
        }
        logger.notice(
            "AX could not raise window \(windowID, privacy: .public) of \(bundleID, privacy: .public); escalating")
        escalate(
            windowID: windowID, app: app, bundleID: bundleID, requestGeneration: requestGeneration)
    }

    /// Cross-Space (or AX-refused) path: the app raises the specific window
    /// itself and activates, pulling that window's Space across. Runs
    /// osascript off the main thread — ~350ms, far too long for the tap's
    /// thread — then settles focus back on the main queue.
    private static func escalate(
        windowID: CGWindowID, app: NSRunningApplication, bundleID: String, requestGeneration: Int
    ) {
        logger.notice(
            "cycling to window \(windowID, privacy: .public) of \(bundleID, privacy: .public) app-side via AppleScript")
        let source = WindowCycle.script(bundleID: bundleID, windowID: windowID)
        DispatchQueue.global(qos: .userInitiated).async {
            let sent = runOSAScript(source, bundleID: bundleID)
            DispatchQueue.main.async {
                guard requestGeneration == AppActivator.generation else {
                    logger.notice(
                        "skipping post-cycle focus settle for \(bundleID, privacy: .public); superseded by a newer request")
                    return
                }
                guard sent else { return }
                settleFocus(
                    app, bundleID: bundleID, requestGeneration: requestGeneration,
                    deadline: .now() + settleBudget)
            }
        }
    }

    /// The Space-switch machinery hands transient focus to Finder after the
    /// animation lands (see AppActivator's history), and a same-app cycle is
    /// not exempt. This is a lighter settle than `AppActivator.pollForFocus`:
    /// there is no landed-gate, because for a same-app cycle "the app has a
    /// window on the current Space" is already true on the Space being left,
    /// so the signal cannot distinguish in-flight from landed. Correct any
    /// drift, require a short stable run, stop at the budget.
    private static let settleInterval: TimeInterval = 0.1
    private static let settleStabilityThreshold = 3
    private static let settleBudget: TimeInterval = 2.5

    private static func settleFocus(
        _ app: NSRunningApplication, bundleID: String, requestGeneration: Int,
        deadline: DispatchTime, consecutiveGoodTicks: Int = 0, correctionCount: Int = 0
    ) {
        guard requestGeneration == AppActivator.generation else {
            logger.notice(
                "stopping post-cycle focus settle for \(bundleID, privacy: .public); superseded by a newer request")
            return
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
            let goodTicks = consecutiveGoodTicks + 1
            if goodTicks >= settleStabilityThreshold {
                logger.notice(
                    "cycle settled on \(bundleID, privacy: .public) after \(correctionCount, privacy: .public) correction(s)")
                return
            }
            guard DispatchTime.now() < deadline else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + settleInterval) {
                settleFocus(
                    app, bundleID: bundleID, requestGeneration: requestGeneration,
                    deadline: deadline, consecutiveGoodTicks: goodTicks,
                    correctionCount: correctionCount)
            }
            return
        }
        guard DispatchTime.now() < deadline else {
            logger.error(
                "gave up settling focus after a cycle of \(bundleID, privacy: .public) (\(correctionCount, privacy: .public) corrections)")
            return
        }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + settleInterval) {
            settleFocus(
                app, bundleID: bundleID, requestGeneration: requestGeneration, deadline: deadline,
                consecutiveGoodTicks: 0, correctionCount: correctionCount + 1)
        }
    }

    /// Runs a script through osascript and returns whether it exited 0. Must
    /// be called off the main thread. Same shape as `AppActivator`'s runner —
    /// including the 5s terminate backstop — but takes an arbitrary script
    /// rather than being welded to `activate`.
    private static func runOSAScript(_ source: String, bundleID: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            logger.error(
                "Failed to launch osascript to cycle \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }

        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                logger.error(
                    "osascript cycling \(bundleID, privacy: .public) timed out after 5s; terminating")
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 5, execute: timeoutWorkItem)

        process.waitUntilExit()
        timeoutWorkItem.cancel()

        guard process.terminationStatus == 0 else {
            let stderrText = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger.error(
                "osascript cycling \(bundleID, privacy: .public) exited \(process.terminationStatus, privacy: .public): \(stderrText, privacy: .public)")
            return false
        }
        return true
    }
}
