import AppKit
import FappSwapCore
import SwiftUI

extension Modifier {
    /// AppKit's flags, for keystrokes captured by the recorder rather than the tap.
    ///
    /// Mirrors `Modifier.set(from: CGEventFlags)` in `FappSwapCore/Modifier.swift`
    /// — the two must stay in agreement, or the tap (that one) and the recorder
    /// (this one) will disagree about what a keystroke's modifiers are and a
    /// recorded shortcut will silently never fire.
    static func set(from flags: NSEvent.ModifierFlags) -> Set<Modifier> {
        var result = Set<Modifier>()
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}

final class KeyRecorderView: NSView {
    var onCapture: ((UInt16, Set<Modifier>) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // esc
            onCancel?()
            return
        }
        onCapture?(event.keyCode, Modifier.set(from: event.modifierFlags))
    }
}

struct KeyRecorder: NSViewRepresentable {
    var onCapture: (UInt16, Set<Modifier>) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
    }
}
