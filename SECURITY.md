# Security

## What fappswap can see

fappswap needs Accessibility permission, which on macOS means it installs a
`CGEventTap` and **every keystroke you type passes through it**. That is a serious
permission to hand to any app, and you shouldn't hand it over on trust alone. So here is
exactly what the app does with it.

### What it does

- **Every key-down is inspected once**, to answer two questions: does this match a
  shortcut, and does this complete a snippet trigger? Key-ups pass through the same tap,
  for one reason only: the key-up of a swallowed shortcut is swallowed too, so the
  focused app never sees half a pair.
- **Matched shortcuts are swallowed.** Everything else is passed through untouched.
- **Recent typing is buffered, briefly and boundedly.** `ExpansionEngine` holds a rolling
  buffer that never exceeds `prefix + longest trigger` characters — typically under twenty.
  It is cleared whenever your snippets change, and it is never written to disk.
- **The clipboard is borrowed during an expansion.** Deleting the trigger and pasting the
  replacement is how expansion works. The previous clipboard contents are restored
  immediately afterwards.
- **What you copy is recorded**, if clipboard history is on (it is by default). The app
  polls the general pasteboard's change counter about three times a second and, when it
  moves, stores plain text or an image — never both, never files — together with the
  bundle ID of the frontmost app and a timestamp. Items the copying app marks concealed,
  transient or auto-generated (`org.nspasteboard.*`, the convention password managers
  use) are skipped, unconditionally. The app's own pasteboard writes are skipped. Nothing
  about the contents is logged — kinds and byte counts only. Recording can be paused from
  the menu bar and turned off under Clipboard Settings; **Clear History…** deletes every item and
  image file, including a leftover `history.json.bak` from a past corrupt-file recovery —
  the one file that can hold a full copy of your history and would otherwise survive it.
- **Diagnostics go to the unified log** under subsystem `com.firatcansucu.fappswap`.
  Keystroke content is not logged, and neither are snippet triggers or replacements. What
  *is* logged: which shortcut fired and the bundle ID of the app it activated, with the
  system's timestamp — so the log is a record of which apps you jumped to and when. The
  unified log is readable by any process running as you, and is kept by macOS for as long
  as it keeps everything else in there.
- **Two external programs are executed in normal use**, both Apple's, both with an
  argument list and never through a shell:
  - `/usr/bin/osascript -e 'tell application id "<bundle id>" to activate'`, only when
    activating an app that lives on another Space or in full screen, where the bundle ID
    is one you chose from the menu bar. It is the only method that both switches Spaces and
    takes focus — see [docs/architecture.md](docs/architecture.md).
  - `/bin/launchctl bootout` and `bootstrap`, only when you toggle **Start at login**, to
    register or unregister the login agent.

  Nothing else is spawned in normal use. **Installing an update** spawns three more, all
  Apple's: `/usr/bin/ditto` to unpack the downloaded zip, `/usr/bin/codesign` to verify it
  against the requirement described below, and `/bin/sh` to relaunch the app through
  `/usr/bin/open` a second after this process exits. That last one is the only shell the
  app ever starts, and the path it opens is handed to it as a positional argument rather
  than pasted into the command line.
- **The updater checks GitHub for new releases**, once a day in the background and on
  demand from the menu bar. The only outbound request is an HTTPS call to the public
  `api.github.com` releases endpoint for this repository — no identifying data, no
  telemetry. The download URL in that response is accepted only if its scheme is `https`
  and its host is `github.com` or a subdomain of it, so a spoofed or compromised feed
  can't point the updater at a server of its choosing. Clicking **Install…** downloads
  that release's `.zip`, then before installing anything requires the bundle to satisfy a
  code-signing requirement — its signature must chain to an Apple root **and** carry
  fappswap's Team ID — and separately re-reads the Team ID and bundle identifier with the
  same code-signing APIs macOS itself uses (`SecStaticCode`), requiring both to match the
  running app's exactly. A self-signed bundle asserting the right team, a bundle from any
  other signer, or one that fails any of those checks is discarded and never installed.
  Ad-hoc builds (contributor and CI builds — see
  [CONTRIBUTING.md](CONTRIBUTING.md#the-ad-hoc-signing-gotcha)) have no Team ID to check against, so the
  updater disables itself for them entirely.

### What it does not do

- **No network access beyond the update check described above.** No analytics, no crash
  reporting, no telemetry of any kind. You can confirm the scope with Little Snitch or by
  reading `UpdateController.swift` and `UpdateCheck.swift` — that's the entirety of the
  app's networking code.
- **No transcript of your typing.** The buffer bound above is the reason. It is a design
  constraint, not an optimisation.
- **No third-party dependencies.** `Package.swift` declares none. Nothing is pulled in at
  build time, so when you build from source there is no supply chain beyond Apple's SDK
  and this repository. The released DMG is built by GitHub Actions on a GitHub-hosted
  macOS runner; the one third-party action in that pipeline, `actions/checkout`, is
  pinned to a commit hash rather than a tag.
- **Nothing leaves your Mac.** The only files written are `bindings.json` and
  `snippets.json` in `~/Library/Application Support/fappswap/` — both written readable
  by your user account only (`0600`) — plus a `.bak` copy of either if it ever fails to
  parse, a login agent plist if you enable "Start at login", and, when clipboard history
  is on, a `clipboard/` folder beside them holding `history.json`, an `images/`
  directory, and (only transiently, after an unreadable `history.json` is recovered from)
  `history.json.bak` — the folder `0700`, every file `0600`. That backup is removed as
  soon as new history is written, and by **Clear History…**, so it never outlives its
  usefulness.

### Things you should know

- **Your snippets are stored as plain text**, unencrypted, in
  `~/Library/Application Support/fappswap/snippets.json`. Anything that can read your home
  directory can read them. **Don't put passwords, API keys or recovery codes in snippets.**
- **Your clipboard history is stored as plain text and PNG files**, unencrypted, in
  `~/Library/Application Support/fappswap/clipboard/`, for as long as the retention
  period you chose (30 days by default). Anything that can read your home directory can
  read it. If you copy something sensitive by hand, delete it from the panel (⌫) or clear
  the history.
- **Releases are Developer ID signed and notarized by Apple.** Gatekeeper verifies that
  before you ever see an Open button, so a downloaded DMG or Homebrew install is checked
  by Apple, not just by me. If you'd still rather check the code yourself before handing
  over Accessibility — reasonable, for an app with this permission —
  [build it from source](CONTRIBUTING.md#getting-set-up) instead; those builds are ad-hoc signed.
- macOS's Secure Event Input means fappswap receives nothing at all while you are typing in
  a password field or in Terminal's Secure Keyboard Entry mode. That is enforced by the
  operating system, not by this app.

## Reporting a vulnerability

**Please don't open a public issue for a security problem.**

Email **f@firatcansucu.com** with the details.

If you'd prefer to keep it on GitHub, you can
[open a private security advisory](https://github.com/firatcansucu/fappswap/security/advisories/new)
instead. Either route reaches me directly and stays private until there's a fix.

### What to expect

I'll acknowledge your report and keep you posted as a fix comes together. If something
turns out to need more time, I'd rather tell you that than go quiet on you.

There's no bug bounty. I'll credit you in the advisory and the changelog unless you'd
rather I didn't.

### In scope

- Anything that lets another process read keystrokes or snippet contents through fappswap.
- Anything that escalates the Accessibility permission beyond what's described above.
- Code execution via a crafted `bindings.json` or `snippets.json`.
- Anything the app writes to disk with permissions that are too loose.
- The updater installing a bundle whose Team ID or bundle identifier doesn't match the
  running app's, one whose signature doesn't chain to Apple, or one that fails strict
  codesign verification — a signature mismatch anywhere in that path is a vulnerability.
- The updater downloading from anywhere other than `https` on `github.com` or a subdomain
  of it.
- Anything that lets another process read clipboard history through fappswap.

### Out of scope

- Snippets being stored in plain text. Known, documented above.
- Clipboard history being stored in plain text. Known, documented above.
- Attacks that already require code execution as your user account. At that point the
  attacker can install their own event tap and doesn't need this one.

## Supported versions

The latest release only. This is a single-maintainer project and there are no backports.
