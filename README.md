<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/wordmark-lockup-white@2x.png">
    <img src="assets/brand/wordmark-lockup-ink@2x.png" alt="fappswap" width="366">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/firatcansucu/fappswap/actions/workflows/ci.yml"><img src="https://github.com/firatcansucu/fappswap/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <a href="https://github.com/firatcansucu/fappswap/releases/latest"><img src="https://img.shields.io/github/v/release/firatcansucu/fappswap" alt="Latest release"></a>
</p>

# ⌥ is the most underused key on your Mac.

I'd rather get to my apps from the keyboard than from the Dock. `⌘Tab` handles two apps
well, but once I'm moving between four I have to hold their order in my head and read the
switcher to count the presses. A key that never moves becomes muscle memory.

fappswap gives you the option to bind each app to a key on the Option layer: press `⌥F` and
Firefox is in front of you, launched if it wasn't running, followed across desktops and
into full screen if it was. Four examples I use on my machine are `⌥F` Firefox, `⌥S`
Obsidian, `⌥A` Terminal, `⌥C` Claude.

On top of the app swapping there are a few more things I wanted from my mac, and I
didn't want to install yet another app for each. `⌥⇥` cycles the front app's windows
wherever they are, full screen included. Typing `§sig` expands to stored text in any app.

`⌥⌘V` opens a history of what you've copied — text and images — with search focused: type
to filter, arrow to pick, Enter to paste it into the app you were in. It expires after a
period you choose (30 days by default) and never leaves your Mac. It keeps up to 1,000
items and 250 MB of images; a single copy over 1 MB of text, or an image over 100 MB,
isn't recorded.

`⌥R` sets a reminder: type what, press Enter, type when — `30m`, `1h30m`, `15:30`, `3pm`,
`tomorrow 9am`, `monday` — press Enter. When it's time, a small card appears in the corner
of your screen, on whatever desktop you're on, with a ding, and stays until you deal with
it. It never grabs your keyboard: press `⌥R` when a card is showing to dismiss (Enter) or
snooze (1 or 2) it without touching the mouse.

All of it is set up from one place: clicking the menu bar icon opens a panel with a tab
each for shortcuts, snippets, clipboard and reminders, and it stays open while you work
rather than closing the moment you click something.

Everything stays on your Mac — no account, no telemetry, nothing on the network but the
daily update check ([SECURITY.md](SECURITY.md)).

## Install

```bash
brew install firatcansucu/tap/fappswap
```

Or grab the signed, notarized DMG from
[Releases](https://github.com/firatcansucu/fappswap/releases/latest). Needs macOS 14+ on
Apple Silicon. Launch it, grant Accessibility when macOS asks — nothing works without it —
then click the menu bar icon → **Shortcuts** → **Add Shortcut…**.

## Docs

[Manual](docs/manual.md) · [Architecture](docs/architecture.md) · [Contributing](CONTRIBUTING.md)

[MIT](LICENSE).
