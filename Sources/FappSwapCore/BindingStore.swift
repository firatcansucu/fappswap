import Foundation

struct BindingFile: Codable {
    var version: Int
    var bindings: [Binding]
}

/// Not thread-safe; expected to be used from the main thread only.
public final class BindingStore {
    public private(set) var bindings: [Binding] = []
    /// True when the last load found an unreadable file and started over.
    public private(set) var didRecoverFromCorruptFile = false

    private let url: URL

    public init(url: URL) {
        self.url = url
        load()
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("fappswap", isDirectory: true)
            .appendingPathComponent("bindings.json")
    }

    public func load() {
        didRecoverFromCorruptFile = false
        guard FileManager.default.fileExists(atPath: url.path) else {
            bindings = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            bindings = try JSONDecoder().decode(BindingFile.self, from: data).bindings
        } catch {
            // File exists but couldn't be read or decoded — back it up rather than
            // silently discarding it, so a later save() doesn't clobber real data.
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            bindings = []
            didRecoverFromCorruptFile = true
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(BindingFile(version: 1, bindings: bindings))
        try data.write(to: url, options: .atomic)
        // Mirrors `SnippetStore.save()`: owner-only, without relying on the
        // permissions of the directories above it.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func binding(keyCode: UInt16, modifiers: Set<Modifier>) -> Binding? {
        bindings.first { $0.matches(keyCode: keyCode, modifiers: modifiers) }
    }

    /// Adds the binding unless its key combination is already taken.
    @discardableResult
    public func add(_ binding: Binding) -> Bool {
        guard self.binding(keyCode: binding.keyCode, modifiers: binding.modifiers) == nil else {
            return false
        }
        bindings.append(binding)
        return true
    }

    public func remove(id: String) {
        bindings.removeAll { $0.id == id }
    }
}
