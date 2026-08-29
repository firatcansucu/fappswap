# Changelog

All notable changes to fappswap are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0] — 2026-08-30

First public release.

### Added
- **Shortcuts.** Bind a key combination — `⌥`+key — to any app. Pressing it brings the app
  to the front, launching it if it isn't running. An app living on another desktop is
  followed there, and into full screen.
- **Snippets.** A prefixed trigger like `§sig` expands to stored text as you type. The
  prefix is configurable, and a `snippets.json` whose prefix breaks the rules is repaired
  on load rather than rejected.
- **Clipboard history.** `⌥⌘V` opens a panel of what you've copied — text and images —
  with search focused: type to filter, ↑/↓ to pick, ↩ to paste back into the app you were
  in, ⌘C to copy without pasting, ⌫ to delete. Copying or pasting something already in the
  list moves it to the top instead of adding a second row. Items expire on a schedule you
  set (30 days by default), with caps of 1,000 items and 250 MB of images. Copies that
  password managers mark concealed are never recorded. Everything stays in
  `~/Library/Application Support/fappswap/`, readable by your account only —
  [SECURITY.md](SECURITY.md) describes exactly what is stored.
- **Reminders.** `⌥R` opens a two-step panel — what, then when (`30m`, `1h30m`, `15:30`,
  `3pm`, `tomorrow 9am`, `monday`). At the due time a card appears in the top-right corner
  on every desktop and over full-screen apps, with a ding, and stays until dismissed or
  snoozed. It never takes your keyboard. Reminders that came due while the Mac slept or the
  app wasn't running appear on wake or launch, marked "Was due …".
- **`⌥⇥` window cycling.** Cycles through the frontmost app's windows, including windows on
  other desktops and in full screen. Minimized windows are skipped. It can be turned off
  for apps that need `⌥⇥` themselves.
- **A menu-bar panel** holding everything — Shortcuts, Snippets, Clipboard, Reminders and
  General — each editable in place. It stays open while you work instead of closing on
  every click.
- **Self-updating.** The panel offers an update when a new release is out; one click
  downloads it, verifies that its signature chains to Apple and carries fappswap's own Team
  ID, installs it and relaunches, and the Accessibility permission carries over. Background
  checks run daily.
- **Start at login**, via a user login agent.
- A self-healing event tap: a 5-second watchdog rebuilds it if macOS disables it, and it
  re-arms on wake from sleep.
- Menu-bar only (`LSUIElement`) — no Dock icon and no window to lose behind your work.
- Installable with Homebrew: `brew install firatcansucu/tap/fappswap`.

[1.0]: https://github.com/firatcansucu/fappswap/releases/tag/v1.0
