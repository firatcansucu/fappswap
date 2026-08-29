import Foundation
import Testing
@testable import FappSwapCore

@Test func snippetPreviewFlattensNewlines() {
    let snippet = Snippet(trigger: "sig", replacement: "Jane Doe\njane@example.com")
    #expect(snippet.preview() == "Jane Doe⏎jane@example.com")
}

@Test func snippetPreviewFlattensCarriageReturnPairs() {
    let snippet = Snippet(trigger: "sig", replacement: "one\r\ntwo\rthree")
    #expect(snippet.preview() == "one⏎two⏎three")
}

@Test func snippetPreviewTruncatesLongText() {
    let snippet = Snippet(trigger: "long", replacement: String(repeating: "x", count: 100))
    let preview = snippet.preview(limit: 10)
    #expect(preview == String(repeating: "x", count: 10) + "…")
}

@Test func snippetPreviewLeavesShortTextAlone() {
    let snippet = Snippet(trigger: "short", replacement: "hello")
    #expect(snippet.preview(limit: 10) == "hello")
}

@Test func snippetGivesEachNewInstanceItsOwnIdentity() {
    let first = Snippet(trigger: "a", replacement: "x")
    let second = Snippet(trigger: "a", replacement: "x")
    #expect(first.id != second.id)
}

@Test func snippetRoundTripsThroughJSON() throws {
    let snippet = Snippet(id: "fixed-id", trigger: "sig", replacement: "line1\nline2")
    let data = try JSONEncoder().encode(snippet)
    let decoded = try JSONDecoder().decode(Snippet.self, from: data)
    #expect(decoded == snippet)
}
