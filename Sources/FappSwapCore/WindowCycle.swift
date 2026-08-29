/// Decides what ⌥Tab should do with the frontmost app's windows.
///
/// Cycling walks a stable circular order — ascending window ID — starting
/// from the focused window, so repeated presses visit every real window
/// exactly once per lap, wherever it lives. Two earlier policies died to
/// platform traps (both preserved in the spikes): ordering by the full
/// CGWindowList is wrong because that list's order is static, not z-order
/// (spikes/ordertest.swift); and "raise the app's bottom-most window" ping-
/// pongs between Spaces when windows are split across them, because off-Space
/// windows always sort behind on-Space ones in the app's own ordering.
///
/// The `raise`/`escalate` split mirrors `AppActivator`'s fast path/escalation
/// shape, and exists for the same reason: the Accessibility API cannot see
/// (let alone raise) a window on another Space — off-Space windows are simply
/// absent from `kAXWindowsAttribute` — so anything cross-Space has to be done
/// by the app itself via AppleScript, which addresses its windows by the same
/// ID CGWindowList reports (spikes/raisewindow.swift, verified against both
/// Firefox's generic Cocoa suite and Finder's custom one).
public enum WindowCycle {
    /// One window of the frontmost app. `spaceIDs` empty means the
    /// WindowServer places it on no Space — a phantom (Firefox keeps
    /// several), never a cycle target. Callers must also pre-filter alpha-0
    /// windows (full-screen toolbar companions), which do carry a Space.
    public struct Window: Equatable {
        public let id: UInt32
        public let spaceIDs: [UInt64]
        public let isOnScreen: Bool

        public init(id: UInt32, spaceIDs: [UInt64], isOnScreen: Bool) {
            self.id = id
            self.spaceIDs = spaceIDs
            self.isOnScreen = isOnScreen
        }
    }

    public enum Decision: Equatable {
        /// Fewer than two reachable windows — nothing to cycle between.
        case nothingToCycle
        /// The target is on the current Space: AXRaise it, no AppleScript
        /// round trip needed.
        case raise(windowID: UInt32)
        /// The target is on another Space; only the app itself can raise it.
        case escalate(windowID: UInt32)
    }

    /// - Parameters:
    ///   - focusedWindowID: the front-most on-screen window, or nil when the
    ///     app has nothing on screen here (e.g. full screen elsewhere).
    public static func decide(
        windows: [Window], focusedWindowID: UInt32?, currentSpace: UInt64
    ) -> Decision {
        // Eligible: real (has a Space), and either visible here or living on
        // another Space. Off-screen but homed on the current Space means
        // minimized here — skipped, cycling does not unminimize.
        let eligible = windows
            .filter { !$0.spaceIDs.isEmpty && ($0.isOnScreen || !$0.spaceIDs.contains(currentSpace)) }
            .sorted { $0.id < $1.id }
        guard let first = eligible.first else { return .nothingToCycle }
        if eligible.count == 1 {
            // A lone remote window is still worth jumping to; a lone local
            // one is already in front.
            return first.isOnScreen ? .nothingToCycle : .escalate(windowID: first.id)
        }
        // The next window after the focused one in circular ID order. An
        // unknown focus (nothing on screen, or a window the filters rejected,
        // like a sheet) starts the lap from the beginning.
        let target: Window
        if let focusedWindowID, eligible.contains(where: { $0.id == focusedWindowID }) {
            target = eligible.first { $0.id > focusedWindowID } ?? first
        } else {
            target = first
        }
        return target.isOnScreen ? .raise(windowID: target.id) : .escalate(windowID: target.id)
    }

    /// AppleScript asking the app to bring one specific window to the front,
    /// then activate — which raises that window and pulls its Space across,
    /// including into full screen. The reorder must precede the activate, or
    /// the Apple Event raises whatever was already frontmost.
    public static func script(bundleID: String, windowID: UInt32) -> String {
        """
        tell application id \(AppleScript.quoted(bundleID))
            set index of window id \(windowID) to 1
            activate
        end tell
        """
    }
}
