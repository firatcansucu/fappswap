# fappswap manual

Everything the app does, and every way it can surprise you. If you just want to get
started, the [README](../README.md) is enough.

- [The panel](#the-panel)
- [Shortcuts](#shortcuts)
- [Snippets](#snippets)
- [Window cycling](#window-cycling)
- [Clipboard history](#clipboard-history)
- [Reminders](#reminders)
- [Start at login](#start-at-login)
- [Updating](#updating)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Where your data lives](#where-your-data-lives)
- [Uninstall](#uninstall)

## The panel

Click the menu bar icon and a panel opens under it. Everything fappswap can be told is in
there, and **it stays open while you work** — add three shortcuts, fix a snippet and flip
two toggles in one visit. It closes when you click the icon again, click anywhere outside
it, or press **esc**.

Five tabs down the left side:

| Tab | What's in it |
| --- | --- |
| **Shortcuts** | Every binding, adding and re-recording them, and the `⌥⇥` toggle |
| **Snippets** | The prefix, every snippet, and the editor |
| **Clipboard** | The history toggles, its shortcut, retention, and the history actions |
| **Reminders** | Adding one, the pending list and the log, sound and shortcut |
| **General** | Start at Login, updates, the Accessibility pane, and About |

Along the bottom is a status line — "Shortcuts, snippets and clipboard active", or a red
"Not active — open Accessibility settings…" that takes you straight to the right pane —
and **Quit**. When an update is waiting, a banner appears across the top.

Everything that needs typing happens **inside the tab**: recording a shortcut, writing a
snippet, changing the prefix. One editor is open at a time, **esc** closes the editor
before it closes the panel, and a rejected value keeps what you typed and tells you what's
wrong rather than throwing it away.

## Shortcuts

**Shortcuts** tab → **Add Shortcut…** → press a key combination → pick an app from the
picker.

Nothing is bound out of the box, and `⌥` specifically isn't required — the recorder takes
any combination of `⌘`, `⌃`, `⌥` and `⇧` together with a key. `⌥` is simply the one with a
whole layer going spare, which is why the app is built around it.

Three things the recorder does that aren't obvious:

- **At least one modifier is required.** A bare key is refused with "Use at least one
  modifier, for example ⌥F." Binding `K` on its own would make `K` untypeable everywhere.
- **Esc cancels** rather than being recorded, so Esc can't be bound.
- **Caps Lock, `fn` and the numeric-pad bit are ignored.** A binding fires regardless of
  them, and `fn` can't be part of a combination.

**What happens when a binding fires:**

- If the app isn't running, it launches.
- If it's running on your current desktop, it comes to the front immediately.
- If it's on another Space, or in full screen, macOS switches you there and puts you in it.

**Bound combinations are swallowed system-wide.** While fappswap is running, `⌥F` will
never type `ƒ` in any app, anywhere. Quitting fappswap gives the key back. This is
deliberate — a shortcut that only worked in some apps would be worse than no shortcut.

**Shortcuts stay live while the panel is open**, so you can add one and try it straight
away. The one exception is the moment the key recorder is waiting for a combination: the
panel's status line then reads "Paused while recording a shortcut", because the tap has to
stop swallowing keys or an already-bound combination could never be re-recorded.

**A binding's combination is editable in place; its app isn't.** Hover a row and click the
pencil to re-record the keys for the same app. To point a shortcut at a different app,
remove it and add it again.

### The Shortcuts tab

Every binding is a row — `⌥F  🦊 Firefox`: the combination in monospace, the app's icon,
then its name. It reads "No shortcuts yet" until you've added one. **Click a row to switch
to that app**, exactly as pressing the shortcut would. Hover it and two buttons appear: a
pencil to re-record the combination, and ✕ to remove the binding. A shortcut whose app is
no longer installed shows its bundle identifier in red — it can't be clicked, but it can
still be removed.

At the foot of the tab is the **Cycle Windows with ⌥⇥** toggle.

## Snippets

**Snippets** tab → **Add Snippet…**. Give it a trigger like `sig` and the text it should
expand to, then **Save**. The editor opens inside the tab; **Cancel** or **esc** closes it.

Type `§sig` anywhere afterwards and it's replaced by that text.

### The prefix

The `§` at the front is the **prefix**, and it's a setting — change it with **Change…**
next to **Prefix** at the top of the tab, to any character you like. `§` is the default because it sits left of
`1` on ISO keyboards and almost nobody types it on purpose; if your keyboard is ANSI it
doesn't exist at all, so you'll want to change it.

Triggers are stored without the prefix, so changing it rebinds every snippet at once.

### How expansion behaves

- **It fires the instant you finish typing the trigger** — no space or tab needed. That's
  only safe because the prefix is a character you never otherwise type, which is the whole
  reason there is a prefix.
- **Two triggers can't overlap.** With `§sig` defined you can't also define `§sign`,
  because the shorter one would always fire first. The editor refuses it and says so.
- **Triggers are case-sensitive.** `§Sig` won't fire `§sig`.
- **Triggers can't contain spaces.**
- **One backspace is recoverable.** `§six` → backspace → `g` expands correctly. A longer
  slip isn't: the app keeps only as many recent characters as the longest trigger needs, so
  by then the `§` has already been discarded. Just type the trigger again.
- **Expansion uses the clipboard for a moment.** It works by deleting the trigger and
  pasting, then putting back what was there. Plain text is restored exactly. Large file
  promises from other apps — a file dragged from another app, say — can't be captured and
  would be lost.

### The Snippets tab

Everything you've defined is a row — `§sig  Kind regards…`: the full trigger in
monospace, then a one-line preview. Hover it for three buttons: **copy** puts the
replacement on the clipboard (which is how you get at your snippets in places expansion
can't reach — see below), **pencil** opens the editor in place, and ✕ removes it.

## Window cycling

Press `⌥⇥` (Option-Tab) and the app in front brings its next window forward. Press again for the one
after that; the loop wraps around and visits every window once per lap.

The point over `⌘\``, macOS's own cycle-windows shortcut: **`⌥⇥` follows windows onto
other Spaces and into full screen.** `⌘\`` only reaches windows on the desktop you're
currently looking at; `⌥⇥` treats all of an app's windows as one loop, wherever they
live, and switches Spaces when the next window is elsewhere.

Details worth knowing:

- **The loop's order is fixed** (by window age), not most-recently-used. With two windows
  it's a plain toggle either way.
- **Minimized windows are skipped.** Un-minimize from the Dock.
- **Same-desktop steps are instant; steps to another Space sit through macOS's own
  Space-switch animation**, exactly like a cross-Space shortcut.
- **It's on by default.** Turn it off with **Cycle Windows with ⌥⇥** at the foot of the
  **Shortcuts** tab if some app needs `⌥⇥` for itself — Safari, for example, uses it to move between
  items on a page — or if you run another switcher (AltTab's default hotkey is also `⌥⇥`).

## Clipboard history

Press **⌥⌘V** anywhere, or click **Open Clipboard History** in the **Clipboard** tab. A panel lists
what you've copied, newest first, with the search field already focused. Copying
something already in the list, or pasting an item from the panel, moves that row to the
top rather than adding a duplicate — the list always reflects what you've used most
recently, not just the order you first copied it in.

- **Type to filter.** Matching is case-insensitive. Images are listed only while the
  search field is empty — they have no text to match.
- **↑ / ↓** move the selection; hovering with the mouse selects too. The search field
  keeps focus throughout.
- **↩** closes the panel and pastes the selected item into the app you were in.
- **⌘C**, or the **Copy** button on the row, closes the panel and puts the item on the
  clipboard without pasting.
- **⌫** deletes the selected item — while the search field is empty. With text in the
  field, ⌫ edits the text; **⌘⌫** deletes the item either way. There is no undo.
- **⎋**, clicking outside the panel, or pressing ⌥⌘V again closes it.

Each row shows the app it was copied from and when.

### What gets recorded

Every copy of text or an image, from any app, unless:

- the copying app marked it **concealed, transient or auto-generated** — password
  managers do this, so a password copied from 1Password, Bitwarden or Apple Passwords is
  never recorded;
- the text is blank or **over 1 MB**, or a single image is **over 100 MB**;
- **recording is paused** (**Clipboard** tab → **Pause Clipboard History**; per session —
  relaunching resumes), or the feature is off (**Clipboard** → **Keep a History of What You
  Copy**).

Pausing or turning the feature off only stops new items from being recorded — history
already saved stays exactly as it is, until its retention period elapses or you clear it
yourself.

fappswap's own clipboard use — a snippet expansion borrowing the clipboard, the panel
itself pasting — is never recorded.

A copy that carries both text and an image (a spreadsheet cell, say) is recorded as text.

### Retention

**Clipboard Settings** → **Keep History For**: 1 day, 7 days, 30 days (the default), 90 days or
1 year. Choosing a shorter period than the one in force asks before deleting what would
fall outside it. On top of the period, the history keeps at most 1,000 items and 250 MB of
images in total — a single image over 100 MB isn't recorded in the first place; the
oldest go first.

### Where it lives

`~/Library/Application Support/fappswap/clipboard/` — `history.json` plus an `images/`
folder, readable by your account only. **Clipboard Settings** → **Show History in Finder**
opens it. **Clipboard Settings** → **Clear History…** deletes all of it.

### Changing the shortcut

⌥⌘V is Finder's **Move Items Here** (⌘C a file, ⌥⌘V to move it). If you use that from the
keyboard, change fappswap's shortcut with **Clipboard Settings** → **Shortcut: … — Change…**,
then press the combination. It can't be one of your app shortcuts, and while clipboard
history is on, an app shortcut can't be it either. If you don't want clipboard history at
all, turning it off in the **Clipboard** tab frees ⌥⌘V the same way — recording stops and
the shortcut goes back to Finder, but anything already in your history stays put.

## Reminders

Press **⌥R** anywhere and a panel opens with one question at a time. (The **Reminders**
tab asks both at once instead — a *what* field, a *when* field and **Add** — over the same
grammar and the same live preview.)

1. **What should I remind you about?** Type it — whatever you type is the reminder, word
   for word — and press **↩**. An empty field shakes and stays.
2. **When?** Type one of:
   - a duration — `30m`, `1h`, `1h30m`, `2d`, `in 45 min`;
   - a clock time — `15:30`, `3pm`, `3:30 pm`, or just `5`, which means the next five
     o'clock that hasn't happened yet (5 PM if it's the morning, 5 AM tomorrow if it's the
     evening);
   - `today`, `tonight`, `tomorrow` or a weekday name, on its own (9:00 that day; `tonight`
     is 20:00) or followed by a time — `tomorrow 9am`, `monday 17:00`. A time that has
     already passed today rolls to tomorrow; a weekday that is today means next week.

   The line under the field shows when it will fire — `Fires at 3:42 PM (in 25 minutes)` —
   or tells you it didn't understand. Press **↩**. The four chips (15 min · 30 min · 1 hour ·
   Tomorrow 9:00) are one-click alternatives. **⌫** on an empty time field goes back to the
   text. Under a minute and over a year are refused.

**⎋**, or clicking anywhere outside the panel, closes it without saving. Pressing ⌥R while
it's open just brings it back to front — unless a reminder card is up, in which case ⌥R goes
to the card instead and the panel closes, dropping whatever you had typed.

### When it fires

A card appears in the top-right corner of the screen your mouse is on, with the fappswap
icon, the reminder's text, and a ding (**Play a Sound** in the **Reminders** tab turns the
ding off). It
sits above everything, follows you to every desktop and over full-screen apps, and stays
until you dismiss or snooze it. Several reminders due at once, or one firing while another
is still up, share a single card.

**The card never takes your keyboard.** If you're mid-sentence somewhere, your typing keeps
going there. To handle the card from the keyboard, press **⌥R** while it's showing — the
card takes focus instead of a new reminder panel opening — then:

- **↩** dismisses everything on the card;
- **1** snoozes everything 5 minutes, **2** snoozes 15 minutes;
- **⎋** leaves the card where it is and gives the keyboard back.

Or click **Dismiss**, **Snooze 5 min**, **Snooze 15 min**. To add a new reminder while a
card is up, use the **Reminders** tab, or deal with the card first.

If the Mac was asleep, or fappswap wasn't running, when a reminder came due, it appears the
moment the Mac wakes or the app launches, with `Was due 2 hours ago` under the text. Nothing
is ever dropped, however late.

### The Reminders tab

Below the add fields, everything pending — `tea time   3:42 PM (in 25 minutes)`, each with
a ✕ on hover to cancel it — and below a divider everything that already fired or was
cancelled, as `Dismissed 2:10 PM` or `Cancelled Yesterday 4:00 PM`. A reminder currently on
screen reads `On screen` and has no ✕: handle it on the card. Past reminders are kept for
30 days; **Clear Log…** removes them now. There's no editing: cancel it and type it again.

### Changing the shortcut

**Reminders** tab → **Change…** next to the shortcut, then press the combination. It can't
be one of your app shortcuts, the clipboard history shortcut, or ⌥⇥, and none of those can
be set to it either. The shortcut is always set; the tab's add fields work regardless.

## Start at login

Toggle **Start at Login** in the **General** tab. This installs a login agent at
`~/Library/LaunchAgents/com.firatcansucu.fappswap.plist`.

> **Warning:** the login agent hardcodes the app's path at the moment you enable it. If you
> move or rename `fappswap.app` afterwards, it will silently fail to find it. Fix this by
> unticking **Start at Login** and re-ticking it after the move.

## Updating

fappswap checks GitHub for a new release once a day in the background — starting about 15
seconds after launch, so it never competes with the tap and the panel for setup time — and
you can trigger a check any time with **Check for Updates…** in the **General** tab.

A banner across the top of the panel tracks the whole thing, and appears only when there is
something to say:

- **nothing** — idle. **General → Check for Updates…** starts a check.
- **"Checking for updates…"** — a check is in flight.
- **"Update to X available"** with an **Install** button — a newer release exists.
- A short phase while installing — **"Downloading X…"**, **"Verifying X…"**, or
  **"Installing X…"** — nothing is clickable until it lands.
- The failure's reason with a **Retry** button — a network error, a verification failure,
  or the app needing to be moved out of the mounted DMG first.

**Installing.** One click downloads the release's `.zip` — only ever from GitHub over
HTTPS — verifies that the bundle carries a real Apple-issued signature from fappswap's own
team, and that its Team ID and bundle identifier match the running app's exactly, then
swaps it into place and relaunches fappswap automatically. If verification fails, nothing is
installed and the banner says so.

**The Accessibility grant survives.** Releases share fappswap's Developer ID signature, and
that signature — not the path, not the bundle version — is what the grant is tied to, so it
carries over from one update to the next automatically.

**A build without a Developer ID signature can't update itself.** There's no stable
identity to verify a downloaded bundle against, so the updater disables itself rather than
install something it can't check. This only affects builds from source; every DMG and
Homebrew release is signed.

## Known limitations

### Both features

They share one event tap, so they share these:

- **Nothing fires while Secure Event Input is active** — while you're typing into a password
  field, or in Terminal's Secure Keyboard Entry mode. macOS deliberately starves event taps
  of keystrokes there, and there's no way around it. For snippets, hover the row in the
  **Snippets** tab and use its copy button instead.
- **Function-row and media keys never reach the event tap**, so they can't be bound at all.

### Shortcuts

- **Switching to an app on a different Space or in full screen isn't instant.**
  Same-desktop switches are. The wait is macOS's own Space-switch animation — the same one
  you sit through swiping between desktops by hand — so it's the standard speed of moving
  between Spaces on a Mac, and not something fappswap can hurry along.
- **For a few seconds after a cross-Space switch, fappswap defends the focus it just
  took.** macOS tends to hand focus back to Finder as the Space-switch animation lands, so
  fappswap keeps re-asserting the target app until it has held focus for half a second, for
  up to five seconds. If you click into some *other* app during that window, fappswap may
  pull focus back to the one you asked for, once. Pressing any other shortcut cancels it
  immediately. Same-desktop switches don't do this at all.
- **No in-place editing** — delete the binding and add it again.
- **Bound combinations are dead system-wide** while fappswap runs.

### Window cycling

- **Windows of apps without AppleScript window support can only be cycled on the current
  desktop.** Reaching a window on another Space works by asking the app itself to raise
  it, which needs the app to answer basic window scripting. The big browsers, Finder and
  most Mac-assed Mac apps do; if one doesn't, `⌥⇥` still cycles its windows on the
  current desktop.
- **A window minimized on another Space counts as being there**, so `⌥⇥` may switch you
  to that Space without anything visibly raising.

### Snippets

- **Expansion pastes rather than types**, so it borrows the clipboard briefly. Previous
  contents are restored, except for promised data such as file drags from other apps.
- **Triggers can't overlap and can't contain spaces.**
- **Expansion is suppressed while the panel is open**, so a trigger typed into a snippet's
  own replacement box stays as typed instead of expanding there. It resumes the moment the
  panel closes.

### Clipboard history

- **⌥⌘V is Finder's Move Items Here** while fappswap runs with the default shortcut.
  Change the shortcut, or turn clipboard history off, if you need that — either frees the
  key.
- **Plain text only.** Formatting isn't kept; what pastes back is plain text.
- **A password copied by hand** from an ordinary text field is recorded like any other
  text — only password managers mark their copies as concealed. Delete it from the panel
  with ⌫.
- **The source app is whichever app was frontmost when the copy was noticed**, about a
  third of a second later. Copy and switch apps faster than that and it's misattributed.
- **File copies aren't recorded.** Copying files in Finder leaves no history entry.

### Reminders

- **Focus and Do Not Disturb are not honoured.** macOS gives apps no reliable way to ask
  whether a Focus is on, so a card appears regardless.
- **A reminder can't wake the Mac.** One due during sleep appears on wake, marked late.
- **Repeating reminders aren't a thing.** Set it again.

## Troubleshooting

### Shortcuts silently stopped working

Nine times out of ten this is the Accessibility grant. Check
**System Settings → Privacy & Security → Accessibility** — if fappswap is listed but the
toggle is off, or if it's listed twice, this is almost always a build-from-source issue: see
[CONTRIBUTING.md](../CONTRIBUTING.md#the-ad-hoc-signing-gotcha), every ad-hoc rebuild produces a
new code signature and macOS ties the grant to the signature. A DMG or Homebrew install
doesn't hit this — its signature doesn't change between updates.

### Read the log

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.firatcansucu.fappswap"' --info
```

The event tap self-heals: a 5-second watchdog checks whether the tap is alive and rebuilds
it if not, and it re-arms on wake from sleep. The log will show whether the watchdog
rebuilt the tap, or found it dead and couldn't — the latter is almost always a permission
problem.

If you're filing a bug, this output is the single most useful thing you can attach.

### A specific app won't come to the front

Check the log for `No installed application found for bundle ID`. Apps are stored by bundle
ID, so if you've deleted or replaced the app since binding it, rebind it.

## Where your data lives

```
~/Library/Application Support/fappswap/bindings.json
~/Library/Application Support/fappswap/snippets.json
~/Library/Application Support/fappswap/clipboard/         (history.json plus images/, if clipboard history is on)
~/Library/Application Support/fappswap/reminders.json     (every reminder, pending and past; pruned after 30 days)
~/Library/Preferences/com.firatcansucu.fappswap.plist    (the window-cycling toggle)
~/Library/LaunchAgents/com.firatcansucu.fappswap.plist   (only if "Start at Login" is on)
```

The JSON files are all plain, readable and safe to back up or hand-edit while the app is
closed. If one of them is ever corrupted, the app moves it aside to `.bak` and starts fresh
rather than refusing to launch. If `snippets.json` parses but its prefix breaks the rules
the prefix editor enforces — empty, more than one character, a letter — the prefix is reset
to `§`, the snippets are kept, and the **Snippets** tab says so at the top until the
next launch.

**Your snippets are stored as plain text.** Don't put passwords or secrets in them.

## Uninstall

1. Quit fappswap with **Quit** at the bottom of the panel.
2. Remove the login agent, if you enabled it:
   ```bash
   launchctl bootout "gui/$(id -u)/com.firatcansucu.fappswap"
   rm ~/Library/LaunchAgents/com.firatcansucu.fappswap.plist
   ```
3. Delete application data:
   ```bash
   rm -rf ~/Library/Application\ Support/fappswap/
   ```
4. Delete `fappswap.app`.
5. Remove fappswap from **System Settings → Privacy & Security → Accessibility**.
