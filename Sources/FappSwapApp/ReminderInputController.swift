import AppKit
import FappSwapCore
import SwiftUI
import os

private let logger = Logger(subsystem: "com.firatcansucu.fappswap", category: "ReminderInput")

/// The `ClipboardPanel` recipe — key without activating the app, so the app the
/// user was in stays active. A separate class for the same reason the others are:
/// this panel closes on losing key (spec decision 10) and the card does not.
final class ReminderInputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// State behind the two-step view. Step one is the text, taken verbatim (decision
/// 4); step two is the time. A refused `↩` bumps `shakes`, which the view animates.
final class ReminderInputModel: ObservableObject {
    enum Step { case text, time }

    @Published var step: Step = .text
    @Published var text = ""
    @Published var timeInput = "" {
        didSet { refreshPreview() }
    }
    /// `Fires at 3:42 PM (in 25 minutes)` while the time parses; nil otherwise.
    @Published private(set) var preview: String?
    /// The parser's message while the time doesn't parse; nil while the field is
    /// empty or parses.
    @Published private(set) var problem: String?
    @Published private(set) var shakes = 0
    /// Bumped on every open so the view re-focuses the field.
    @Published var openGeneration = 0

    static let chips: [(label: String, input: String)] = [
        ("15 min", "15m"), ("30 min", "30m"), ("1 hour", "1h"), ("Tomorrow 9:00", "tomorrow 9am"),
    ]

    private let parse: (String) -> Result<Date, ReminderTimeParser.Failure>
    private let dueLabel: (Date) -> String

    init(parse: @escaping (String) -> Result<Date, ReminderTimeParser.Failure>,
         dueLabel: @escaping (Date) -> String) {
        self.parse = parse
        self.dueLabel = dueLabel
    }

    func reset() {
        step = .text
        text = ""
        timeInput = ""
    }

    /// `↩` in step one. False, with a shake, when there is nothing to remind about (decision 1).
    func advance() -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            shakes += 1
            return false
        }
        step = .time
        return true
    }

    /// `⌫` on an empty time field: back to the text, which is kept.
    func back() {
        timeInput = ""
        step = .text
    }

    /// `↩` in step two. nil, with a shake, when the time is blank or doesn't parse (decisions 2, 7, 8).
    func submit() -> (text: String, dueDate: Date)? {
        guard case .success(let date) = parse(timeInput) else {
            shakes += 1
            return nil
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), date)
    }

    private func refreshPreview() {
        let trimmed = timeInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            preview = nil
            problem = nil
            return
        }
        switch parse(trimmed) {
        case .success(let date):
            preview = "Fires at \(dueLabel(date))"
            problem = nil
        case .failure(let failure):
            preview = nil
            problem = failure.message
        }
    }
}

/// Owns the `⌥R` input panel: shows it where Spotlight would, routes `↩` / `⎋` /
/// `⌫`, and hands the finished draft to `onCreate`, which returns an error to show
/// or nil. `NSApp.activate()` is never called to show *this panel* — see
/// `ReminderInputPanel`. The one deliberate exception is `showError`'s `NSAlert`:
/// as an accessory app fappswap otherwise isn't the one receiving keys, so that
/// modal needs activation for `↩`/`⎋` to reach it — see its own doc comment.
final class ReminderInputController {
    private static let width = ReminderInputMetrics.width
    private static let initialHeight = ReminderInputMetrics.textHeight
    /// The panel's top edge, fixed while it is open so that growing into the
    /// time step extends downwards instead of making the whole panel jump.
    private var anchorTop: CGFloat?

    let model: ReminderInputModel
    private let panel: ReminderInputPanel
    private let onCreate: (String, Date) -> String?
    private var keyMonitor: Any?
    /// Same discipline as `ClipboardPanelController.swallowedKeyCodes` — read
    /// that doc comment. The insert happens *after* any action that closes the
    /// panel, because `close()` clears the set as it runs.
    private var swallowedKeyCodes: Set<UInt16> = []

    var isVisible: Bool { panel.isVisible }

    init(parse: @escaping (String) -> Result<Date, ReminderTimeParser.Failure>,
         dueLabel: @escaping (Date) -> String,
         onCreate: @escaping (String, Date) -> String?) {
        self.onCreate = onCreate
        model = ReminderInputModel(parse: parse, dueLabel: dueLabel)

        panel = ReminderInputPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.initialHeight),
            // Borderless, not `.titled`: a titled window reserves the title
            // bar's height inside its *frame* whatever `.fullSizeContentView`
            // does about drawing, so the frame can never be shorter than the
            // content plus ~28pt — which shows up as dead space under the
            // footer that no amount of resizing removes. Borderless makes the
            // frame exactly the content, and the view below supplies the
            // rounded background this used to get from the title bar.
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // `.ignoresSafeArea()` is load-bearing: with `.fullSizeContentView` an
        // `NSHostingView` insets its content by the window's safe area, which
        // for a titled window is the title bar's height — a ~28pt empty band
        // above the field, and 28pt of phantom height in `fittingSize`.
        panel.contentView = NSHostingView(rootView: ReminderInputView(
            model: model,
            onChip: { [weak self] input in self?.pick(input) })
            .ignoresSafeArea())

        // Clicking anywhere outside a non-activating panel makes it resign key;
        // that is "click outside closes and discards" (decision 10), no global monitor.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }

    /// Opens fresh, or brings an already-open panel back to front with its draft
    /// intact (decision 11).
    func open() {
        if !panel.isVisible {
            model.reset()
        }
        model.openGeneration += 1
        if !panel.isVisible { positionOnMouseScreen() }
        layout()
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
        // The step's view has not been laid out yet on the first pass, so take
        // the height again once SwiftUI has caught up. Same hop the card uses.
        DispatchQueue.main.async { [weak self] in self?.layout() }
        logger.notice("input opened")
    }

    func close() {
        guard panel.isVisible else { return }
        swallowedKeyCodes.removeAll()
        panel.orderOut(nil)
        logger.notice("input closed")
    }

    /// Slightly above centre on the screen the mouse is on, like Spotlight.
    /// Records the top edge so `layout()` can grow the panel downwards.
    private func positionOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else {
            panel.center()
            anchorTop = panel.frame.maxY
            return
        }
        let origin = NSPoint(
            x: frame.midX - Self.width / 2,
            y: frame.midY - Self.initialHeight / 2 + frame.height * 0.08)
        panel.setFrameOrigin(origin)
        anchorTop = origin.y + Self.initialHeight
    }

    /// A step change swaps the view's contents, so its height is only correct
    /// on the next run-loop turn. Never a synchronous wait — this sits on the
    /// key monitor's callback path.
    private func relayoutAfterStepChange() {
        DispatchQueue.main.async { [weak self] in self?.layout() }
    }

    /// Shrinks the panel to exactly what the view needs, keeping the top edge
    /// where it was so the description step is one line tall and the time step
    /// grows downwards from the same place.
    private func layout() {
        // Deliberately not measured. This view is the window's content view, so
        // it is stretched to the window and reports the window's own height back
        // from both `fittingSize` and `intrinsicContentSize` — a circular
        // measurement that can never shrink the panel. `ReminderInputMetrics` is
        // the single source of truth instead, shared with the view's own frame,
        // so the window is exactly as tall as what it draws.
        let height = ReminderInputMetrics.height(for: model.step)
        let top = anchorTop ?? panel.frame.maxY
        // The frame, not the content size: with `.fullSizeContentView` the view
        // spans the whole frame, so `setContentSize` would add the title bar's
        // height back on top and reintroduce the empty band.
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - height, width: Self.width, height: height),
            display: true)
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return event.type == .keyDown ? self.handle(event) : self.handleKeyUp(event)
        }
    }

    /// Returns nil to swallow the event, or the event to let the text field have it.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }
        switch event.keyCode {
        case 36, 76:  // ↩, keypad enter
            if model.step == .text {
                if model.advance() { relayoutAfterStepChange() }
            } else {
                save()
            }
            swallowedKeyCodes.insert(event.keyCode)
            return nil
        case 53:  // ⎋
            close()
            swallowedKeyCodes.insert(event.keyCode)
            return nil
        case 51 where model.step == .time && model.timeInput.isEmpty:  // ⌫ on an empty time field
            model.back()
            relayoutAfterStepChange()
            swallowedKeyCodes.insert(event.keyCode)
            return nil
        default:
            return event
        }
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        guard swallowedKeyCodes.remove(event.keyCode) != nil else { return event }
        return nil
    }

    // MARK: - Actions

    private func pick(_ input: String) {
        model.timeInput = input
        save()
    }

    private func save() {
        guard let draft = model.submit() else { return }
        close()
        guard let message = onCreate(draft.text, draft.dueDate) else { return }
        // `save()` runs on the key monitor's callback (`handle(_:)` -> `save()`).
        // `showError`'s `runModal()` is a nested run loop that would not return
        // until the alert is dismissed, so the monitor block itself would block
        // on it — exactly what nothing on this path may do (see the module's
        // doc comment about `asyncAfter`, never a synchronous wait). Hopping out
        // first also keeps `handle(_:)`'s `swallowedKeyCodes.insert` for this ↩
        // from racing the trailing key-up against a nested modal session, and
        // keeps a stray `⌥R` from ordering a panel front that can't take key
        // while the modal holds it.
        DispatchQueue.main.async { [weak self] in self?.showError(message) }
    }

    /// `runModal` is safe here for the same reason it is in `AppDelegate`:
    /// the tap's run-loop source runs in `.commonModes`, which
    /// includes the modal-panel mode, so events keep flowing while this alert is
    /// up. `NSApp.activate()` first so `↩`/`⎋` reach it — as an accessory app,
    /// fappswap is otherwise not the one receiving keys. Must be called off the
    /// key monitor's callback — see the comment at its one call site in `save()`.
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }
}

/// The panel's exact size, shared by the SwiftUI frame and the window frame so
/// the two can never disagree and leave dead space. These are measured by eye
/// against the real app, not computed: an `NSHostingView` installed as a
/// window's content view reports the window's own height back from both
/// `fittingSize` and `intrinsicContentSize`, so there is nothing to compute
/// from. Adjust here and the window follows.
enum ReminderInputMetrics {
    static let width: CGFloat = 460
    /// One line of `.title3` with 11pt above and below, a divider, and the footer.
    static let textHeight: CGFloat = 70
    /// The description recap, the field, a divider, and the chips row.
    static let timeHeight: CGFloat = 93

    static func height(for step: ReminderInputModel.Step) -> CGFloat {
        step == .text ? textHeight : timeHeight
    }
}

struct ReminderInputView: View {
    @ObservedObject var model: ReminderInputModel
    let onChip: (String) -> Void
    @FocusState private var focus: ReminderInputModel.Step?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.step {
            case .text:
                TextField("What should I remind you about?", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .focused($focus, equals: .text)
            case .time:
                Text(model.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                TextField("When? 30m · 1h30m · 15:30 · 3pm · tomorrow 9am · monday", text: $model.timeInput)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(.horizontal, 14)
                    .padding(.top, 3)
                    .padding(.bottom, 11)
                    .focused($focus, equals: .time)
            }
            Divider()
            HStack(spacing: 8) {
                if model.step == .time {
                    ForEach(ReminderInputModel.chips, id: \.input) { chip in
                        Button(chip.label) { onChip(chip.input) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                Spacer()
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(model.problem == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(width: ReminderInputMetrics.width,
               height: ReminderInputMetrics.height(for: model.step),
               alignment: .top)
        // The panel is borderless, so its chrome lives here.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .modifier(Shake(animatableData: CGFloat(model.shakes)))
        .animation(.default, value: model.shakes)
        .onAppear { focus = .text }
        .onChange(of: model.step) { _, step in
            // The hop lets the new field exist before focus is asked for.
            DispatchQueue.main.async { focus = step }
        }
        .onChange(of: model.openGeneration) { _, _ in
            // The hop lets the window finish becoming key before focus is asked for.
            DispatchQueue.main.async { focus = model.step }
        }
    }

    private var footer: String {
        switch model.step {
        case .text: return "↩ next · ⎋ cancel"
        case .time: return model.problem ?? model.preview ?? "↩ set · ⌫ back · ⎋ cancel"
        }
    }
}

/// The macOS "no" gesture (decisions 1, 2): a quick horizontal wobble, driven by
/// a counter so each refusal animates once.
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: 8 * sin(animatableData * .pi * 3), y: 0))
    }
}
