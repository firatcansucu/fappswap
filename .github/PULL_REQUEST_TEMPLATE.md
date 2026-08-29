## What does this change?

<!-- One or two sentences. What is different after this PR that wasn't before? -->

## Why?

<!-- Link the issue if there is one: "Fixes #12".
     For anything bigger than a bugfix, there should be an issue — see CONTRIBUTING.md.
     If there isn't one yet, explain here and expect a conversation before review. -->

## How did you test it?

<!-- FappSwapCore changes: say which tests you added or ran.
     FappSwapApp changes: there are no unit tests, so say what you did by hand —
     which apps, and whether you tried a cross-Space or full-screen switch.
     "Tested with Firefox and Terminal, including one full-screen switch" is perfect. -->

## Checklist

- [ ] `swift build` and `swift test` pass locally
- [ ] This PR does one thing (a bugfix *and* a reformat is two PRs)
- [ ] Logic that doesn't need AppKit lives in `FappSwapCore`
- [ ] Any new logging is `.notice` or higher if it's meant to be readable later
- [ ] `CHANGELOG.md` updated under `[Unreleased]`, if this is user-visible
- [ ] Docs updated, if this changes behaviour someone has read about

## Anything else?

<!-- Open questions, things you weren't sure about, or parts you'd like a second
     opinion on. Saying "I wasn't sure about X" is welcome, not a weakness. -->
