import AppKit
import FappSwapCore
import SwiftUI

/// "Press a combination" as an inline row instead of a floating dialog. The
/// embedded `KeyRecorder` grabs first responder; the tap is already suspended
/// because opening a recorder editor sets `activeEditor` (see
/// `StatusPanelController.didChangeEditor`). Reused for all three hotkeys.
struct InlineShortcutRecorder: View {
    let prompt: String
    /// Shown above the prompt when changing an existing shortcut; nil when adding.
    let current: String?
    let validate: (UInt16, Set<Modifier>) -> String?
    let onCapture: (UInt16, Set<Modifier>) -> Void
    let onCancel: () -> Void
    @State private var error: String?

    var body: some View {
        ZStack(alignment: .leading) {
            KeyRecorder(
                onCapture: { keyCode, modifiers in
                    if let message = validate(keyCode, modifiers) {
                        error = message
                    } else {
                        onCapture(keyCode, modifiers)
                    }
                },
                onCancel: onCancel)
            .frame(width: 0, height: 0)
            VStack(alignment: .leading, spacing: 4) {
                if let current {
                    Text("Current: \(current)").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(prompt)
                    Spacer()
                    Text("esc to cancel").font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct ShortcutsTab: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.bindingRows.isEmpty && model.activeEditor != .addShortcut {
                        Text("No shortcuts yet").foregroundStyle(.secondary).padding(8)
                    }
                    ForEach(model.bindingRows) { row in
                        if model.activeEditor == .editShortcut(row.id) {
                            InlineShortcutRecorder(
                                prompt: "Press a new combination",
                                current: row.binding.displayKey,
                                validate: { keyCode, modifiers in
                                    model.settings.validateShortcutEdit(row.binding, keyCode, modifiers)
                                },
                                onCapture: { keyCode, modifiers in
                                    model.activeEditor = nil
                                    model.perform {
                                        model.settings.saveShortcutEdit(row.binding, keyCode, modifiers)
                                    }
                                },
                                onCancel: { model.activeEditor = nil })
                        } else {
                            ShortcutRow(model: model, row: row)
                        }
                    }
                    if model.activeEditor == .addShortcut {
                        InlineShortcutRecorder(
                            prompt: "Press any key combination",
                            current: nil,
                            validate: model.settings.validateShortcut,
                            onCapture: { keyCode, modifiers in
                                model.activeEditor = nil  // resume the tap before the modal picker
                                model.perform { model.settings.saveShortcut(keyCode, modifiers) }
                            },
                            onCancel: { model.activeEditor = nil })
                    } else {
                        Button {
                            model.activeEditor = .addShortcut
                        } label: {
                            Label("Add Shortcut…", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                    }
                }
            }
            Divider()
            Toggle("Cycle Windows with ⌥⇥", isOn: Binding(
                get: { model.windowCycling },
                set: { on in model.perform { model.settings.setWindowCycling(on) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(12)
    }
}

private struct ShortcutRow: View {
    @ObservedObject var model: StatusPanelModel
    let row: StatusPanelModel.BindingRow
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(row.binding.displayKey)
                .font(.system(.body, design: .monospaced))
            if let icon = row.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            if let name = row.appName {
                Text(name).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("\(row.binding.bundleID) — not installed")
                    .foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
            if hovering {
                Button {
                    model.activeEditor = .editShortcut(row.id)
                } label: {
                    Image(systemName: "pencil").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Change the combination")
                Button {
                    model.perform { model.settings.removeShortcut(row.binding) }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .padding(6)
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard row.appName != nil else { return }
            model.activate(row.binding.bundleID)
        }
    }
}

struct SnippetsTab: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = model.recoveryNotice {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            if model.activeEditor == .prefix {
                InlinePrefixEditor(model: model)
            } else {
                HStack(spacing: 6) {
                    Text("Prefix").foregroundStyle(.secondary)
                    Text(model.prefix).font(.system(.body, design: .monospaced))
                    Button("Change…") { model.activeEditor = .prefix }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
                .font(.caption)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.snippetList.isEmpty && model.activeEditor != .addSnippet {
                        Text("No snippets yet").foregroundStyle(.secondary).padding(8)
                    }
                    ForEach(model.snippetList, id: \.id) { snippet in
                        if model.activeEditor == .editSnippet(snippet.id) {
                            inlineEditor(SnippetDraft(
                                snippetID: snippet.id, trigger: snippet.trigger,
                                replacement: snippet.replacement))
                        } else {
                            SnippetRow(model: model, snippet: snippet)
                        }
                    }
                    if model.activeEditor == .addSnippet {
                        inlineEditor(SnippetDraft(snippetID: nil, trigger: "", replacement: ""))
                    } else {
                        Button {
                            model.activeEditor = .addSnippet
                        } label: {
                            Label("Add Snippet…", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                    }
                }
            }
        }
        .padding(12)
    }

    /// The floating dialog's editor, embedded. It sizes to the content column now
    /// rather than to its old 420pt dialog width.
    private func inlineEditor(_ draft: SnippetDraft) -> some View {
        SnippetEditor(
            draft: draft,
            prefix: model.prefix,
            onCancel: { model.activeEditor = nil },
            onSave: { draft in
                let message = model.settings.saveSnippet(draft)
                if message == nil {
                    model.activeEditor = nil
                    model.reload()
                }
                return message
            })
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct InlinePrefixEditor: View {
    @ObservedObject var model: StatusPanelModel
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Prefix")
                TextField("", text: $draft)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .font(.system(.body, design: .monospaced))
                    .focused($focused)
                    .onSubmit { apply() }
                Button("Apply") { apply() }
                Button("Cancel") { model.activeEditor = nil }
            }
            Text("One character that isn't a letter. Every snippet's trigger starts with it.")
                .font(.caption).foregroundStyle(.secondary)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .onAppear {
            draft = model.prefix
            focused = true
        }
    }

    private func apply() {
        error = model.settings.savePrefix(draft)
        if error == nil {
            model.activeEditor = nil
            model.reload()
        }
    }
}

private struct SnippetRow: View {
    @ObservedObject var model: StatusPanelModel
    let snippet: Snippet
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(model.prefix + snippet.trigger)
                .font(.system(.body, design: .monospaced))
            Text(snippet.preview())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if hovering {
                // Copies, never pastes: after the panel closes, which app has key
                // focus is timing-dependent — same reasoning as the old menu's Copy.
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet.replacement, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Copy")
                Button {
                    model.activeEditor = .editSnippet(snippet.id)
                } label: {
                    Image(systemName: "pencil").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Edit")
                Button {
                    model.perform { model.settings.removeSnippet(snippet) }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Remove")
            }
        }
        .padding(6)
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}

struct ClipboardTab: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Keep a History of What You Copy", isOn: Binding(
                get: { model.clipboardEnabled },
                set: { on in model.perform { model.settings.setClipboardEnabled(on) } }))
            Toggle("Pause Clipboard History", isOn: Binding(
                get: { model.clipboardPaused },
                set: { _ in model.perform { model.clipboard.togglePause() } }))
                .disabled(!model.clipboardEnabled)

            if model.activeEditor == .clipboardHotkey {
                InlineShortcutRecorder(
                    prompt: "Press a new combination",
                    current: model.clipboardHotkey,
                    validate: model.settings.validateClipboardHotkey,
                    onCapture: { keyCode, modifiers in
                        model.activeEditor = nil
                        model.perform { model.settings.saveClipboardHotkey(keyCode, modifiers) }
                    },
                    onCancel: { model.activeEditor = nil })
            } else {
                HStack(spacing: 6) {
                    Text("Shortcut: \(model.clipboardHotkey)")
                    Button("Change…") { model.activeEditor = .clipboardHotkey }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
                .disabled(!model.clipboardEnabled)
                .foregroundStyle(model.clipboardEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }

            // selectRetention can run a confirmation alert (shrinking with items to
            // delete), and clearHistory always does — both go through `perform`, whose
            // runPreservingPanel keeps the panel alive under the modal.
            Picker("Keep History For", selection: Binding(
                get: { model.retention },
                set: { days in model.perform { model.settings.selectRetention(days) } })) {
                ForEach(RetentionDays.allCases, id: \.self) { days in
                    Text(days.label).tag(days)
                }
            }
            .disabled(!model.clipboardEnabled)

            Divider()
            Button("Open Clipboard History") { model.clipboard.open() }
            Button("Show History in Finder") { model.settings.revealHistory() }
            Button("Clear History…") { model.perform { model.settings.clearHistory() } }
            Spacer()
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RemindersTab: View {
    @ObservedObject var model: StatusPanelModel
    @State private var text = ""
    @State private var timeInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Both fields at once, not the ⌥R panel's two-step flow: in a panel
            // with a mouse there is nothing to gain from the step dance, and the
            // live preview runs the same parser either way.
            TextField("Remind me about…", text: $text)
            HStack(spacing: 6) {
                TextField("When? 30m · 3pm · tomorrow 9am", text: $timeInput)
                Button("Add") { add() }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || timeInput.isEmpty)
            }
            Text(preview.text)
                .font(.caption)
                .foregroundStyle(preview.isProblem ? Color.red : Color.secondary)
                .lineLimit(1)

            // One row each: crammed onto a single line the sound toggle's label
            // wrapped, which looked broken.
            Toggle("Play a Sound", isOn: Binding(
                get: { model.reminderSound },
                set: { on in model.perform { model.reminders.setSoundEnabled(on) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .lineLimit(1)
                .fixedSize()
            if model.activeEditor != .reminderHotkey {
                HStack(spacing: 6) {
                    Text("Shortcut: \(model.reminderHotkey)").font(.caption).foregroundStyle(.secondary)
                    Button("Change…") { model.activeEditor = .reminderHotkey }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor).font(.caption)
                    Spacer()
                }
            }
            if model.activeEditor == .reminderHotkey {
                InlineShortcutRecorder(
                    prompt: "Press a new combination",
                    current: model.reminderHotkey,
                    validate: model.reminders.validateHotkey,
                    onCapture: { keyCode, modifiers in
                        model.activeEditor = nil
                        model.perform { model.reminders.saveHotkey(keyCode, modifiers) }
                    },
                    onCancel: { model.activeEditor = nil })
            }

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.pendingReminders.isEmpty {
                        Text("Nothing pending").foregroundStyle(.secondary).padding(6)
                    }
                    ForEach(model.pendingReminders, id: \.id) { reminder in
                        ReminderRow(
                            text: reminder.text,
                            detail: model.reminders.dueLabel(reminder),
                            // Only a waiting reminder can be cancelled; one on the
                            // card is dismissed or snoozed there.
                            onCancel: reminder.status == .pending
                                ? { model.perform { model.reminders.cancel(reminder) } } : nil)
                    }
                    Divider().padding(.vertical, 4)
                    if model.reminderLog.isEmpty {
                        Text("No past reminders").foregroundStyle(.secondary).padding(6)
                    }
                    ForEach(model.reminderLog, id: \.id) { reminder in
                        ReminderRow(
                            text: reminder.text,
                            detail: model.reminders.logLabel(reminder),
                            onCancel: nil)
                    }
                    if !model.reminderLog.isEmpty {
                        Button("Clear Log…") { model.perform { model.reminders.clearLog() } }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .padding(6)
                    }
                }
            }
        }
        .padding(12)
    }

    /// Pure: reading the parser during body evaluation is fine, writing `@State`
    /// there is not — so the rejection travels back as a flag rather than as
    /// stored state.
    private var preview: (text: String, isProblem: Bool) {
        let trimmed = timeInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (" ", false) }
        switch model.reminders.parse(trimmed) {
        case .success(let date):
            return ("Fires at \(model.reminders.previewLabel(date))", false)
        case .failure(let failure):
            return (failure.message, true)
        }
    }

    private func add() {
        guard case .success(let date) = model.reminders.parse(timeInput) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.perform {
            if model.reminders.create(trimmed, date) == nil {
                text = ""
                timeInput = ""
            }
        }
    }
}

private struct ReminderRow: View {
    let text: String
    let detail: String
    let onCancel: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if hovering, let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Cancel")
            }
        }
        .padding(6)
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}

struct GeneralTab: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Start at Login", isOn: Binding(
                get: { model.startAtLogin },
                set: { on in model.perform { model.settings.setStartAtLogin(on) } }))
            Button("Check for Updates…") { model.updateAction() }
            Button("Open Accessibility Settings…") { model.settings.openAccessibilitySettings() }
            Spacer()
            Divider()
            Text("About").font(.caption).foregroundStyle(.secondary)
            Button("fappswap on GitHub") {
                NSWorkspace.shared.open(URL(string: "https://github.com/firatcansucu/fappswap")!)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
