import Foundation

struct ClipboardHistoryFile: Codable {
    var version: Int
    var items: [ClipboardItem]
}

/// Owns `history.json` and the `images/` directory beside it. Not thread-safe;
/// main thread only, like `BindingStore` and `SnippetStore`, whose file
/// handling this mirrors. Every mutator saves before it returns, so the file
/// never lags the in-memory list.
public final class ClipboardHistoryStore {
    /// Newest first.
    public private(set) var items: [ClipboardItem] = []
    /// True when the last load found an unreadable file and started over.
    public private(set) var didRecoverFromCorruptFile = false

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("history.json") }
    public var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    /// Where `load()` moves an unreadable `history.json`. The only file that can
    /// hold a full copy of the user's history and isn't referenced by `items`,
    /// so `clear()` and a successful recovery both remove it explicitly.
    private var backupFileURL: URL { fileURL.appendingPathExtension("bak") }

    public init(directory: URL) {
        self.directory = directory
        load()
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("fappswap", isDirectory: true)
            .appendingPathComponent("clipboard", isDirectory: true)
    }

    public func load() {
        didRecoverFromCorruptFile = false
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                items = try JSONDecoder().decode(ClipboardHistoryFile.self, from: data).items
            } catch {
                try? FileManager.default.removeItem(at: backupFileURL)
                try? FileManager.default.moveItem(at: fileURL, to: backupFileURL)
                items = []
                didRecoverFromCorruptFile = true
            }
        } else {
            items = []
        }
        reconcileImageFiles()
    }

    public func save() throws {
        try ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ClipboardHistoryFile(version: 1, items: items))
        try data.write(to: fileURL, options: .atomic)
        // Clipboard contents are user content: owner-only, without relying on
        // the permissions of the directories above.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        // Once new history has been written, a backup from an earlier corrupt
        // file has no recovery value left, only exposure: it's a full copy of
        // whatever was recorded before. Cleared once so this only runs once
        // per recovery.
        if didRecoverFromCorruptFile {
            try? FileManager.default.removeItem(at: backupFileURL)
            didRecoverFromCorruptFile = false
        }
    }

    /// Creates the store's directories owner-only. Safe to call repeatedly.
    public func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [directory, imagesDirectory] {
            try fm.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
    }

    /// Records a text item at the top. Returns nil, recording nothing, for blank
    /// text or text over `RetentionPolicy.maxTextBytes`.
    @discardableResult
    public func recordText(_ text: String, sourceBundleID: String?, date: Date = Date()) throws -> ClipboardItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard text.utf8.count <= RetentionPolicy.maxTextBytes else { return nil }

        // Dedup: if the text already exists, move it to the top with a fresh timestamp
        // and new source bundle ID. Images are not deduplicated; comparing bytes would
        // mean reading files off disk, and a repeated identical screenshot is rare.
        if let index = items.firstIndex(where: { $0.text == text }) {
            let existing = items.remove(at: index)
            let moved = ClipboardItem(id: existing.id, date: date, sourceBundleID: sourceBundleID, content: existing.content)
            items.insert(moved, at: 0)
            try save()
            return moved
        }

        let item = ClipboardItem(date: date, sourceBundleID: sourceBundleID, content: .text(text))
        items.insert(item, at: 0)
        try save()
        return item
    }

    /// Records an image at the top. The caller has already decoded and encoded
    /// both representations — Core has no CoreGraphics. The files are written
    /// before the item is listed, so a crash between the two leaves an orphan
    /// file (cleaned up on the next load) rather than a listed item with no file.
    @discardableResult
    public func recordImage(
        png: Data, thumbnail: Data, pixelWidth: Int, pixelHeight: Int,
        sourceBundleID: String?, date: Date = Date()
    ) throws -> ClipboardItem {
        try ensureDirectories()
        let id = UUID()
        let ref = ClipboardItem.ImageRef(
            fileName: "\(id.uuidString).png",
            thumbnailFileName: "\(id.uuidString).thumb.png",
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, byteCount: png.count)
        for (name, data) in [(ref.fileName, png), (ref.thumbnailFileName, thumbnail)] {
            let url = imagesDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let item = ClipboardItem(id: id, date: date, sourceBundleID: sourceBundleID, content: .image(ref))
        items.insert(item, at: 0)
        try save()
        return item
    }

    public func imageURL(for item: ClipboardItem) -> URL? {
        item.imageRef.map { imagesDirectory.appendingPathComponent($0.fileName) }
    }

    public func thumbnailURL(for item: ClipboardItem) -> URL? {
        item.imageRef.map { imagesDirectory.appendingPathComponent($0.thumbnailFileName) }
    }

    /// Sum of the full-image file sizes, from the items' recorded byte counts.
    public var imageByteTotal: Int {
        items.reduce(0) { $0 + $1.imageByteCount }
    }

    /// Saves the list without `removed`, then deletes its files — never the other
    /// way around. If `save()` throws (a full disk, most plausibly), the
    /// in-memory list is put back exactly as it was and nothing gets destroyed:
    /// disk and memory still agree, and `removed` hasn't been deleted from
    /// either, so it can't come back changed on a later `load()`. This is what
    /// keeps `reconcileImageFiles()` safe — it trusts that an item still listed
    /// on disk still has its files, which only holds if a file is never deleted
    /// before the list that stops referencing it has actually been saved.
    public func remove(id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let previous = items
        let removed = items.remove(at: index)
        do {
            try save()
        } catch {
            items = previous
            throw error
        }
        deleteFiles(of: removed)
    }

    /// Same ordering as `remove`: the empty list is saved first, and only a
    /// successful save is followed by deleting every item's files. If `save()`
    /// throws, the previous list is restored and nothing is destroyed — see the
    /// comment on `remove(id:)` for why that order matters.
    public func clear() throws {
        let previous = items
        items = []
        do {
            try save()
        } catch {
            items = previous
            throw error
        }
        for item in previous { deleteFiles(of: item) }
        // Clear History means everything: a leftover backup from a past
        // corrupt-file recovery can hold a full plaintext dump and is the one
        // file `save()` above doesn't touch when there's nothing to recover from.
        try? FileManager.default.removeItem(at: backupFileURL)
    }

    /// Moves an item to the top with a new date — what pasting from the panel
    /// does, so the list reflects what you use, not only what you copy.
    public func touch(id: UUID, date: Date = Date()) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let existing = items.remove(at: index)
        items.insert(ClipboardItem(id: existing.id, date: date, sourceBundleID: existing.sourceBundleID,
                                   content: existing.content), at: 0)
        try save()
    }

    /// Deletes an image item's files. No-op for text. Failures are ignored: a
    /// file that is already gone is the outcome we wanted.
    func deleteFiles(of item: ClipboardItem) {
        guard let ref = item.imageRef else { return }
        for name in [ref.fileName, ref.thumbnailFileName] {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    /// Drops items whose image file is missing and deletes files no item
    /// references. Called at the end of every `load()`, so a crash between
    /// writing files and writing the list degrades into one lost item.
    private func reconcileImageFiles() {
        let fm = FileManager.default
        items.removeAll { item in
            guard let ref = item.imageRef else { return false }
            return !fm.fileExists(atPath: imagesDirectory.appendingPathComponent(ref.fileName).path)
        }
        var referenced = Set<String>()
        for ref in items.compactMap(\.imageRef) {
            referenced.insert(ref.fileName)
            referenced.insert(ref.thumbnailFileName)
        }
        let present = (try? fm.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
        for name in present where !referenced.contains(name) {
            try? fm.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    // MARK: - Retention

    /// What `prune` would remove, without removing it. Three passes in order:
    /// older than `days`; then the oldest beyond `maxItems`; then the oldest
    /// images until the image total is under `maxImageBytes`. Text is never
    /// removed by the byte pass.
    public func itemsToRemove(by policy: RetentionPolicy, now: Date = Date()) -> [ClipboardItem] {
        let cutoff = now.addingTimeInterval(-Double(policy.days.rawValue) * 86_400)
        var removed: [ClipboardItem] = []
        var kept: [ClipboardItem] = []
        for item in items {
            if item.date < cutoff { removed.append(item) } else { kept.append(item) }
        }
        if kept.count > policy.maxItems {
            removed.append(contentsOf: kept[policy.maxItems...])
            kept = Array(kept.prefix(policy.maxItems))
        }
        var imageBytes = kept.reduce(0) { $0 + $1.imageByteCount }
        var index = kept.count - 1
        while imageBytes > policy.maxImageBytes, index >= 0 {
            if kept[index].imageByteCount > 0 {
                imageBytes -= kept[index].imageByteCount
                removed.append(kept.remove(at: index))
            }
            index -= 1
        }
        return removed
    }

    /// For the "Delete N items?" confirmation. Never mutates.
    public func countThatWouldBeRemoved(by policy: RetentionPolicy, now: Date = Date()) -> Int {
        itemsToRemove(by: policy, now: now).count
    }

    /// Applies the policy: saves the pruned list first, and only then deletes
    /// the image files of everything removed — see the comment on `remove(id:)`
    /// for why. Saves only if something changed. If the save fails, the
    /// in-memory list is restored so nothing is removed from either place.
    /// Returns what was removed, for logging counts.
    @discardableResult
    public func prune(policy: RetentionPolicy, now: Date = Date()) throws -> [ClipboardItem] {
        let doomed = itemsToRemove(by: policy, now: now)
        guard !doomed.isEmpty else { return [] }
        let previous = items
        let ids = Set(doomed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        do {
            try save()
        } catch {
            items = previous
            throw error
        }
        for item in doomed { deleteFiles(of: item) }
        return doomed
    }

    // MARK: - Search

    /// Case- and diacritic-insensitive substring match over text items. An empty
    /// or whitespace query returns everything; any other query excludes images,
    /// which have nothing to match against.
    public func items(matching query: String) -> [ClipboardItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter { item in
            guard let text = item.text else { return false }
            return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
