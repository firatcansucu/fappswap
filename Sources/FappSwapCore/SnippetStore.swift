import Foundation

struct SnippetFile: Codable {
    var version: Int
    var prefix: String
    var snippets: [Snippet]
}

/// Not thread-safe; expected to be used from the main thread only, like
/// `BindingStore`, whose file handling this deliberately mirrors.
public final class SnippetStore {
    public static let defaultPrefix = "§"

    public private(set) var snippets: [Snippet] = []
    /// The one character that starts every trigger. Stored here rather than on
    /// each `Snippet` so changing it rebinds all of them at once.
    public private(set) var prefix = SnippetStore.defaultPrefix
    /// True when the last load found an unreadable file and started over.
    public private(set) var didRecoverFromCorruptFile = false
    /// True when the last load found a prefix that breaks the rules `setPrefix`
    /// enforces and fell back to the default, keeping the snippets.
    public private(set) var didResetInvalidPrefix = false

    private let url: URL

    public init(url: URL) {
        self.url = url
        load()
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("fappswap", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    public func load() {
        didRecoverFromCorruptFile = false
        didResetInvalidPrefix = false
        guard FileManager.default.fileExists(atPath: url.path) else {
            snippets = []
            prefix = Self.defaultPrefix
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(SnippetFile.self, from: data)
            snippets = file.snippets
            // The file is hand-editable, so the prefix rules are re-checked on
            // the way in. An empty prefix would otherwise make every trigger
            // fire bare and every new one fail validation with a blank message.
            // Not treated as corruption: the snippets are fine, only the prefix
            // is dropped.
            if Self.validatePrefix(file.prefix) == nil {
                prefix = file.prefix
            } else {
                prefix = Self.defaultPrefix
                didResetInvalidPrefix = true
            }
        } catch {
            // File exists but couldn't be read or decoded — back it up rather than
            // silently discarding it, so a later save() doesn't clobber real data.
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            snippets = []
            prefix = Self.defaultPrefix
            didRecoverFromCorruptFile = true
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = SnippetFile(version: 1, prefix: prefix, snippets: snippets)
        try encoder.encode(file).write(to: url, options: .atomic)
        // Snippets are user content. `~/Library` is owner-only on a stock Mac,
        // but the file should not rely on that.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Checks a candidate trigger and replacement against every rule. Pass the
    /// id of the snippet being edited so it isn't compared against itself.
    public func validate(
        trigger: String, replacement: String, excludingID id: String? = nil
    ) -> SnippetValidationError? {
        if trigger.isEmpty { return .emptyTrigger }
        if replacement.isEmpty { return .emptyReplacement }
        if trigger.contains(where: \.isWhitespace) { return .whitespaceInTrigger }
        if trigger.contains(prefix) { return .triggerContainsPrefix(prefix) }
        for existing in snippets where existing.id != id {
            if existing.trigger == trigger {
                return .duplicateTrigger(prefix + trigger)
            }
            // Expansion fires immediately, so of two triggers where one starts the
            // other, only the shorter can ever fire. Rejected rather than silently
            // shadowed — see the design doc's Detection section.
            if existing.trigger.hasPrefix(trigger) || trigger.hasPrefix(existing.trigger) {
                return .collidingTrigger(existing: prefix + existing.trigger)
            }
        }
        return nil
    }

    /// Adds the snippet, or replaces the one with the same id. Returns nil on
    /// success, or why it was rejected.
    @discardableResult
    public func upsert(_ snippet: Snippet) -> SnippetValidationError? {
        if let error = validate(
            trigger: snippet.trigger,
            replacement: snippet.replacement,
            excludingID: snippet.id
        ) {
            return error
        }
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        return nil
    }

    public func remove(id: String) {
        snippets.removeAll { $0.id == id }
    }

    /// The rules a prefix must satisfy on its own, independent of the snippets.
    /// Shared by `setPrefix` and `load`, so a hand-edited file is held to the
    /// same standard as the Change Prefix dialog.
    static func validatePrefix(_ candidate: String) -> SnippetValidationError? {
        guard candidate.count == 1, let character = candidate.first else {
            return .prefixNotSingleCharacter
        }
        if character.isLetter || character.isNumber || character.isWhitespace {
            return .prefixNotPunctuation
        }
        return nil
    }

    /// Returns nil on success, or why the prefix was rejected.
    @discardableResult
    public func setPrefix(_ newPrefix: String) -> SnippetValidationError? {
        if let error = Self.validatePrefix(newPrefix) { return error }
        guard let character = newPrefix.first else { return .prefixNotSingleCharacter }
        // Keeps the "no trigger contains the prefix" invariant true in both
        // directions — otherwise a prefix change could break it retroactively.
        if let clash = snippets.first(where: { $0.trigger.contains(character) }) {
            return .prefixUsedInExistingTrigger(clash.trigger)
        }
        prefix = newPrefix
        return nil
    }
}
