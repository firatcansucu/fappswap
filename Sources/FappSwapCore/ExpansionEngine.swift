public enum ExpansionDecision: Equatable, Sendable {
    case none
    /// Delete `deleteCount` graphemes backwards, then insert `text`.
    case expand(deleteCount: Int, text: String)
}

/// Holds the short rolling buffer of recent typing and decides when a trigger has
/// been completed.
///
/// Deliberately free of AppKit and CoreGraphics: everything about matching is
/// testable without a running app or an event tap. Not thread-safe — the tap
/// callback and this engine both live on the main thread.
///
/// The buffer never holds more than prefix + longest trigger characters, so the
/// app does not accumulate a transcript of what was typed.
public final class ExpansionEngine {
    public private(set) var buffer = ""

    /// Full match strings (prefix + trigger) with their replacements, longest
    /// first, so the first suffix hit is also the longest one.
    private var candidates: [(match: String, replacement: String)] = []
    private var capacity = 0

    public init() {}

    /// Replaces the snippet set. Clears the buffer, since a half-typed trigger
    /// may no longer exist.
    public func update(prefix: String, snippets: [Snippet]) {
        candidates = snippets
            .map { (match: prefix + $0.trigger, replacement: $0.replacement) }
            .sorted { $0.match.count > $1.match.count }
        capacity = candidates.first?.match.count ?? 0
        reset()
    }

    public func reset() {
        buffer = ""
    }

    public func consumeBackspace() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
    }

    /// Feeds typed text in. `text` is usually one character, but dead keys and
    /// some input methods deliver several at once, so each is checked in turn and
    /// the first match wins.
    public func consume(text: String) -> ExpansionDecision {
        guard capacity > 0 else { return .none }
        for character in text {
            buffer.append(character)
            if buffer.count > capacity {
                buffer.removeFirst(buffer.count - capacity)
            }
            if let hit = candidates.first(where: { buffer.hasSuffix($0.match) }) {
                reset()
                return .expand(deleteCount: hit.match.count, text: hit.replacement)
            }
        }
        return .none
    }
}
