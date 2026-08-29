import Foundation
import Testing
@testable import FappSwapCore

private func makeTempURL() -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fappswap-test-\(UUID().uuidString)")
    return dir.appendingPathComponent("snippets.json")
}

@Test func snippetStoreStartsEmptyWithTheDefaultPrefix() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.snippets.isEmpty)
    #expect(store.prefix == "§")
    #expect(!store.didRecoverFromCorruptFile)
}

@Test func snippetStoreSavesAndReloadsSnippetsAndPrefix() throws {
    let url = makeTempURL()
    let store = SnippetStore(url: url)
    #expect(store.upsert(Snippet(trigger: "sig", replacement: "line1\nline2")) == nil)
    #expect(store.setPrefix(":") == nil)
    try store.save()

    let reloaded = SnippetStore(url: url)
    #expect(reloaded.prefix == ":")
    #expect(reloaded.snippets.count == 1)
    #expect(reloaded.snippets[0].trigger == "sig")
    #expect(reloaded.snippets[0].replacement == "line1\nline2")
}

@Test func snippetStoreWritesTheDocumentedFileShape() throws {
    let url = makeTempURL()
    let store = SnippetStore(url: url)
    #expect(store.upsert(Snippet(id: "fixed", trigger: "sig", replacement: "text")) == nil)
    try store.save()

    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect(json?["version"] as? Int == 1)
    #expect(json?["prefix"] as? String == "§")
    let snippets = json?["snippets"] as? [[String: Any]]
    #expect(snippets?.count == 1)
    #expect(snippets?[0]["id"] as? String == "fixed")
    #expect(snippets?[0]["trigger"] as? String == "sig")
    #expect(snippets?[0]["replacement"] as? String == "text")
}

@Test func snippetStoreBacksUpAndRecoversFromCorruptFile() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("this is not json".utf8).write(to: url)

    let store = SnippetStore(url: url)
    #expect(store.snippets.isEmpty)
    #expect(store.prefix == "§")
    #expect(store.didRecoverFromCorruptFile)
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
}

@Test func snippetStoreUpdatesAnExistingSnippetInPlace() {
    let store = SnippetStore(url: makeTempURL())
    let original = Snippet(id: "same", trigger: "sig", replacement: "old")
    #expect(store.upsert(original) == nil)
    #expect(store.upsert(Snippet(id: "same", trigger: "sig", replacement: "new")) == nil)
    #expect(store.snippets.count == 1)
    #expect(store.snippets[0].replacement == "new")
}

@Test func snippetStoreRemovesByID() {
    let store = SnippetStore(url: makeTempURL())
    let snippet = Snippet(trigger: "sig", replacement: "text")
    #expect(store.upsert(snippet) == nil)
    store.remove(id: snippet.id)
    #expect(store.snippets.isEmpty)
}

@Test func snippetStoreRejectsEmptyTriggerAndReplacement() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.upsert(Snippet(trigger: "", replacement: "text")) == .emptyTrigger)
    #expect(store.upsert(Snippet(trigger: "sig", replacement: "")) == .emptyReplacement)
    #expect(store.snippets.isEmpty)
}

@Test func snippetStoreRejectsWhitespaceInTrigger() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.upsert(Snippet(trigger: "my sig", replacement: "text")) == .whitespaceInTrigger)
}

@Test func snippetStoreRejectsTriggerContainingThePrefix() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.upsert(Snippet(trigger: "s§g", replacement: "text"))
        == .triggerContainsPrefix("§"))
}

@Test func snippetStoreRejectsDuplicateTrigger() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.upsert(Snippet(trigger: "sig", replacement: "one")) == nil)
    #expect(store.upsert(Snippet(trigger: "sig", replacement: "two"))
        == .duplicateTrigger("§sig"))
    #expect(store.snippets.count == 1)
}

@Test func snippetStoreRejectsTriggerThatCollidesByPrefixEitherWay() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.upsert(Snippet(trigger: "sig", replacement: "one")) == nil)
    // Longer trigger whose start is an existing trigger.
    #expect(store.upsert(Snippet(trigger: "sign", replacement: "two"))
        == .collidingTrigger(existing: "§sig"))
    // And the reverse: shorter trigger that starts an existing one.
    let other = SnippetStore(url: makeTempURL())
    #expect(other.upsert(Snippet(trigger: "sign", replacement: "one")) == nil)
    #expect(other.upsert(Snippet(trigger: "sig", replacement: "two"))
        == .collidingTrigger(existing: "§sign"))
}

@Test func snippetStoreAllowsUnrelatedTriggers() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.upsert(Snippet(trigger: "sig", replacement: "one")) == nil)
    #expect(store.upsert(Snippet(trigger: "addr", replacement: "two")) == nil)
    #expect(store.snippets.count == 2)
}

@Test func snippetStoreLetsASnippetKeepItsOwnTriggerWhenEdited() {
    let store = SnippetStore(url: makeTempURL())
    let snippet = Snippet(id: "same", trigger: "sig", replacement: "one")
    #expect(store.upsert(snippet) == nil)
    // Editing only the replacement must not trip the duplicate check against itself.
    #expect(store.upsert(Snippet(id: "same", trigger: "sig", replacement: "two")) == nil)
}

@Test func snippetStoreRejectsBadPrefixes() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.setPrefix("") == .prefixNotSingleCharacter)
    #expect(store.setPrefix("::") == .prefixNotSingleCharacter)
    #expect(store.setPrefix("a") == .prefixNotPunctuation)
    #expect(store.setPrefix("7") == .prefixNotPunctuation)
    #expect(store.setPrefix(" ") == .prefixNotPunctuation)
    #expect(store.prefix == "§")
}

@Test func snippetStoreAcceptsPunctuationPrefixes() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.setPrefix(":") == nil)
    #expect(store.prefix == ":")
    #expect(store.setPrefix(";") == nil)
    #expect(store.prefix == ";")
}

@Test func snippetStoreRejectsPrefixAlreadyUsedInsideATrigger() {
    let store = SnippetStore(url: makeTempURL())
    #expect(store.upsert(Snippet(trigger: "a:b", replacement: "text")) == nil)
    #expect(store.setPrefix(":") == .prefixUsedInExistingTrigger("a:b"))
    #expect(store.prefix == "§")
}

@Test func snippetStoreValidationErrorsAllCarryAMessage() {
    let errors: [SnippetValidationError] = [
        .emptyTrigger, .emptyReplacement, .whitespaceInTrigger,
        .triggerContainsPrefix("§"), .duplicateTrigger("§sig"),
        .collidingTrigger(existing: "§sig"), .prefixNotSingleCharacter,
        .prefixNotPunctuation, .prefixUsedInExistingTrigger("a:b"),
    ]
    for error in errors {
        #expect(!error.message.isEmpty)
    }
}

@Test func snippetStoreWritesTheFileReadableOnlyByItsOwner() throws {
    let url = makeTempURL()
    let store = SnippetStore(url: url)
    #expect(store.upsert(Snippet(trigger: "sig", replacement: "text")) == nil)
    try store.save()

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
}

@Test func snippetStoreResetsAnEmptyPrefixOnLoadAndKeepsTheSnippets() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = """
        {"version": 1, "prefix": "", "snippets": [{"id": "a", "trigger": "sig", "replacement": "text"}]}
        """
    try Data(json.utf8).write(to: url)

    let store = SnippetStore(url: url)
    #expect(store.prefix == "§")
    #expect(store.snippets.count == 1)
    #expect(store.didResetInvalidPrefix)
    #expect(!store.didRecoverFromCorruptFile)
}

@Test func snippetStoreResetsALetterPrefixOnLoad() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version": 1, "prefix": "ab", "snippets": []}"#.utf8).write(to: url)

    let store = SnippetStore(url: url)
    #expect(store.prefix == "§")
    #expect(store.didResetInvalidPrefix)
}

@Test func snippetStoreKeepsAValidPrefixOnLoad() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version": 1, "prefix": ":", "snippets": []}"#.utf8).write(to: url)

    let store = SnippetStore(url: url)
    #expect(store.prefix == ":")
    #expect(!store.didResetInvalidPrefix)
}
