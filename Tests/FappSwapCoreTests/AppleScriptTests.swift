import Testing
@testable import FappSwapCore

@Test func quotedWrapsAnOrdinaryBundleIDInQuotes() {
    #expect(AppleScript.quoted("org.mozilla.firefox") == "\"org.mozilla.firefox\"")
}

@Test func quotedEscapesADoubleQuoteSoItCannotCloseTheLiteral() {
    // Without escaping, `x" to activate` would end the string literal and the
    // rest would be parsed as AppleScript statements.
    #expect(AppleScript.quoted("x\" to activate") == "\"x\\\" to activate\"")
}

@Test func quotedEscapesBackslashesBeforeQuotes() {
    // A lone trailing backslash must not escape the closing quote.
    #expect(AppleScript.quoted("a\\b") == "\"a\\\\b\"")
    #expect(AppleScript.quoted("trailing\\") == "\"trailing\\\\\"")
}

@Test func quotedEscapesNewlinesWhichAppleScriptCannotHoldLiterally() {
    #expect(AppleScript.quoted("a\nb") == "\"a\\nb\"")
    #expect(AppleScript.quoted("a\rb") == "\"a\\rb\"")
}

@Test func quotedLeavesNoUnescapedQuoteInsideTheLiteral() {
    let hostile = "x\" to activate\ntell application \"Calculator\" to activate\n--"
    let result = AppleScript.quoted(hostile)

    // Strip the outer quotes, then every legitimately escaped character.
    // Whatever remains must contain no bare quote and no bare backslash.
    let inner = String(result.dropFirst().dropLast())
    var stripped = ""
    var escaping = false
    for ch in inner {
        if escaping { escaping = false; continue }
        if ch == "\\" { escaping = true; continue }
        stripped.append(ch)
    }
    #expect(!stripped.contains("\""))
    #expect(result.hasPrefix("\"") && result.hasSuffix("\""))
}
