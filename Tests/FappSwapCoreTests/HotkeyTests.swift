import Foundation
import Testing
@testable import FappSwapCore

@Test func hotkeyDisplayKeyOrdersModifiersLikeBindings() {
    let hotkey = Hotkey(keyCode: 9, modifiers: [.option, .command])
    #expect(hotkey.displayKey == "⌘⌥V")
    #expect(Hotkey.clipboardDefault == hotkey)
    #expect(Hotkey.windowCycle.displayKey == "⌥⇥")
}

@Test func hotkeyMatchesExactModifierSetsOnly() {
    let hotkey = Hotkey.clipboardDefault
    #expect(hotkey.matches(keyCode: 9, modifiers: [.option, .command]))
    #expect(!hotkey.matches(keyCode: 9, modifiers: [.command]))
    #expect(!hotkey.matches(keyCode: 9, modifiers: [.option, .command, .shift]))
    #expect(!hotkey.matches(keyCode: 8, modifiers: [.option, .command]))
}

@Test func hotkeyRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(Hotkey.clipboardDefault)
    #expect(try JSONDecoder().decode(Hotkey.self, from: data) == Hotkey.clipboardDefault)
}

@Test func bindingDisplayKeyStillMatchesHotkeyDisplayKey() {
    let binding = Binding(keyCode: 3, modifiers: [.option], bundleID: "x")
    #expect(binding.displayKey == "⌥F")
    #expect(binding.displayKey == Hotkey(keyCode: 3, modifiers: [.option]).displayKey)
}
