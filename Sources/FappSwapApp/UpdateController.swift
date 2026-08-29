import AppKit
import FappSwapCore
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "Updater")

/// Checks GitHub for a newer release and installs it in place.
///
/// The swap preserves the Accessibility grant because release builds share one
/// Developer ID identity (bundle ID + Team ID), which is what TCC pins the
/// grant to. That also defines the trust rule enforced here: a downloaded
/// bundle is installed only if its Team ID and bundle ID match the running
/// app's. Ad-hoc builds have no Team ID, so the updater silently disables
/// itself for development builds — by design.
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        /// An update to this version is downloaded-checked and one click away.
        case available(String)
        /// Busy; the string is a short human-readable phase for the menu item.
        case working(String)
        case failed(String)
    }

    /// Single-subscriber, like HotkeyTap.onHealthChange. Called on the main thread.
    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    private var pendingUpdate: AvailableUpdate?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.firatcansucu.fappswap.updater", qos: .utility)

    private static let defaultFeed =
        URL(string: "https://api.github.com/repos/firatcansucu/fappswap/releases/latest")!

    /// Testing hook (Task 8): `defaults write com.firatcansucu.fappswap
    /// updateFeedURL <url>` points the checker at a local fake feed.
    private var feedURL: URL {
        UserDefaults.standard.string(forKey: "updateFeedURL").flatMap(URL.init(string:))
            ?? Self.defaultFeed
    }

    private var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // MARK: - Checking

    func startPeriodicChecks() {
        // Only a `swift run` binary is caught here — it has no Info.plist,
        // so there's no version to compare against. An ad-hoc build (from
        // `./scripts/bundle.sh`) does have one, so periodic checks still run
        // for it; `install()`'s Team ID check is what refuses to install
        // anything for a build with no Team ID, not this guard.
        guard currentVersion != nil else {
            logger.notice("updater inactive: no bundle version (development build?)")
            return
        }
        // Not at launch instantly — the tap and menu set up first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.check(userInitiated: false)
        }
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Idle or failed → check now. Available → install. Wired to the menu item.
    func userAction() {
        switch state {
        case .idle, .failed: check(userInitiated: true)
        case .available: install()
        case .checking, .working: break
        }
    }

    private func check(userInitiated: Bool) {
        guard let currentVersion else {
            if userInitiated { setState(.failed("Updates unavailable in this build")) }
            return
        }
        if case .working = state { return }
        setState(.checking)

        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                logger.notice("update check failed: \(error.localizedDescription, privacy: .public)")
                // A failed background check is nobody's problem; a failed
                // manual check deserves an answer in the menu.
                self.setState(userInitiated ? .failed("Couldn't check — try again later") : .idle)
                return
            }
            guard let data,
                  let update = UpdateCheck.availableUpdate(
                      currentVersion: currentVersion, latestReleaseJSON: data)
            else {
                self.setState(.idle)
                logger.notice("update check: up to date (\(currentVersion, privacy: .public))")
                return
            }
            logger.notice("update available: \(update.version, privacy: .public)")
            DispatchQueue.main.async {
                self.pendingUpdate = update
                self.setState(.available(update.version))
            }
        }.resume()
    }

    // MARK: - Installing

    private func install() {
        guard let update = pendingUpdate else { return }

        let bundleURL = Bundle.main.bundleURL
        // App Translocation mounts the app read-only when run from the DMG;
        // there is nothing writable to swap. Cheap string check — fine on main.
        if bundleURL.path.contains("/AppTranslocation/") {
            setState(.failed("Move fappswap to Applications first"))
            return
        }

        // Leave .available synchronously, before the queue hop below, so a
        // second click landing while the Team ID check is still in flight
        // sees .working and falls through userAction()'s no-op branch
        // instead of starting a second, concurrent install racing this one
        // to move the live app bundle.
        setState(.working("Checking…"))

        // SecStaticCodeCreateWithPath/SecCodeCopySigningInformation read and
        // parse the code signature from disk; that's I/O this app can't do
        // on main without risking the event tap. Still fails fast, before
        // any download starts — just off the main thread doing it.
        queue.async { [weak self] in
            guard let self else { return }
            guard let expectedTeam = Self.teamID(of: bundleURL) else {
                // Ad-hoc / unsigned running build: no baseline to verify against.
                self.setState(.failed("Updates unavailable in this build"))
                return
            }

            DispatchQueue.main.async {
                self.setState(.working("Downloading \(update.version)…"))
                URLSession.shared.downloadTask(with: update.zipURL) { [weak self] location, _, error in
                    guard let self else { return }
                    guard let location, error == nil else {
                        logger.error("download failed: \(error?.localizedDescription ?? "no file", privacy: .public)")
                        self.setState(.failed("Download failed — try again"))
                        return
                    }
                    // downloadTask deletes `location` when this callback returns, and the
                    // rest of the work leaves the URLSession queue; move it out first.
                    let zip = FileManager.default.temporaryDirectory
                        .appendingPathComponent("fappswap-update-\(update.version).zip")
                    do {
                        try? FileManager.default.removeItem(at: zip)
                        try FileManager.default.moveItem(at: location, to: zip)
                    } catch {
                        self.setState(.failed("Download failed — try again"))
                        return
                    }
                    self.queue.async {
                        self.verifyAndSwap(zip: zip, update: update,
                                           bundleURL: bundleURL, expectedTeam: expectedTeam)
                    }
                }.resume()
            }
        }
    }

    private func verifyAndSwap(
        zip: URL, update: AvailableUpdate, bundleURL: URL, expectedTeam: String
    ) {
        setState(.working("Verifying \(update.version)…"))
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("fappswap-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: zip) }

        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", "-x", "-k", zip.path, staging.path)
            let newApp = staging.appendingPathComponent("fappswap.app")

            // Trust gate. `--verify --deep --strict` alone only proves the
            // bundle's seal is internally consistent — it passes just as
            // happily on an ad-hoc signature as a Developer ID one. The `-R`
            // requirement is what forces the signing chain up to an actual
            // Apple root and pins it to this running app's own team, so a
            // self-signed bundle asserting the right team/bundle ID in its
            // (otherwise-unverified) metadata can't reach the identity guard
            // below. `run(...)` execs codesign directly with no shell, so the
            // requirement string is one argument as-is — nothing to quote.
            try run("/usr/bin/codesign", "--verify", "--deep", "--strict",
                    "-R=anchor apple generic and certificate leaf[subject.OU] = \(expectedTeam)",
                    newApp.path)
            // Belt and braces: the identity guard below is redundant with the
            // requirement above, but its failure produces the clearer
            // user-facing "verification failed" message and keeps the same
            // shape as before if the requirement string ever needs to change.
            guard Self.teamID(of: newApp) == expectedTeam,
                  Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier
            else {
                logger.error("downloaded bundle failed the identity check; refusing to install")
                try? fm.removeItem(at: staging)
                setState(.failed("Update failed verification — not installed"))
                return
            }

            setState(.working("Installing \(update.version)…"))
            // Swap: old aside, new in. The running executable survives by
            // inode. If the second move fails, put the old one back.
            //
            // The displaced bundle goes next to the live app, not to
            // NSTemporaryDirectory() — that directory lives on the boot
            // volume, so if the app is running from an external volume,
            // moving there would be a slow cross-volume copy instead of an
            // instant rename, and a crash or power loss mid-copy would lose
            // the app with the backup stranded somewhere macOS periodically
            // purges. Sitting beside the app, any leftover from a failed
            // install is also exactly where a user would look for it.
            let old = bundleURL.deletingLastPathComponent()
                .appendingPathComponent("fappswap-old-\(UUID().uuidString).app")
            try fm.moveItem(at: bundleURL, to: old)
            do {
                try fm.moveItem(at: newApp, to: bundleURL)
            } catch {
                try? fm.moveItem(at: old, to: bundleURL)
                throw error
            }
            try? fm.removeItem(at: old)
            try? fm.removeItem(at: staging)
            logger.notice("installed \(update.version, privacy: .public); relaunching")

            DispatchQueue.main.async {
                // Detached so it outlives us; the sleep lets this process exit
                // before `open` looks at the bundle. `asyncAfter`, never sleep
                // — nothing in this app blocks the main thread.
                //
                // The path is passed as `$0`, a positional argument to `sh
                // -c`, rather than interpolated into the command string — a
                // path containing a quote, backtick, `$(`, or backslash would
                // otherwise break or inject into the shell command. `exec`
                // replaces the shell with `open` instead of leaving it around
                // as a stray process once `open` returns.
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c",
                    "sleep 1; exec /usr/bin/open \"$0\"", bundleURL.path]
                try? relaunch.run()
                NSApp.terminate(nil)
            }
        } catch {
            logger.error("update install failed: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: staging)
            setState(.failed("Update failed — nothing was changed"))
        }
    }

    // MARK: - Helpers

    private func setState(_ new: State) {
        if Thread.isMainThread { state = new }
        else { DispatchQueue.main.async { self.state = new } }
    }

    /// Team ID from the code signature, or nil for ad-hoc/unsigned.
    private static func teamID(of url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
                code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Runs a tool and throws on a nonzero exit. Only ever called on `queue`.
    private func run(_ launchPath: String, _ arguments: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "fappswap.updater", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                            "\(launchPath) exited \(p.terminationStatus)"])
        }
    }
}
