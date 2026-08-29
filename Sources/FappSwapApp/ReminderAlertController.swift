import AppKit
import FappSwapCore
import SwiftUI
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "ReminderCard")

/// The `ClipboardPanel` recipe once more, kept separate for the same reason
/// `StatusPanelWindow` is: this panel is shown *without* becoming key and only
/// takes focus on request.
final class ReminderAlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// State behind the card. Reminders are appended as they fire and cleared
/// together — every action applies to the whole card (spec decision 23).
final class ReminderAlertModel: ObservableObject {
    @Published private(set) var items: [Reminder] = []
    /// True while the panel is key, so the footer can say which keys work.
    @Published var isFocused = false
    /// `Was due 2 hours ago`, or nil when on time. Evaluated when a row is built.
    let overdueLabel: (Reminder) -> String?
    let hotkeyDisplay: () -> String

    init(overdueLabel: @escaping (Reminder) -> String?, hotkeyDisplay: @escaping () -> String) {
        self.overdueLabel = overdueLabel
        self.hotkeyDisplay = hotkeyDisplay
    }

    func add(_ new: [Reminder]) {
        let known = Set(items.map(\.id))
        items.append(contentsOf: new.filter { !known.contains($0.id) })
    }

    func removeAll() { items.removeAll() }

    var ids: Set<UUID> { Set(items.map(\.id)) }
}

/// The card. Appears top-right of the mouse's screen with `orderFrontRegardless()`,
/// so it never takes keyboard focus from whatever the user is typing in (decision
/// 21). `focus()` — the reminder hotkey pressed while a card is up — makes it key
/// for `↩` / `1` / `2` / `⎋` (decision 23). One card for everything currently due
/// (decision 17); it hides when the last reminder on it is dismissed or snoozed.
final class ReminderAlertController {
    private static let width: CGFloat = 300
    private static let inset: CGFloat = 16
    private static let soundName = "Glass"

    let model: ReminderAlertModel
    private let panel: ReminderAlertPanel
    private let soundEnabled: () -> Bool
    private let onDismiss: (Set<UUID>) -> Void
    private let onSnooze: (Set<UUID>, Int) -> Void
    private var keyMonitor: Any?
    /// Same discipline as `ClipboardPanelController.swallowedKeyCodes`: a key-up
    /// is swallowed if and only if its key-down was, so nothing reaches an empty
    /// responder chain after the card hides and makes AppKit beep.
    private var swallowedKeyCodes: Set<UInt16> = []
    /// The screen the card was placed on, so growth re-anchors to the same corner.
    private var screen: NSScreen?

    var isVisible: Bool { panel.isVisible }

    init(soundEnabled: @escaping () -> Bool,
         overdueLabel: @escaping (Reminder) -> String?,
         hotkeyDisplay: @escaping () -> String,
         onDismiss: @escaping (Set<UUID>) -> Void,
         onSnooze: @escaping (Set<UUID>, Int) -> Void) {
        self.soundEnabled = soundEnabled
        self.onDismiss = onDismiss
        self.onSnooze = onSnooze
        model = ReminderAlertModel(overdueLabel: overdueLabel, hotkeyDisplay: hotkeyDisplay)

        panel = ReminderAlertPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
            // Borderless, not `.titled`: a titled window reserves the title
            // bar's height inside its *frame* whatever `.fullSizeContentView`
            // does about drawing, so the frame can never be shorter than the
            // content plus ~28pt of dead space. Borderless makes the frame
            // exactly the content, and the view supplies the rounded background.
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        // `.nonactivatingPanel` only means "don't activate the app" — without this,
        // any click on the card (a drag via `isMovableByWindowBackground`, or a click
        // on blank space) still makes the panel key, and every keystroke after that
        // is silently swallowed by `handle(_:)`. `focus()`'s explicit
        // `makeKeyAndOrderFront` is unaffected.
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        // On every Space and over full-screen apps until dealt with (decisions 18, 24).
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // `.ignoresSafeArea()` is load-bearing: with `.fullSizeContentView` an
        // `NSHostingView` insets its content by the window's safe area, which
        // for a titled window is the title bar's height — a ~28pt empty band
        // above the icon, and 28pt of phantom height in `fittingSize`.
        panel.contentView = NSHostingView(rootView: ReminderAlertView(
            model: model,
            onDismiss: { [weak self] in self?.dismissAll() },
            onSnooze: { [weak self] minutes in self?.snoozeAll(minutes: minutes) })
            .ignoresSafeArea())

        // Key status drives the footer only. Losing key — a click elsewhere, or
        // `⎋` — is "give the keyboard back", never "close": the card stays.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.model.isFocused = true
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.model.isFocused = false
        }
    }

    /// Adds the reminders to the card, dings, and shows it — anchored top-right of
    /// the mouse's screen if it was hidden, re-fitted in place if already up. A call
    /// with nothing new — an empty batch, or one `model.add` fully dedupes away —
    /// is a no-op: it must never ding (decision 17, one ding per arrival) and must
    /// never leave an unclosable empty card on screen.
    func show(_ reminders: [Reminder]) {
        guard !reminders.isEmpty else { return }
        let before = model.items.count
        model.add(reminders)
        guard model.items.count > before else { return }
        if soundEnabled() {
            NSSound(named: Self.soundName)?.play()
        }
        if !panel.isVisible {
            screen = Self.mouseScreen()
        }
        installKeyMonitor()
        layout()
        panel.orderFrontRegardless()
        // SwiftUI applies the model change on the next turn; fit again then so
        // the card is the right height for its new rows. An `async` hop, never a wait.
        DispatchQueue.main.async { [weak self] in self?.layout() }
        logger.notice("card shown with \(self.model.items.count, privacy: .public) reminders")
    }

    /// The reminder hotkey while the card is up: take the keyboard.
    func focus() {
        guard panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        logger.notice("card focused")
    }

    /// `⎋`: keep the card, give the keyboard back. Hiding and re-showing without
    /// key is the one reliable way to return key status to the app the user was
    /// in — there is no "resign key but stay" call.
    private func unfocus() {
        // As in `hide()`: the panel is about to stop being key, so the trailing
        // `⎋` key-up goes to whatever app is key now and never reaches the
        // monitor. Leaving `53` in the set would swallow some later, unrelated
        // key-up instead.
        swallowedKeyCodes.removeAll()
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        logger.notice("card unfocused")
    }

    private func hide() {
        swallowedKeyCodes.removeAll()
        model.removeAll()
        panel.orderOut(nil)
        logger.notice("card hidden")
    }

    private func layout() {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        // The frame, not the content size: with `.fullSizeContentView` the view
        // spans the whole frame, so `setContentSize` would add the title bar's
        // height back on top and leave an empty band above the icon.
        let height = measuredHeight()
        guard height > 0 else { return }
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: panel.frame.minY,
                   width: Self.width, height: height),
            display: true)
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - Self.inset - panel.frame.width,
            y: frame.maxY - Self.inset - panel.frame.height))
    }

    /// The card's height for the rows it currently holds, measured in a
    /// throwaway hosting view.
    ///
    /// The real one is the window's content view, so AppKit stretches it to the
    /// window and it reports the window's own height back from both
    /// `fittingSize` and `intrinsicContentSize` — measuring it can only ever
    /// confirm the size it already has, which would pin the card at its initial
    /// height however many reminders arrived. A detached view has no window to
    /// be stretched to, so its `fittingSize` is the real one.
    private func measuredHeight() -> CGFloat {
        let probe = NSHostingView(rootView: ReminderAlertView(
            model: model, onDismiss: {}, onSnooze: { _ in })
            .ignoresSafeArea())
        probe.frame = NSRect(x: 0, y: 0, width: Self.width, height: 0)
        probe.layoutSubtreeIfNeeded()
        return probe.fittingSize.height
    }

    private static func mouseScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    // MARK: - Keys

    /// Installed once and kept, as in `ClipboardPanelController`: `handle(_:)`
    /// gates on `panel.isKeyWindow`, so it costs nothing while the card is not
    /// focused, and `handleKeyUp(_:)` still sees the key-up that lands after a
    /// dismissing `↩` has already hidden the card.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return event.type == .keyDown ? self.handle(event) : self.handleKeyUp(event)
        }
    }

    /// Only while focused. Every unmodified key is swallowed: the card has nothing
    /// to type into, and an unhandled key-down in a key window beeps. Anything
    /// carrying `⌘` passes through instead — a local monitor runs before
    /// `NSMenu.performKeyEquivalent`, so swallowing those would kill ⌘Q and every
    /// other app-level key equivalent while the card is focused. The insert
    /// happens *after* the action for the two that hide the card, because `hide()`
    /// clears the set as it runs.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }
        guard !event.modifierFlags.contains(.command) else { return event }
        switch event.keyCode {
        case 36, 76:  // ↩, keypad enter
            dismissAll()
        case 18:  // 1
            snoozeAll(minutes: 5)
        case 19:  // 2
            snoozeAll(minutes: 15)
        case 53:  // ⎋
            unfocus()
        default:
            break
        }
        swallowedKeyCodes.insert(event.keyCode)
        return nil
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        guard swallowedKeyCodes.remove(event.keyCode) != nil else { return event }
        return nil
    }

    // MARK: - Actions

    private func dismissAll() {
        let ids = model.ids
        guard !ids.isEmpty else { return }
        hide()
        onDismiss(ids)
    }

    private func snoozeAll(minutes: Int) {
        let ids = model.ids
        guard !ids.isEmpty else { return }
        hide()
        onSnooze(ids, minutes)
    }
}

struct ReminderAlertView: View {
    @ObservedObject var model: ReminderAlertModel
    let onDismiss: () -> Void
    let onSnooze: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // The bundle's icns (decision 22). Outside a bundle this is the
                // generic app icon, which is fine for `swift run`.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.items.count == 1 ? "Reminder" : "\(model.items.count) reminders")
                        .font(.subheadline.weight(.semibold))
                    ForEach(model.items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            if let overdue = model.overdueLabel(item) {
                                Text(overdue).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Divider()
            HStack {
                Spacer()
                Button("Snooze 5 min") { onSnooze(5) }
                Button("Snooze 15 min") { onSnooze(15) }
                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            // Decision 23: the card explains its own keyboard behaviour.
            Text(model.isFocused
                 ? "↩ dismiss · 1 / 2 snooze · ⎋ back"
                 : "\(model.hotkeyDisplay()) for keyboard")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 300)
        // The panel is borderless, so its chrome lives here.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
