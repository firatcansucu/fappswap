import Foundation

public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    /// A UUID, not derived from the trigger: unlike a `Binding`, a snippet's
    /// trigger is editable, and the row has to keep its identity across an edit.
    public let id: String
    /// Stored **without** the prefix. The prefix is global (`SnippetStore.prefix`),
    /// so changing it rebinds every snippet at once.
    public var trigger: String
    public var replacement: String

    public init(id: String = UUID().uuidString, trigger: String, replacement: String) {
        self.id = id
        self.trigger = trigger
        self.replacement = replacement
    }

    /// One-line rendering for the Snippets submenu rows. Newlines become ⏎ so a
    /// multi-line snippet still occupies exactly one row.
    public func preview(limit: Int = 40) -> String {
        let flattened = replacement
            .replacingOccurrences(of: "\r\n", with: "⏎")
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\r", with: "⏎")
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)) + "…"
    }
}
