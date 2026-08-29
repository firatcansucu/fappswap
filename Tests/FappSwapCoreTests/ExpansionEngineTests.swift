import Testing
@testable import FappSwapCore

private func makeEngine(
    prefix: String = "§", _ snippets: [Snippet] = [Snippet(trigger: "sig", replacement: "SIGNATURE")]
) -> ExpansionEngine {
    let engine = ExpansionEngine()
    engine.update(prefix: prefix, snippets: snippets)
    return engine
}

/// Feeds a string one character at a time, returning the first decision that is
/// not `.none` — which is what the tap does, one keystroke per call.
private func type(_ text: String, into engine: ExpansionEngine) -> ExpansionDecision {
    for character in text {
        let decision = engine.consume(text: String(character))
        if decision != .none { return decision }
    }
    return .none
}

@Test func engineExpandsOnExactTriggerMatch() {
    let engine = makeEngine()
    #expect(type("§sig", into: engine) == .expand(deleteCount: 4, text: "SIGNATURE"))
}

@Test func engineDoesNotExpandOnPartialTrigger() {
    let engine = makeEngine()
    #expect(type("§si", into: engine) == .none)
}

@Test func engineDoesNotExpandWithoutThePrefix() {
    let engine = makeEngine()
    #expect(type("sig", into: engine) == .none)
}

@Test func engineExpandsMidSentence() {
    let engine = makeEngine()
    #expect(type("hello there §sig", into: engine) == .expand(deleteCount: 4, text: "SIGNATURE"))
}

@Test func engineIsCaseSensitive() {
    let engine = makeEngine()
    #expect(type("§Sig", into: engine) == .none)
}

@Test func engineClearsTheBufferAfterExpanding() {
    let engine = makeEngine()
    #expect(type("§sig", into: engine) == .expand(deleteCount: 4, text: "SIGNATURE"))
    #expect(engine.buffer.isEmpty)
    // A second expansion still works right after the first.
    #expect(type("§sig", into: engine) == .expand(deleteCount: 4, text: "SIGNATURE"))
}

@Test func engineCountsDeleteCountInGraphemes() {
    // "é" written as e + combining acute is two scalars but one grapheme, and
    // backspace deletes a grapheme — so "§" + "é" is 2 deletions, not the 3 a
    // scalar or UTF-16 count would give.
    let engine = makeEngine(prefix: "§", [Snippet(trigger: "e\u{301}", replacement: "X")])
    #expect(type("§e\u{301}", into: engine) == .expand(deleteCount: 2, text: "X"))
}

@Test func engineExpandsTheLongestMatchWhenTriggersOverlap() {
    // The store rejects overlapping triggers, but a hand-edited snippets.json can
    // still contain them, so the engine has to behave predictably.
    let engine = makeEngine(prefix: "§", [
        Snippet(trigger: "sig", replacement: "SHORT"),
        Snippet(trigger: "gsig", replacement: "LONG"),
    ])
    #expect(type("§gsig", into: engine) == .expand(deleteCount: 5, text: "LONG"))
}

@Test func engineCapsTheBufferAtPrefixPlusLongestTrigger() {
    let engine = makeEngine(prefix: "§", [Snippet(trigger: "sig", replacement: "X")])
    _ = type("abcdefghijklmnop", into: engine)
    #expect(engine.buffer.count == 4)
    #expect(engine.buffer == "mnop")
}

@Test func engineStillMatchesAfterTheBufferHasBeenTrimmed() {
    let engine = makeEngine()
    #expect(type("aaaaaaaaaaaa§sig", into: engine) == .expand(deleteCount: 4, text: "SIGNATURE"))
}

@Test func engineRetainsNothingWhenThereAreNoSnippets() {
    let engine = makeEngine(prefix: "§", [])
    #expect(type("§sig anything at all", into: engine) == .none)
    #expect(engine.buffer.isEmpty)
}

@Test func engineResetClearsTheBuffer() {
    let engine = makeEngine()
    _ = type("§si", into: engine)
    engine.reset()
    #expect(engine.buffer.isEmpty)
    // The half-typed trigger is gone, so finishing it must not fire.
    #expect(type("g", into: engine) == .none)
}

@Test func engineBackspaceDropsExactlyOneCharacter() {
    let engine = makeEngine()
    _ = type("§six", into: engine)
    #expect(engine.buffer == "§six")
    engine.consumeBackspace()
    #expect(engine.buffer == "§si")
    #expect(type("g", into: engine) == .expand(deleteCount: 4, text: "SIGNATURE"))
}

@Test func engineCannotRecoverATypoLongerThanTheBuffer() {
    // The cap is prefix + longest trigger, so a one-character typo is
    // recoverable (above) but a two-character one pushes the prefix out of the
    // buffer for good, and backspacing cannot bring it back. Deliberate: the
    // alternative is retaining more of what was typed than matching needs.
    let engine = makeEngine()
    _ = type("§sixg", into: engine)
    #expect(engine.buffer == "sixg")
    engine.consumeBackspace()
    engine.consumeBackspace()
    #expect(type("g", into: engine) == .none)
}

@Test func engineBackspaceOnEmptyBufferIsHarmless() {
    let engine = makeEngine()
    engine.consumeBackspace()
    #expect(engine.buffer.isEmpty)
}

@Test func engineUpdateClearsTheBuffer() {
    let engine = makeEngine()
    _ = type("§si", into: engine)
    engine.update(prefix: "§", snippets: [Snippet(trigger: "sig", replacement: "SIGNATURE")])
    #expect(engine.buffer.isEmpty)
}

@Test func engineFollowsAPrefixChange() {
    let engine = makeEngine()
    engine.update(prefix: ":", snippets: [Snippet(trigger: "sig", replacement: "SIGNATURE")])
    #expect(type("§sig", into: engine) == .none)
    #expect(type(":sig", into: engine) == .expand(deleteCount: 4, text: "SIGNATURE"))
}

@Test func engineHandlesAMultiCharacterInputString() {
    // Dead keys and some input methods deliver more than one character at once.
    let engine = makeEngine()
    #expect(engine.consume(text: "§sig") == .expand(deleteCount: 4, text: "SIGNATURE"))
}
