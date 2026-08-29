import FappSwapCore
import Foundation

/// What the editor dialog is working on. Separate from `Snippet` because a new
/// snippet has no id yet, and because edits must not touch the store until saved.
struct SnippetDraft {
    /// Nil for a new snippet; the existing snippet's id when editing.
    let snippetID: String?
    var trigger: String
    var replacement: String
}

/// Snippets and the prefix. Mutations report errors as return values — the
/// dialog shows them inline and stays open, the menu shows them in an alert.
final class SnippetsModel {
    private let store: SnippetStore
    private let onChange: () -> Void
    /// Set once at launch when the store had to recover; shown as a disabled
    /// line at the top of the Snippets submenu for the rest of the run.
    let recoveryNotice: String?

    init(store: SnippetStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        if store.didRecoverFromCorruptFile {
            recoveryNotice = "Your snippets file couldn't be read and was backed up "
                + "to snippets.json.bak. Starting with an empty list."
        } else if store.didResetInvalidPrefix {
            recoveryNotice = "The prefix in snippets.json wasn't usable, so it has been "
                + "reset to \(SnippetStore.defaultPrefix). Your snippets are unchanged."
        } else {
            recoveryNotice = nil
        }
    }

    var snippets: [Snippet] { store.snippets }
    var prefix: String { store.prefix }

    /// Validates and saves. Returns the message to show, or nil when saved.
    func save(_ draft: SnippetDraft) -> String? {
        let snippet = Snippet(
            id: draft.snippetID ?? UUID().uuidString,
            trigger: draft.trigger,
            replacement: draft.replacement)
        if let error = store.upsert(snippet) {
            return error.message
        }
        return persist()
    }

    func remove(_ snippet: Snippet) -> String? {
        store.remove(id: snippet.id)
        return persist()
    }

    func setPrefix(_ new: String) -> String? {
        if let error = store.setPrefix(new) {
            return error.message
        }
        return persist()
    }

    private func persist() -> String? {
        defer {
            // Rebuilds the running engine's match table — without this, edits
            // only take effect after a relaunch.
            onChange()
        }
        do {
            try store.save()
            return nil
        } catch {
            return "Could not save snippets: \(error.localizedDescription)"
        }
    }
}
