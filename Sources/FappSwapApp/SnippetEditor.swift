import AppKit
import FappSwapCore
import SwiftUI

/// The snippet editor. Expands inline inside the status panel's Snippets tab, so
/// it sizes to whatever column it is given rather than to a fixed dialog width.
/// `onSave` returns the rejection message, or nil when saved — the editor stays
/// open on rejection so nothing typed is lost.
struct SnippetEditor: View {
    @State private var trigger: String
    @State private var replacement: String
    @State private var error: String?
    @FocusState private var triggerFocused: Bool
    private let snippetID: String?
    private let prefix: String
    private let onCancel: () -> Void
    private let onSave: (SnippetDraft) -> String?

    init(draft: SnippetDraft,
         prefix: String,
         onCancel: @escaping () -> Void,
         onSave: @escaping (SnippetDraft) -> String?) {
        _trigger = State(initialValue: draft.trigger)
        _replacement = State(initialValue: draft.replacement)
        snippetID = draft.snippetID
        self.prefix = prefix
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(prefix).font(.system(.body, design: .monospaced))
                TextField("trigger", text: $trigger)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .focused($triggerFocused)
            }

            Text("Expands to").font(.caption).foregroundStyle(.secondary)
            PlainTextEditor(text: $replacement)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
                .border(Color.secondary.opacity(0.3))

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    error = onSave(SnippetDraft(
                        snippetID: snippetID, trigger: trigger, replacement: replacement))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .onAppear { triggerFocused = true }
    }
}

/// A plain, monospaced, non-hyphenating text view.
///
/// SwiftUI's `TextEditor` hyphenates as it wraps, so a long snippet renders as
/// `firatcan.sucu@protonmail.-com` and reads as though the hyphen were part of
/// the replacement text. The paragraph style is the only place to turn that off,
/// and the only way to reach it is to own the `NSTextView`.
struct PlainTextEditor: NSViewRepresentable {
    @SwiftUI.Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.usesDefaultHyphenation = false
        style.hyphenationFactor = 0
        textView.defaultParagraphStyle = style
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.typingAttributes = [
            .paragraphStyle: style,
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = context.coordinator
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only when it actually differs: assigning `string` while the user types
        // would reset the insertion point to the end on every keystroke.
        if textView.string != text { textView.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: SwiftUI.Binding<String>

        init(text: SwiftUI.Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
