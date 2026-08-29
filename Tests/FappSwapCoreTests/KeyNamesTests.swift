import Testing
@testable import FappSwapCore

@Test func keyNamesFallsBackToRawCodeForUnmappedKeys() {
    #expect(KeyNames.name(for: 999) == "key 999")
}

@Test func bindingDisplayKeyRendersBareKeyWithNoModifiers() {
    let b = Binding(keyCode: 49, modifiers: [], bundleID: "x")
    #expect(b.displayKey == "Space")
}
