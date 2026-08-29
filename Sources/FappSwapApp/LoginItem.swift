import Foundation
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "LoginItem")

enum LoginItemError: LocalizedError {
    case launchctlFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .launchctlFailed(let status):
            return "launchctl exited with status \(status)."
        }
    }
}

enum LoginItem {
    static let label = "com.firatcansucu.fappswap"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Path to the running executable, so the agent launches exactly this build.
    private static var executablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    }

    static func enable() throws {
        logger.notice("resolved executable path: \(executablePath, privacy: .public)")
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)

        // Discard any stale registration first so a repeat `enable()` never reads
        // "already loaded" back from `bootstrap` as a genuine failure below.
        run(["bootout", "gui/\(getuid())/\(label)"])

        let status = run(["bootstrap", "gui/\(getuid())", plistURL.path])
        guard status == 0 else {
            logger.error("bootstrap failed, status=\(status, privacy: .public)")
            do {
                try FileManager.default.removeItem(at: plistURL)
            } catch {
                logger.error(
                    "cleanup after failed bootstrap also failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            throw LoginItemError.launchctlFailed(status: status)
        }
    }

    static func disable() throws {
        // Not-loaded is expected and fine; only a genuine failure to unregister
        // would be worth surfacing, and launchctl gives no reliable way to tell
        // the two apart, so the status is ignored here as before.
        run(["bootout", "gui/\(getuid())/\(label)"])

        // The plist may already be gone (e.g. a previous `disable()` succeeded but
        // the caller retried), which is success, not failure.
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        try FileManager.default.removeItem(at: plistURL)
    }

    /// Runs launchctl and returns its exit status; callers decide which statuses
    /// they care about.
    @discardableResult
    private static func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            logger.error("failed to launch launchctl: \(error.localizedDescription, privacy: .public)")
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
