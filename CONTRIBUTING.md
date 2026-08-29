# Contributing to fappswap

Thanks for looking. Issues and pull requests are both welcome.

## How this project is run

fappswap is a personal utility that I use every day and maintain myself. There's one
maintainer, which means every issue and pull request gets read by me personally.

A few things worth saying up front, so nothing comes as a surprise:

- **If your PR fits where the app is heading and the code holds up, I'll be glad to merge
  it**, and you'll be credited in the changelog.
- **Sometimes I'll pass on something even when the code is good.** That's usually not about
  your work at all — more often it's a feature I don't think I could maintain and support
  well over the long run, and it seems fairer to say so than to merge it and let it rot.
- **If I do pass, you can still have it.** The license is MIT: fork it, build it, ship it,
  keep it. That's a genuine option, not a polite brush-off.

Which is really why: **for anything bigger than a bugfix, please open an issue first.** A
two-line conversation up front is much kinder to both of us than a "sorry, not this one"
after you've spent a weekend on it.

## Good contributions

Things I'm reliably happy to receive:

- Bug fixes, especially with a test.
- A reproduction case for something flaky.
- Documentation fixes — including "this paragraph confused me."
- Compatibility fixes for macOS versions or hardware I don't have.

Things to open an issue about first:

- New features of any size.
- New third-party dependencies. The app currently has zero, and I'd like to keep it that
  way unless something is genuinely worth it.
- Refactors that touch `HotkeyTap` or `AppActivator`. Both are load-bearing and full of
  hard-won behaviour that looks removable and isn't — read their doc comments and
  [docs/architecture.md](docs/architecture.md) before you start.

## Getting set up

```bash
git clone https://github.com/firatcansucu/fappswap.git
cd fappswap
swift build
swift test
./scripts/bundle.sh    # produces fappswap.app in the repo root
```

`scripts/bundle.sh` runs `pkill -x fappswap` before building, so it will kill any running
instance — including the one you're using. You can't overwrite a running bundle.

### The ad-hoc signing gotcha

**Read this before your first run.** There's a signing quirk that will otherwise convince
you that you've broken the app when you haven't.

Builds without the project's own Developer ID certificate — CI's, and every contributor's,
including one that holds a Developer ID of its own — are ad-hoc signed, and every ad-hoc
rebuild produces a **new code signature**. macOS ties the Accessibility grant to that
signature, not to the path or the bundle ID. So after every rebuild the existing entry in
System Settings sits there looking correct and enabled while the app receives no keystrokes
at all.

The fix, every time:

1. **System Settings → Privacy & Security → Accessibility**
2. Select the stale fappswap entry, hit **−** to remove it
3. Add the freshly built app with **+**, and make sure the toggle is on

If shortcuts silently stop firing after a rebuild, this is almost always why. Confirm with
the log (see [Reporting bugs](#reporting-bugs)) before going any further.

An ad-hoc build has no Team ID, so the in-app updater disables itself for it — background
checks still run, but **Install** always ends in "Updates unavailable in this build". A
DMG or Homebrew install never hits any of this.

## Code conventions

There's no linter and no style config. Match the surrounding code — it's fairly consistent
and mostly standard Swift.

Two things that aren't obvious:

- **Logic that doesn't need AppKit goes in `FappSwapCore`**, where it can be tested.
- **Anything you might want to read back in the log must be `.notice` or higher.** `.debug`
  messages aren't persisted to the log store and will be gone when you look for them.

## Tests

`swift test` covers `FappSwapCore`. If you're changing matching, storage or validation,
add a test — that's the half of the codebase where tests are cheap and worth it.

`FappSwapApp` isn't unit tested. For changes there, say in the PR what you did to verify it
and in which apps. "Tested with Firefox and Terminal, including a full-screen switch" is a
genuinely useful sentence.

## Pull requests

- Branch off `main`.
- Keep it to one thing. A PR that fixes a bug and reformats a file is two PRs.
- Fill in the template — it's short, and it's what the questions I'd otherwise ask you look
  like written down.
- CI runs `swift build` and `swift test` on macOS. It needs to be green.

## Reporting bugs

Use the bug report template, and attach the log if you can:

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.firatcansucu.fappswap"' --info
```

That output is the single most useful thing in any bug report about shortcuts that stopped
firing.

## Security

Don't open a public issue for a security problem. See [SECURITY.md](SECURITY.md).

## Code of conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Short version:
be decent.
