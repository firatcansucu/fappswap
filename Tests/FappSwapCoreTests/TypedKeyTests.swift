import Testing
@testable import FappSwapCore

@Test func typedKeyClassifiesOrdinaryCharactersAsText() {
    #expect(TypedKey.classify(keyCode: 0, modifiers: [], text: "a") == .text("a"))
    #expect(TypedKey.classify(keyCode: 0, modifiers: [.shift], text: "A") == .text("A"))
    // Option-layer characters are still text — only the bound ones get swallowed,
    // and those never reach this function.
    #expect(TypedKey.classify(keyCode: 3, modifiers: [.option], text: "ƒ") == .text("ƒ"))
    // The section key, which is what the default prefix is typed with on ISO layouts.
    #expect(TypedKey.classify(keyCode: 10, modifiers: [], text: "§") == .text("§"))
}

@Test func typedKeyTreatsSpaceAsOrdinaryText() {
    // Deliberate: space advances the buffer, it does not reset it.
    #expect(TypedKey.classify(keyCode: 49, modifiers: [], text: " ") == .text(" "))
}

@Test func typedKeyClassifiesDeleteAsBackspace() {
    #expect(TypedKey.classify(keyCode: 51, modifiers: [], text: "\u{8}") == .backspace)
}

@Test func typedKeyClassifiesWordEndingKeysAsBoundary() {
    for keyCode in [UInt16(36), 76, 48, 53, 117, 115, 119, 116, 121, 123, 124, 125, 126] {
        #expect(TypedKey.classify(keyCode: keyCode, modifiers: [], text: "") == .boundary)
    }
}

@Test func typedKeyClassifiesCommandAndControlChordsAsBoundary() {
    #expect(TypedKey.classify(keyCode: 8, modifiers: [.command], text: "c") == .boundary)
    #expect(TypedKey.classify(keyCode: 0, modifiers: [.control], text: "a") == .boundary)
    #expect(TypedKey.classify(keyCode: 8, modifiers: [.command, .shift], text: "c") == .boundary)
}

@Test func typedKeyClassifiesEmptyAndControlCharactersAsBoundary() {
    #expect(TypedKey.classify(keyCode: 200, modifiers: [], text: "") == .boundary)
    #expect(TypedKey.classify(keyCode: 200, modifiers: [], text: "\u{1B}") == .boundary)
    #expect(TypedKey.classify(keyCode: 200, modifiers: [], text: "\u{7F}") == .boundary)
}
