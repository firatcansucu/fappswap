import AppKit
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "AppInfo")

enum AppInfo {
    /// Display name for a bundle ID, or nil when the app is not installed.
    static func displayName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    enum PickResult {
        case picked(bundleID: String)
        case cancelled
        /// The chosen item is an application by type but has no bundle
        /// identifier, so it can never be bound. Distinguished from `cancelled`
        /// so the UI can say so rather than silently doing nothing.
        case noBundleID(name: String)
    }

    /// Opens a picker restricted to applications.
    static func pickApplication() -> PickResult {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            logger.error("Selected item at \(url.path, privacy: .public) has no bundle identifier")
            return .noBundleID(name: FileManager.default.displayName(atPath: url.path))
        }
        return .picked(bundleID: bundleID)
    }
}
