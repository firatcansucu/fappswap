import AppKit
import FappSwapCore
import SwiftUI

/// The panel's state, snapshotted rather than observed: the tabs read published
/// values that `reload()` refreshes on open and after every action. Nothing here
/// touches a store — the closure structs `StatusPanelController` carries are the
/// only way out.
final class StatusPanelModel: ObservableObject {
    enum PanelTab: String, CaseIterable {
        case shortcuts, snippets, clipboard, reminders, general

        var title: String {
            switch self {
            case .shortcuts: return "Shortcuts"
            case .snippets: return "Snippets"
            case .clipboard: return "Clipboard"
            case .reminders: return "Reminders"
            case .general: return "General"
            }
        }

        var symbol: String {
            switch self {
            case .shortcuts: return "keyboard"
            case .snippets: return "character.cursor.ibeam"
            case .clipboard: return "doc.on.clipboard"
            case .reminders: return "bell"
            case .general: return "gearshape"
            }
        }
    }

    /// One editor open at a time, per the spec's inline-editing rules. The three
    /// key-recording cases suspend the tap so an already-bound combination can be
    /// typed at the recorder instead of firing.
    enum ActiveEditor: Equatable {
        case addShortcut
        case editShortcut(String)  // binding id
        case addSnippet
        case editSnippet(String)  // snippet id
        case prefix
        case clipboardHotkey
        case reminderHotkey

        var suspendsTap: Bool {
            switch self {
            case .addShortcut, .editShortcut, .clipboardHotkey, .reminderHotkey: return true
            case .addSnippet, .editSnippet, .prefix: return false
            }
        }
    }

    enum StatusLine: Equatable {
        case noPermission
        case recording
        case active(clipboard: Bool, paused: Bool)

        var text: String {
            switch self {
            case .noPermission: return "Not active — open Accessibility settings…"
            case .recording: return "Paused while recording a shortcut"
            case .active(false, _): return "Shortcuts and snippets active"
            case .active(true, true): return "Shortcuts and snippets active · clipboard paused"
            case .active(true, false): return "Shortcuts, snippets and clipboard active"
            }
        }
    }

    /// A shortcut row with its display data resolved once per reload, not per frame.
    struct BindingRow: Identifiable {
        let binding: FappSwapCore.Binding
        let appName: String?   // nil = not installed; show the bundle ID in red
        let icon: NSImage?
        var id: String { binding.id }
    }

    private static let tabKey = "statusPanelTab"

    @Published var tab: PanelTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.tabKey) }
    }
    @Published var activeEditor: ActiveEditor? {
        didSet { onEditorChange(activeEditor) }
    }
    @Published var statusLine: StatusLine = .active(clipboard: true, paused: false)
    @Published var updateState: UpdateController.State = .idle

    // Snapshots, refreshed by reload():
    @Published var bindingRows: [BindingRow] = []
    @Published var snippetList: [Snippet] = []
    @Published var prefix: String = ""
    @Published var recoveryNotice: String?
    @Published var windowCycling = true
    @Published var startAtLogin = false
    @Published var clipboardEnabled = true
    @Published var clipboardPaused = false
    @Published var clipboardHotkey = ""
    @Published var retention: RetentionDays = .thirty
    @Published var pendingReminders: [Reminder] = []
    @Published var reminderLog: [Reminder] = []
    @Published var reminderHotkey = ""
    @Published var reminderSound = true

    let clipboard: StatusPanelController.ClipboardActions
    let settings: StatusPanelController.SettingsActions
    let reminders: StatusPanelController.ReminderActions
    let activate: (String) -> Void
    let updateAction: () -> Void
    private let tap: HotkeyTap
    private let snippetsProvider: () -> (prefix: String, snippets: [Snippet])
    private let bindingsProvider: () -> [FappSwapCore.Binding]

    /// Injected by the controller after init.
    var runPreservingPanel: (() -> Void) -> Void = { $0() }
    var onEditorChange: (ActiveEditor?) -> Void = { _ in }

    init(tap: HotkeyTap,
         snippets: @escaping () -> (prefix: String, snippets: [Snippet]),
         bindings: @escaping () -> [FappSwapCore.Binding],
         clipboard: StatusPanelController.ClipboardActions,
         settings: StatusPanelController.SettingsActions,
         reminders: StatusPanelController.ReminderActions,
         activate: @escaping (String) -> Void,
         updateAction: @escaping () -> Void) {
        self.tap = tap
        snippetsProvider = snippets
        bindingsProvider = bindings
        self.clipboard = clipboard
        self.settings = settings
        self.reminders = reminders
        self.activate = activate
        self.updateAction = updateAction
        tab = PanelTab(rawValue: UserDefaults.standard.string(forKey: Self.tabKey) ?? "") ?? .shortcuts
    }

    /// Snapshots everything the tabs show. Called on open and after every action —
    /// cheap enough that being indiscriminate is simpler than being clever.
    func reload() {
        bindingRows = bindingsProvider().map { binding in
            guard let name = AppInfo.displayName(for: binding.bundleID) else {
                return BindingRow(binding: binding, appName: nil, icon: nil)
            }
            let icon = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: binding.bundleID)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            return BindingRow(binding: binding, appName: name, icon: icon)
        }
        let snip = snippetsProvider()
        prefix = snip.prefix
        snippetList = snip.snippets
        recoveryNotice = settings.snippetRecoveryNotice()
        windowCycling = settings.isWindowCyclingEnabled()
        startAtLogin = settings.isStartAtLoginEnabled()
        clipboardEnabled = settings.isClipboardEnabled()
        clipboardPaused = clipboard.isPaused()
        clipboardHotkey = settings.clipboardHotkeyDisplay()
        retention = settings.retention()
        pendingReminders = reminders.pending()
        reminderLog = reminders.log()
        reminderHotkey = reminders.hotkeyDisplay()
        reminderSound = reminders.isSoundEnabled()
    }

    /// Runs an action that may present an alert (every closure that can return an
    /// error does, via `AppDelegate`), keeps the panel open through it, and reloads.
    func perform(_ body: @escaping () -> Void) {
        runPreservingPanel(body)
        reload()
    }
}
