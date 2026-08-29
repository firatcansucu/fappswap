import AppKit
import FappSwapCore
import SwiftUI
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "ClipboardPanel")

/// A panel that takes keyboard focus without activating the app. That is the
/// whole trick: the app the user was in stays active, so a synthetic ⌘V after
/// the panel closes lands there.
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the `⌥⌘V` panel: shows it centred on the mouse's screen, routes keys,
/// and performs paste / copy / delete. `NSApp.activate()` is never called
/// here — see `ClipboardPanel`.
final class ClipboardPanelController {
    let model: ClipboardPanelModel
    private let store: ClipboardHistoryStore
    private let writer: PasteboardWriter
    /// False while an expansion is in flight; a paste then would interleave
    /// with the expander's own ⌘V.
    private let canPaste: () -> Bool
    private let panel: ClipboardPanel
    private var keyMonitor: Any?
    /// Key codes consumed on key-down, so the matching key-up can be swallowed
    /// too. `handle(_:)` returns nil for keys it consumes (⎋, ↩, ⌘C, ⌘⌫, ⌫),
    /// which correctly eats the key-down — but the key-up for the same key
    /// still arrives afterward, on its own, separate turn of the run loop
    /// (the physical release lags the press). For the keys that close the
    /// panel, that key-up used to land after `panel.orderOut(nil)` and the
    /// monitor's own teardown had already run, reaching an empty responder
    /// chain and making AppKit beep. Mirrors `HotkeyTap`'s `swallowedKeyCodes`:
    /// a key-up swallowed without its key-down (or vice versa) is exactly the
    /// bug class that discipline exists to prevent — which is also why the
    /// monitor itself now stays installed for the controller's lifetime
    /// rather than being torn down in `close()` (see `installKeyMonitor()`):
    /// a monitor removed the instant the panel closes can never see the
    /// trailing key-up that arrives afterward.
    private var swallowedKeyCodes: Set<UInt16> = []

    private static let size = NSSize(width: 560, height: 420)
    /// Settle time between writing the pasteboard and posting ⌘V; the same
    /// value `TextInjector` uses before its paste.
    private static let settleBeforePaste: TimeInterval = 0.05

    var isVisible: Bool { panel.isVisible }

    init(store: ClipboardHistoryStore, writer: PasteboardWriter,
         isPaused: @escaping () -> Bool, canPaste: @escaping () -> Bool) {
        self.store = store
        self.writer = writer
        self.canPaste = canPaste
        model = ClipboardPanelModel(store: store, isPaused: isPaused)

        panel = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        // Appears over a full-screen app and on whichever Space is current —
        // the app's whole point is not caring which Space you are on.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: ClipboardPanelView(model: model, onCopy: { [weak self] item in
                self?.copy(item)
            }))

        // Clicking anywhere outside a non-activating panel makes it resign key;
        // that is the "click outside closes" behaviour, with no global monitor.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }

    func toggle() {
        if isVisible { close() } else { open() }
    }

    func open() {
        model.query = ""
        model.reload()
        model.selectFirst()
        model.openGeneration += 1
        positionOnMouseScreen()
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
        logger.notice("panel opened with \(self.model.totalCount, privacy: .public) items")
    }

    func close() {
        guard isVisible else { return }
        // The key monitor is deliberately not torn down here — see
        // `installKeyMonitor()`. Stale entries are still cleared so a panel
        // closed by a click outside (no key involved) can't strand one and
        // wrongly swallow an unrelated future key-up of the same code; the
        // three cases in `handle(_:)` that close the panel themselves add
        // their own key code back in immediately after, so their trailing
        // key-up is still caught.
        swallowedKeyCodes.removeAll()
        panel.orderOut(nil)
        logger.notice("panel closed")
    }

    /// Slightly above centre on the screen the mouse is on, like Spotlight.
    private func positionOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let origin = NSPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.midY - Self.size.height / 2 + frame.height * 0.08)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Keys

    /// Installed once and kept for the controller's whole lifetime, not
    /// torn down on every `close()`. `handle(_:)` (key-down) already gates
    /// on `panel.isKeyWindow`, so leaving the monitor running while the
    /// panel is hidden costs nothing; keeping it running is what lets
    /// `handleKeyUp(_:)` still catch a key-up that arrives after the panel
    /// has already closed. The guard just makes a second `open()` call a
    /// no-op instead of leaking a duplicate monitor.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return event.type == .keyDown ? self.handle(event) : self.handleKeyUp(event)
        }
    }

    /// Returns nil to swallow the event, or the event to let the search field
    /// have it. The search field keeps focus throughout; arrows never move it.
    ///
    /// Every case that returns nil here also records its key code in
    /// `swallowedKeyCodes` so `handleKeyUp(_:)` can swallow the matching
    /// key-up — see that property's doc comment for why. For ⎋, ↩ and ⌘C,
    /// which close the panel via `close()` (directly, or inside `paste()` /
    /// `copy()`), the insert happens *after* that call rather than before:
    /// `close()` clears the whole set as it runs, so inserting first would
    /// have the entry wiped out by the very call meant to make it matter.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 126:  // ↑
            model.moveSelection(by: -1)
            swallowedKeyCodes.insert(event.keyCode)
            return nil
        case 125:  // ↓
            model.moveSelection(by: 1)
            swallowedKeyCodes.insert(event.keyCode)
            return nil
        case 36, 76:  // ↩, keypad enter
            paste()
            swallowedKeyCodes.insert(event.keyCode)
            return nil
        case 53:  // ⎋
            close()
            swallowedKeyCodes.insert(event.keyCode)
            return nil
        case 8 where flags == .command:  // ⌘C
            if let item = model.selected { copy(item) }
            swallowedKeyCodes.insert(event.keyCode)
            return nil
        case 51 where flags == .command:  // ⌘⌫ — always deletes the item
            swallowedKeyCodes.insert(event.keyCode)
            deleteSelected()
            return nil
        case 51 where flags.isEmpty && model.query.isEmpty:
            // ⌫ deletes the item only with an empty search field; with text in
            // it, ⌫ edits the query. Accepted consequence (see the spec):
            // backspacing out a query and pressing ⌫ once more deletes the item.
            swallowedKeyCodes.insert(event.keyCode)
            deleteSelected()
            return nil
        default:
            return event
        }
    }

    /// Swallows the key-up matching a key-down `handle(_:)` consumed, so it
    /// never reaches an empty responder chain after the panel closes and
    /// makes AppKit beep. Any key-up not in `swallowedKeyCodes` — the search
    /// field's own typing — passes through untouched. Deliberately does not
    /// gate on `panel.isKeyWindow` the way `handle(_:)` does: the whole point
    /// is to still catch the key-up after the panel is no longer key.
    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        guard swallowedKeyCodes.remove(event.keyCode) != nil else { return event }
        return nil
    }

    // MARK: - Actions

    private func paste() {
        guard let item = model.selected else { return }
        close()
        guard canPaste() else {
            logger.notice("paste skipped: an injection is in flight")
            return
        }
        guard write(item) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleBeforePaste) {
            SyntheticKey.post(keyCode: SyntheticKey.vKeyCode, flags: .maskCommand)
        }
        logger.notice("pasted \(item.imageRef == nil ? "text" : "image", privacy: .public) item")
    }

    private func copy(_ item: ClipboardItem) {
        close()
        guard write(item) else { return }
        logger.notice("copied \(item.imageRef == nil ? "text" : "image", privacy: .public) item")
    }

    /// Writes the item to the pasteboard and promotes it to the top of the
    /// history. Returns false if the write did not happen — a listed image
    /// whose backing file is already gone, e.g. pruned since the panel last
    /// reloaded — so callers can skip the synthetic ⌘V and the success log.
    @discardableResult
    private func write(_ item: ClipboardItem) -> Bool {
        switch item.content {
        case .text(let text):
            writer.write(text: text)
        case .image:
            guard let url = store.imageURL(for: item), let png = try? Data(contentsOf: url) else {
                logger.error("image file missing for a listed item")
                return false
            }
            writer.write(png: png)
        }
        try? store.touch(id: item.id)
        return true
    }

    private func deleteSelected() {
        guard let item = model.selected else { return }
        do {
            try store.remove(id: item.id)
            logger.notice("deleted one item from the panel, \(self.store.items.count, privacy: .public) remain")
        } catch {
            logger.error("could not delete clipboard item: \(error.localizedDescription, privacy: .public)")
        }
        model.selectAfterRemoving(indexOf: item.id)
    }
}
