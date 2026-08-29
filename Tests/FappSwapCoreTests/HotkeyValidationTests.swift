import Foundation
import Testing
@testable import FappSwapCore

private let optF = Hotkey(keyCode: 3, modifiers: [.option])
private let optG = Hotkey(keyCode: 5, modifiers: [.option])
private let bindings = [Binding(keyCode: 3, modifiers: [.option], bundleID: "com.example.f")]

@Test func bindingRefusesNoModifier() {
    let plainF = Hotkey(keyCode: 3, modifiers: [])
    #expect(HotkeyValidation.forBinding(plainF, bindings: [], clipboardHotkey: nil, reminderHotkey: .reminderDefault) == .noModifier)
    #expect(HotkeyValidation.forClipboard(plainF, bindings: [], reminderHotkey: .reminderDefault) == .noModifier)
    #expect(HotkeyValidation.forReminder(plainF, bindings: [], clipboardHotkey: nil) == .noModifier)
}

@Test func bindingRefusesWindowCycleOnAllPaths() {
    #expect(HotkeyValidation.forBinding(.windowCycle, bindings: [], clipboardHotkey: nil, reminderHotkey: .reminderDefault) == .windowCycle)
    #expect(HotkeyValidation.forClipboard(.windowCycle, bindings: [], reminderHotkey: .reminderDefault) == .windowCycle)
    #expect(HotkeyValidation.forReminder(.windowCycle, bindings: [], clipboardHotkey: nil) == .windowCycle)
}

@Test func bindingRefusesExistingBinding() {
    #expect(HotkeyValidation.forBinding(optF, bindings: bindings, clipboardHotkey: nil, reminderHotkey: .reminderDefault) == .existingBinding)
    #expect(HotkeyValidation.forClipboard(optF, bindings: bindings, reminderHotkey: .reminderDefault) == .existingBinding)
    #expect(HotkeyValidation.forReminder(optF, bindings: bindings, clipboardHotkey: nil) == .existingBinding)
}

@Test func bindingRefusesClipboardHotkeyOnlyWhenOneIsPassed() {
    #expect(HotkeyValidation.forBinding(.clipboardDefault, bindings: [], clipboardHotkey: .clipboardDefault, reminderHotkey: .reminderDefault) == .clipboardHotkey)
    #expect(HotkeyValidation.forReminder(.clipboardDefault, bindings: [], clipboardHotkey: .clipboardDefault) == .clipboardHotkey)
    // Clipboard history off: the combination is genuinely free.
    #expect(HotkeyValidation.forBinding(.clipboardDefault, bindings: [], clipboardHotkey: nil, reminderHotkey: .reminderDefault) == nil)
    #expect(HotkeyValidation.forReminder(.clipboardDefault, bindings: [], clipboardHotkey: nil) == nil)
}

@Test func bindingAndClipboardRefuseTheReminderHotkey() {
    #expect(HotkeyValidation.forBinding(.reminderDefault, bindings: [], clipboardHotkey: nil, reminderHotkey: .reminderDefault) == .reminderHotkey)
    #expect(HotkeyValidation.forClipboard(.reminderDefault, bindings: [], reminderHotkey: .reminderDefault) == .reminderHotkey)
    // A reminder hotkey moved elsewhere frees ⌥R.
    #expect(HotkeyValidation.forBinding(.reminderDefault, bindings: [], clipboardHotkey: nil, reminderHotkey: optG) == nil)
}

@Test func clipboardAndReminderCandidatesEqualToThemselvesAreNotConflicts() {
    // The caller passes the *other* reserved hotkeys only; re-recording the same
    // combination is a no-op, not a conflict.
    #expect(HotkeyValidation.forClipboard(.clipboardDefault, bindings: bindings, reminderHotkey: .reminderDefault) == nil)
    #expect(HotkeyValidation.forReminder(.reminderDefault, bindings: bindings, clipboardHotkey: .clipboardDefault) == nil)
}

@Test func freeCombinationPassesAllPaths() {
    #expect(HotkeyValidation.forBinding(optG, bindings: bindings, clipboardHotkey: .clipboardDefault, reminderHotkey: .reminderDefault) == nil)
    #expect(HotkeyValidation.forClipboard(optG, bindings: bindings, reminderHotkey: .reminderDefault) == nil)
    #expect(HotkeyValidation.forReminder(optG, bindings: bindings, clipboardHotkey: .clipboardDefault) == nil)
}

@Test func conflictOrderIsModifierThenWindowCycleThenClipboardThenReminderThenBinding() {
    // ⌥⇥ bound as an app shortcut (possible in files written before this check existed)
    // is still reported as window cycling, the more fundamental reason.
    let tabBinding = [Binding(keyCode: 48, modifiers: [.option], bundleID: "x")]
    #expect(HotkeyValidation.forBinding(.windowCycle, bindings: tabBinding, clipboardHotkey: .windowCycle, reminderHotkey: .windowCycle) == .windowCycle)
    // A combination that is both the clipboard and the reminder hotkey names the clipboard first.
    #expect(HotkeyValidation.forBinding(optG, bindings: [], clipboardHotkey: optG, reminderHotkey: optG) == .clipboardHotkey)
}

@Test func reminderDefaultIsOptionR() {
    #expect(Hotkey.reminderDefault == Hotkey(keyCode: 15, modifiers: [.option]))
    #expect(Hotkey.reminderDefault.displayKey == "⌥R")
}

@Test func conflictMessagesAreTheSpecWording() {
    #expect(HotkeyConflict.noModifier.message == "Use at least one modifier, for example ⌥F.")
    #expect(HotkeyConflict.windowCycle.message == "⌥⇥ is window cycling. Pick another combination.")
    #expect(HotkeyConflict.clipboardHotkey.message == "That's the clipboard history shortcut. Change it under Clipboard Settings first.")
    #expect(HotkeyConflict.reminderHotkey.message == "That's the reminder shortcut. Change it under Reminders first.")
    #expect(HotkeyConflict.existingBinding.message == "That combination is already in use.")
}
