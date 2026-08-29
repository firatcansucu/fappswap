import Testing
@testable import FappSwapCore

// Windows carry their Space memberships and whether they are on screen right
// now. Cycling walks a stable circular order (ascending window ID) starting
// from the focused window, so every real window gets visited — the "raise the
// bottom-most" policy ping-ponged between Spaces when windows were split
// across them, because off-Space windows always sort behind on-Space ones in
// the app's own ordering.

private func w(_ id: UInt32, spaces: [UInt64], onScreen: Bool) -> WindowCycle.Window {
    WindowCycle.Window(id: id, spaceIDs: spaces, isOnScreen: onScreen)
}

@Test func decideWithNoWindowsDoesNothing() {
    #expect(
        WindowCycle.decide(windows: [], focusedWindowID: nil, currentSpace: 3) == .nothingToCycle)
}

@Test func decideWithOneWindowHereDoesNothing() {
    let windows = [w(1, spaces: [3], onScreen: true)]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 1, currentSpace: 3)
            == .nothingToCycle)
}

@Test func decideJumpsToALoneWindowOnAnotherSpace() {
    // Frontmost app with nothing visible here (e.g. full screen elsewhere):
    // ⌥Tab goes to it, like clicking its Dock icon.
    let windows = [w(5, spaces: [7], onScreen: false)]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: nil, currentSpace: 3)
            == .escalate(windowID: 5))
}

@Test func decideIgnoresPhantomWindows() {
    let windows = [w(1, spaces: [3], onScreen: true), w(2, spaces: [], onScreen: false)]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 1, currentSpace: 3)
            == .nothingToCycle)
}

@Test func decideIgnoresWindowsMinimizedOnTheCurrentSpace() {
    // Minimized windows keep their home Space while leaving the screen;
    // cycling skips them rather than raising something invisible.
    let windows = [w(1, spaces: [3], onScreen: true), w(2, spaces: [3], onScreen: false)]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 1, currentSpace: 3)
            == .nothingToCycle)
}

@Test func decideRaisesTheNextWindowByIDOnTheCurrentSpace() {
    let windows = [w(1, spaces: [3], onScreen: true), w(2, spaces: [3], onScreen: true)]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 1, currentSpace: 3)
            == .raise(windowID: 2))
}

@Test func decideWrapsAroundPastTheHighestID() {
    let windows = [w(1, spaces: [3], onScreen: true), w(2, spaces: [3], onScreen: true)]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 2, currentSpace: 3)
            == .raise(windowID: 1))
}

@Test func decideStepsThroughThreeWindowsInOrder() {
    let windows = [
        w(10, spaces: [3], onScreen: true),
        w(20, spaces: [3], onScreen: true),
        w(30, spaces: [3], onScreen: true),
    ]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 20, currentSpace: 3)
            == .raise(windowID: 30))
}

@Test func decideVisitsEveryWindowWhenSplitAcrossSpaces() {
    // The reported bug: three windows here, one elsewhere — cycling bounced
    // between the remote window and a single local one. The circular order
    // must visit all four.
    let here: [UInt64] = [3]
    let there: [UInt64] = [7]
    let windows = [
        w(10, spaces: here, onScreen: true),
        w(20, spaces: here, onScreen: true),
        w(30, spaces: here, onScreen: true),
        w(40, spaces: there, onScreen: false),
    ]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 10, currentSpace: 3)
            == .raise(windowID: 20))
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 20, currentSpace: 3)
            == .raise(windowID: 30))
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 30, currentSpace: 3)
            == .escalate(windowID: 40))

    // Now standing on the other Space: the three original windows are the
    // off-screen ones, and the wrap comes back to the lowest ID.
    let flipped = [
        w(10, spaces: here, onScreen: false),
        w(20, spaces: here, onScreen: false),
        w(30, spaces: here, onScreen: false),
        w(40, spaces: there, onScreen: true),
    ]
    #expect(
        WindowCycle.decide(windows: flipped, focusedWindowID: 40, currentSpace: 7)
            == .escalate(windowID: 10))
}

@Test func decideFallsBackToTheFirstEligibleWindowWhenFocusIsUnknown() {
    let windows = [w(4, spaces: [7], onScreen: false), w(9, spaces: [8], onScreen: false)]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: nil, currentSpace: 3)
            == .escalate(windowID: 4))
}

@Test func decideTreatsAFocusIDOutsideTheEligibleSetAsUnknown() {
    // The focused window can be something the filters rejected (a companion
    // overlay, a sheet); cycling starts from the top rather than crashing or
    // doing nothing.
    let windows = [w(4, spaces: [3], onScreen: true), w(9, spaces: [3], onScreen: true)]
    #expect(
        WindowCycle.decide(windows: windows, focusedWindowID: 77, currentSpace: 3)
            == .raise(windowID: 4))
}

@Test func scriptTargetsTheWindowByIDAndReordersBeforeActivating() {
    let script = WindowCycle.script(bundleID: "org.mozilla.firefox", windowID: 50138)
    #expect(script.contains("tell application id \"org.mozilla.firefox\""))
    // The reorder must come before the activate, or the Apple Event raises
    // whatever was already frontmost.
    let reorder = script.range(of: "set index of window id 50138 to 1")
    let activate = script.range(of: "activate")
    #expect(reorder != nil && activate != nil)
    if let reorder, let activate {
        #expect(reorder.lowerBound < activate.lowerBound)
    }
}

@Test func scriptQuotesHostileBundleIDs() {
    let script = WindowCycle.script(bundleID: "x\" to activate", windowID: 1)
    #expect(script.contains(#"tell application id "x\" to activate""#))
}
