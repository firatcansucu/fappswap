import Testing
import CoreGraphics
import Foundation
@testable import FappSwapCore

@Test func modifierSetFromFlagsReadsTheFourRealModifiers() {
    let flags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    #expect(Modifier.set(from: flags) == [.command, .control, .option, .shift])
}

@Test func modifierSetIgnoresCapsLockAndDeviceBits() {
    let flags: CGEventFlags = [.maskAlternate, .maskAlphaShift, .maskNonCoalesced, .maskSecondaryFn]
    #expect(Modifier.set(from: flags) == [.option])
}

@Test func modifierSetIsEmptyForPlainKeypress() {
    #expect(Modifier.set(from: CGEventFlags()) == [])
}

@Test func modifierSymbolsMatchTheirKeys() {
    #expect(Modifier.allCases.map(\.symbol) == ["⌘", "⌃", "⌥", "⇧"])
}

@Test func bindingMatchesExactKeyCodeAndModifierSet() {
    let firefox = Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")
    #expect(firefox.matches(keyCode: 3, modifiers: [.option]))
}

@Test func bindingRejectsExtraOrMissingModifiers() {
    let firefox = Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")
    #expect(!firefox.matches(keyCode: 3, modifiers: [.option, .shift]))
    #expect(!firefox.matches(keyCode: 3, modifiers: []))
}

@Test func bindingRejectsDifferentKeyCode() {
    let firefox = Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")
    #expect(!firefox.matches(keyCode: 31, modifiers: [.option]))
}

@Test func bindingIdDependsOnKeyComboNotApp() {
    let a = Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")
    let b = Binding(keyCode: 3, modifiers: [.option], bundleID: "com.other.app")
    let c = Binding(keyCode: 3, modifiers: [.option, .shift], bundleID: "org.mozilla.firefox")
    #expect(a.id == b.id)
    #expect(a.id != c.id)
}

@Test func bindingIdSortsModifiersRegardlessOfConstructionOrder() {
    let b = Binding(keyCode: 3, modifiers: [.shift, .control, .command, .option], bundleID: "x")
    #expect(b.id == "3-command+control+option+shift")
}

@Test func bindingDisplayKeyRendersSymbolsInStableOrder() {
    let b = Binding(keyCode: 3, modifiers: [.shift, .option], bundleID: "x")
    #expect(b.displayKey == "⌥⇧F")
}

@Test func bindingRoundTripsThroughJSON() throws {
    let original = Binding(keyCode: 3, modifiers: [.option], bundleID: "org.mozilla.firefox")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Binding.self, from: data)
    #expect(decoded == original)
}
