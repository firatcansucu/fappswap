import Foundation
import Testing
@testable import FappSwapCore

func makeTempClipboardDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fappswap-clipboard-test-\(UUID().uuidString)", isDirectory: true)
}

private func permissions(at url: URL) throws -> Int? {
    try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
}

/// Sets or clears the BSD `uchg` (user immutable) flag on `url` via
/// `/usr/bin/chflags`. Used below to make `save()` fail without touching POSIX
/// permission bits: `save()` calls `ensureDirectories()`, which unconditionally
/// chmods the directory back to 0700 on every call, so a plain `chmod` of the
/// directory doesn't survive to the write that follows it. `chflags` isn't
/// touched by that reset, and it blocks creating the atomic write's temp file
/// even for the file's owner — while leaving whatever's already on disk
/// completely untouched, which is exactly the failure this simulates. Works
/// the same whether the test process is root or not, since `uchg` isn't a
/// permission check.
@discardableResult
private func chflags(_ flag: String, _ url: URL) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
    process.arguments = [flag, url.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

@Test func clipboardStoreStartsEmpty() {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    #expect(store.items.isEmpty)
    #expect(!store.didRecoverFromCorruptFile)
}

@Test func clipboardStoreRecordsTextNewestFirstAndReloads() throws {
    let dir = makeTempClipboardDirectory()
    let store = ClipboardHistoryStore(directory: dir)
    let first = try store.recordText("first", sourceBundleID: "com.apple.TextEdit",
                                     date: Date(timeIntervalSince1970: 1))
    let second = try store.recordText("second", sourceBundleID: nil,
                                      date: Date(timeIntervalSince1970: 2))
    #expect(first != nil && second != nil)
    #expect(store.items.map(\.text) == ["second", "first"])

    let reloaded = ClipboardHistoryStore(directory: dir)
    #expect(reloaded.items == store.items)
    #expect(reloaded.items[1].sourceBundleID == "com.apple.TextEdit")
}

@Test func clipboardStoreWritesTheDocumentedFileShape() throws {
    let dir = makeTempClipboardDirectory()
    let store = ClipboardHistoryStore(directory: dir)
    try store.recordText("hello", sourceBundleID: "com.apple.Safari")

    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
    #expect(json?["version"] as? Int == 1)
    let items = json?["items"] as? [[String: Any]]
    #expect(items?.count == 1)
    #expect(items?[0]["sourceBundleID"] as? String == "com.apple.Safari")
    #expect(items?[0]["id"] as? String != nil)
}

@Test func clipboardStoreRefusesBlankText() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    #expect(try store.recordText("", sourceBundleID: nil) == nil)
    #expect(try store.recordText("  \n\t ", sourceBundleID: nil) == nil)
    #expect(store.items.isEmpty)
}

@Test func clipboardStoreRefusesTextOverTheCap() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    let huge = String(repeating: "x", count: RetentionPolicy.maxTextBytes + 1)
    #expect(try store.recordText(huge, sourceBundleID: nil) == nil)
    let exact = String(repeating: "x", count: RetentionPolicy.maxTextBytes)
    #expect(try store.recordText(exact, sourceBundleID: nil) != nil)
}

@Test func clipboardStoreRemovesByIDAndClears() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    let a = try #require(try store.recordText("a", sourceBundleID: nil))
    try store.recordText("b", sourceBundleID: nil)
    try store.remove(id: a.id)
    #expect(store.items.map(\.text) == ["b"])
    try store.clear()
    #expect(store.items.isEmpty)
    #expect(ClipboardHistoryStore(directory: store.directory).items.isEmpty)
}

/// A failed save must not let a deletion "stick" only in memory: if `remove`
/// can't persist the new list, the item must still be exactly where it was,
/// in memory and on disk, so a later `load()` can't bring it back changed.
@Test func clipboardStoreRemoveLeavesEverythingInPlaceWhenSaveFails() throws {
    let dir = makeTempClipboardDirectory()
    let store = ClipboardHistoryStore(directory: dir)
    let a = try #require(try store.recordText("a", sourceBundleID: nil))
    try store.recordText("b", sourceBundleID: nil)
    let itemsBefore = store.items
    let jsonBefore = try Data(contentsOf: store.fileURL)

    chflags("uchg", dir)
    defer { chflags("nouchg", dir) }
    #expect(throws: (any Error).self) { try store.remove(id: a.id) }

    #expect(store.items == itemsBefore)
    #expect(try Data(contentsOf: store.fileURL) == jsonBefore)
}

/// Same guarantee for `clear`, and specifically checking that a failed save
/// leaves an image item's files on disk too — the point is that nothing was
/// destroyed, not just that the JSON list is unchanged.
@Test func clipboardStoreClearLeavesEverythingInPlaceIncludingImageFilesWhenSaveFails() throws {
    let dir = makeTempClipboardDirectory()
    let store = ClipboardHistoryStore(directory: dir)
    try store.recordText("a", sourceBundleID: nil)
    let image = try store.recordImage(png: fakePNG, thumbnail: fakeThumb, pixelWidth: 1, pixelHeight: 1, sourceBundleID: nil)
    let imageURL = try #require(store.imageURL(for: image))
    let thumbURL = try #require(store.thumbnailURL(for: image))
    let itemsBefore = store.items
    let jsonBefore = try Data(contentsOf: store.fileURL)

    chflags("uchg", dir)
    defer { chflags("nouchg", dir) }
    #expect(throws: (any Error).self) { try store.clear() }

    #expect(store.items == itemsBefore)
    #expect(try Data(contentsOf: store.fileURL) == jsonBefore)
    #expect(FileManager.default.fileExists(atPath: imageURL.path))
    #expect(FileManager.default.fileExists(atPath: thumbURL.path))
}

@Test func clipboardStoreWritesOwnerOnlyFilesAndDirectories() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    try store.recordText("hello", sourceBundleID: nil)
    #expect(try permissions(at: store.fileURL) == 0o600)
    #expect(try permissions(at: store.directory) == 0o700)
    #expect(try permissions(at: store.imagesDirectory) == 0o700)
}

@Test func clipboardStoreBacksUpAndRecoversFromCorruptFile() throws {
    let dir = makeTempClipboardDirectory()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("history.json")
    try Data("not json".utf8).write(to: file)

    let store = ClipboardHistoryStore(directory: dir)
    #expect(store.items.isEmpty)
    #expect(store.didRecoverFromCorruptFile)
    #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("bak").path))
}

@Test func clipboardStoreClearRemovesAnExistingBackupFile() throws {
    let dir = makeTempClipboardDirectory()
    let store = ClipboardHistoryStore(directory: dir)
    try store.recordText("a", sourceBundleID: nil)
    let backup = store.fileURL.appendingPathExtension("bak")
    try Data("stale backup".utf8).write(to: backup)

    try store.clear()
    #expect(!FileManager.default.fileExists(atPath: backup.path))
}

@Test func clipboardStoreRemovesTheBackupOnTheFirstSaveAfterRecovery() throws {
    let dir = makeTempClipboardDirectory()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("history.json")
    try Data("not json".utf8).write(to: file)
    let backup = file.appendingPathExtension("bak")

    let store = ClipboardHistoryStore(directory: dir)
    #expect(store.didRecoverFromCorruptFile)
    #expect(FileManager.default.fileExists(atPath: backup.path))

    try store.recordText("fresh start", sourceBundleID: nil)
    #expect(!FileManager.default.fileExists(atPath: backup.path))
    #expect(!store.didRecoverFromCorruptFile)
}

private let fakePNG = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
private let fakeThumb = Data([0x89, 0x50, 0x4E, 0x47, 9])

@Test func clipboardStoreRecordsAnImageAsTwoOwnerOnlyFiles() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    let item = try store.recordImage(
        png: fakePNG, thumbnail: fakeThumb, pixelWidth: 1280, pixelHeight: 800,
        sourceBundleID: "com.apple.screencaptureui")
    let ref = try #require(item.imageRef)
    #expect(ref.pixelWidth == 1280 && ref.pixelHeight == 800)
    #expect(ref.byteCount == fakePNG.count)
    #expect(ref.fileName == "\(item.id.uuidString).png")
    #expect(ref.thumbnailFileName == "\(item.id.uuidString).thumb.png")

    let full = try #require(store.imageURL(for: item))
    let thumb = try #require(store.thumbnailURL(for: item))
    #expect(try Data(contentsOf: full) == fakePNG)
    #expect(try Data(contentsOf: thumb) == fakeThumb)
    #expect(try permissions(at: full) == 0o600)
    #expect(try permissions(at: thumb) == 0o600)
    #expect(store.imageByteTotal == fakePNG.count)
    #expect(store.imageURL(for: ClipboardItem(date: Date(), sourceBundleID: nil, content: .text("t"))) == nil)
}

@Test func clipboardStoreDeletesImageFilesOnRemoveAndClear() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    let a = try store.recordImage(png: fakePNG, thumbnail: fakeThumb, pixelWidth: 1, pixelHeight: 1, sourceBundleID: nil)
    let b = try store.recordImage(png: fakePNG, thumbnail: fakeThumb, pixelWidth: 1, pixelHeight: 1, sourceBundleID: nil)
    let aURL = try #require(store.imageURL(for: a))
    let bURL = try #require(store.imageURL(for: b))
    let bThumb = try #require(store.thumbnailURL(for: b))

    try store.remove(id: a.id)
    #expect(!FileManager.default.fileExists(atPath: aURL.path))
    #expect(FileManager.default.fileExists(atPath: bURL.path))

    try store.clear()
    #expect(!FileManager.default.fileExists(atPath: bURL.path))
    #expect(!FileManager.default.fileExists(atPath: bThumb.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: store.imagesDirectory.path).isEmpty)
}

@Test func clipboardStoreDropsItemsWhoseImageFileIsMissingOnLoad() throws {
    let dir = makeTempClipboardDirectory()
    let store = ClipboardHistoryStore(directory: dir)
    let gone = try store.recordImage(png: fakePNG, thumbnail: fakeThumb, pixelWidth: 1, pixelHeight: 1, sourceBundleID: nil)
    try store.recordText("kept", sourceBundleID: nil)
    try FileManager.default.removeItem(at: try #require(store.imageURL(for: gone)))

    let reloaded = ClipboardHistoryStore(directory: dir)
    #expect(reloaded.items.map(\.text) == ["kept"])
    #expect(!reloaded.didRecoverFromCorruptFile)
}

@Test func clipboardStoreDeletesOrphanedImageFilesOnLoad() throws {
    let dir = makeTempClipboardDirectory()
    let store = ClipboardHistoryStore(directory: dir)
    try store.recordText("anything", sourceBundleID: nil)
    let orphan = store.imagesDirectory.appendingPathComponent("orphan.png")
    try fakePNG.write(to: orphan)

    _ = ClipboardHistoryStore(directory: dir)
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
}

private let day: TimeInterval = 86_400

@Test func clipboardStorePrunesByAge() throws {
    let now = Date(timeIntervalSince1970: 100 * day)
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    try store.recordText("old", sourceBundleID: nil, date: now.addingTimeInterval(-31 * day))
    try store.recordText("edge", sourceBundleID: nil, date: now.addingTimeInterval(-30 * day))
    try store.recordText("new", sourceBundleID: nil, date: now.addingTimeInterval(-1 * day))

    let policy = RetentionPolicy(days: .thirty)
    #expect(store.countThatWouldBeRemoved(by: policy, now: now) == 1)
    #expect(store.items.count == 3)  // counting never mutates

    let removed = try store.prune(policy: policy, now: now)
    #expect(removed.map(\.text) == ["old"])
    #expect(store.items.map(\.text) == ["new", "edge"])
}

@Test func clipboardStorePrunesOldestBeyondMaxItems() throws {
    let now = Date(timeIntervalSince1970: 100 * day)
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    for i in 0..<5 {
        try store.recordText("item \(i)", sourceBundleID: nil, date: now.addingTimeInterval(Double(i)))
    }
    let removed = try store.prune(policy: RetentionPolicy(days: .year, maxItems: 3), now: now)
    #expect(removed.map(\.text) == ["item 1", "item 0"])
    #expect(store.items.map(\.text) == ["item 4", "item 3", "item 2"])
}

@Test func clipboardStorePrunesOldestImagesUntilUnderTheByteCapLeavingText() throws {
    let now = Date(timeIntervalSince1970: 100 * day)
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    let png = Data(repeating: 0, count: 100)
    let oldImage = try store.recordImage(png: png, thumbnail: fakeThumb, pixelWidth: 1, pixelHeight: 1,
                                         sourceBundleID: nil, date: now.addingTimeInterval(1))
    try store.recordText("text between", sourceBundleID: nil, date: now.addingTimeInterval(2))
    let midImage = try store.recordImage(png: png, thumbnail: fakeThumb, pixelWidth: 1, pixelHeight: 1,
                                         sourceBundleID: nil, date: now.addingTimeInterval(3))
    let newImage = try store.recordImage(png: png, thumbnail: fakeThumb, pixelWidth: 1, pixelHeight: 1,
                                         sourceBundleID: nil, date: now.addingTimeInterval(4))
    let oldURL = try #require(store.imageURL(for: oldImage))

    let removed = try store.prune(policy: RetentionPolicy(days: .year, maxImageBytes: 150), now: now)
    #expect(removed.map(\.id) == [oldImage.id, midImage.id])  // oldest first
    #expect(store.items.first?.id == newImage.id)
    #expect(store.items.contains { $0.text == "text between" })
    #expect(store.imageByteTotal == 100)
    #expect(!FileManager.default.fileExists(atPath: oldURL.path))
}

@Test func clipboardStorePruneReturnsEmptyAndDoesNotSaveWhenNothingToDo() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    try store.recordText("fresh", sourceBundleID: nil)
    let before = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date
    #expect(try store.prune(policy: RetentionPolicy(days: .thirty)).isEmpty)
    let after = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date
    #expect(before == after)
}

/// Same guarantee for `prune`: a failed save must remove nothing, from memory
/// or from disk, even though there was genuinely something to prune.
@Test func clipboardStorePruneRemovesNothingWhenSaveFails() throws {
    let now = Date(timeIntervalSince1970: 100 * day)
    let dir = makeTempClipboardDirectory()
    let store = ClipboardHistoryStore(directory: dir)
    try store.recordText("old", sourceBundleID: nil, date: now.addingTimeInterval(-31 * day))
    try store.recordText("new", sourceBundleID: nil, date: now.addingTimeInterval(-1 * day))
    let itemsBefore = store.items
    let jsonBefore = try Data(contentsOf: store.fileURL)

    chflags("uchg", dir)
    defer { chflags("nouchg", dir) }
    #expect(throws: (any Error).self) {
        try store.prune(policy: RetentionPolicy(days: .thirty), now: now)
    }

    #expect(store.items == itemsBefore)
    #expect(try Data(contentsOf: store.fileURL) == jsonBefore)
}

@Test func clipboardStoreFiltersCaseInsensitivelyAndHidesImagesWhileSearching() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    try store.recordText("Search Google for it", sourceBundleID: nil)
    try store.recordText("nothing here", sourceBundleID: nil)
    let image = try store.recordImage(png: fakePNG, thumbnail: fakeThumb, pixelWidth: 1, pixelHeight: 1, sourceBundleID: nil)

    #expect(store.items(matching: "").count == 3)
    #expect(store.items(matching: "   ").count == 3)
    #expect(store.items(matching: "google").map(\.text) == ["Search Google for it"])
    #expect(store.items(matching: "GOOGLE").count == 1)
    #expect(store.items(matching: "zzz").isEmpty)
    #expect(!store.items(matching: "e").contains { $0.id == image.id })
}

@Test func clipboardStoreMovesARepeatedCopyToTheTop() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    let first = try #require(try store.recordText("same", sourceBundleID: "a", date: Date(timeIntervalSince1970: 1)))
    try store.recordText("other", sourceBundleID: nil, date: Date(timeIntervalSince1970: 2))
    let again = try #require(try store.recordText("same", sourceBundleID: "b", date: Date(timeIntervalSince1970: 3)))
    #expect(store.items.count == 2)
    #expect(store.items[0].text == "same")
    #expect(store.items[0].id == first.id)
    #expect(again.id == first.id)
    #expect(store.items[0].date == Date(timeIntervalSince1970: 3))
    #expect(store.items[0].sourceBundleID == "b")
}

@Test func clipboardStoreTouchMovesAnItemToTheTopWithAFreshDate() throws {
    let store = ClipboardHistoryStore(directory: makeTempClipboardDirectory())
    let a = try #require(try store.recordText("a", sourceBundleID: nil, date: Date(timeIntervalSince1970: 1)))
    try store.recordText("b", sourceBundleID: nil, date: Date(timeIntervalSince1970: 2))
    try store.touch(id: a.id, date: Date(timeIntervalSince1970: 3))
    #expect(store.items.map(\.text) == ["a", "b"])
    #expect(store.items[0].date == Date(timeIntervalSince1970: 3))
}
