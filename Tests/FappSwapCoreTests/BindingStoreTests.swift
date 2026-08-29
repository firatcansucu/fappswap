import Foundation
import Testing
@testable import FappSwapCore

private func makeTempURL() -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fappswap-test-\(UUID().uuidString)")
    return dir.appendingPathComponent("bindings.json")
}

@Test func storeStartsEmptyWhenNoFileExists() {
    let store = BindingStore(url: makeTempURL())
    #expect(store.bindings.isEmpty)
    #expect(!store.didRecoverFromCorruptFile)
}

@Test func storeSavesAndReloadsBindings() throws {
    let url = makeTempURL()
    let store = BindingStore(url: url)
    #expect(store.add(Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")))
    try store.save()

    let reloaded = BindingStore(url: url)
    #expect(reloaded.bindings.count == 1)
    #expect(reloaded.bindings[0].bundleID == "org.mozilla.firefox")
}

@Test func storeWritesTheDocumentedFileShape() throws {
    let url = makeTempURL()
    let store = BindingStore(url: url)
    #expect(store.add(Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")))
    try store.save()

    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect(json?["version"] as? Int == 1)
    let bindings = json?["bindings"] as? [[String: Any]]
    #expect(bindings?.count == 1)
    #expect(bindings?[0]["bundleID"] as? String == "org.mozilla.firefox")
    #expect(bindings?[0]["keyCode"] as? Int == 3)
    #expect(bindings?[0]["modifiers"] as? [String] == ["option"])
}

@Test func storeLooksUpBindingsByKeyCodeAndModifiers() throws {
    let store = BindingStore(url: makeTempURL())
    #expect(store.add(Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")))

    #expect(store.binding(keyCode: 3, modifiers: [.option])?.bundleID == "org.mozilla.firefox")
    #expect(store.binding(keyCode: 3, modifiers: [.option, .shift]) == nil)
    #expect(store.binding(keyCode: 4, modifiers: [.option]) == nil)
}

@Test func storeBacksUpAndRecoversFromUnreadableFile() throws {
    // root bypasses POSIX permissions, so the unreadable file wouldn't actually
    // be unreadable and this test would fail to exercise the recovery path.
    guard getuid() != 0 else { return }

    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version":1,"bindings":[]}"#.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)

    let store = BindingStore(url: url)
    #expect(store.bindings.isEmpty)
    #expect(store.didRecoverFromCorruptFile)
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
}

@Test func storeBacksUpAndRecoversFromCorruptFile() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("this is not json".utf8).write(to: url)

    let store = BindingStore(url: url)
    #expect(store.bindings.isEmpty)
    #expect(store.didRecoverFromCorruptFile)
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
}

@Test func storeTreatsUnknownModifierAsCorrupt() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let bad = #"{"version":1,"bindings":[{"keyCode":3,"modifiers":["hyper"],"bundleID":"x"}]}"#
    try Data(bad.utf8).write(to: url)

    let store = BindingStore(url: url)
    #expect(store.bindings.isEmpty)
    #expect(store.didRecoverFromCorruptFile)
}

@Test func storeRejectsDuplicateKeyCombination() {
    let store = BindingStore(url: makeTempURL())
    #expect(store.add(Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")))
    #expect(!store.add(Binding(keyCode: 3, modifiers: [.option], bundleID: "md.obsidian")))
    #expect(store.bindings.count == 1)
    #expect(store.bindings[0].bundleID == "org.mozilla.firefox")
}

@Test func storeAllowsSameKeyWithDifferentModifiers() {
    let store = BindingStore(url: makeTempURL())
    #expect(store.add(Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")))
    #expect(store.add(Binding(keyCode: 3, modifiers: [.option, .shift], bundleID: "md.obsidian")))
    #expect(store.bindings.count == 2)
}

@Test func storeRemovesBindingByID() throws {
    let url = makeTempURL()
    let store = BindingStore(url: url)
    let binding = Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")
    #expect(store.add(binding))
    store.remove(id: binding.id)
    try store.save()

    #expect(BindingStore(url: url).bindings.isEmpty)
}

@Test func storeWritesTheFileReadableOnlyByItsOwner() throws {
    let url = makeTempURL()
    let store = BindingStore(url: url)
    store.add(Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox"))
    try store.save()

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
}
