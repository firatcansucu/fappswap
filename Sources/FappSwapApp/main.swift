import AppKit
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "main")

// `launchctl bootstrap` with `RunAtLoad: true` starts the login-item copy
// immediately, not just at next login (see `LoginItem.enable()`), so ticking
// "Start at login" while already running would otherwise spawn a duplicate
// alongside this instance — and duplicate `CGEventTap`s would both swallow and
// both activate. Bail out before installing anything if another instance with
// this bundle ID is already running; launchd's `KeepAlive: false` means it will
// not try to restart the copy that exits here.
let bundleID = Bundle.main.bundleIdentifier ?? LoginItem.label
let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if alreadyRunning {
    logger.notice("another instance of \(bundleID, privacy: .public) is already running — exiting")
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Accessory: no Dock icon, no Cmd-Tab entry. LSUIElement in the bundle does the
// same thing; this covers running the bare executable during development.
application.setActivationPolicy(.accessory)
application.run()
