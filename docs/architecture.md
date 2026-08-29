# Architecture

A tour of how fappswap fits together, for anyone reading the code for the first time.
It's a small app — around 3,000 lines — and the shape is simple: one event tap feeds
every feature that reacts to a key.

## The two targets

**`FappSwapCore`** is pure logic with no AppKit and no CoreGraphics. Models
(`Binding`, `Snippet`, `Modifier`, `TypedKey`), the four JSON-backed stores
(`BindingStore`, `SnippetStore`, `ClipboardHistoryStore`, `ReminderStore`), and
`ExpansionEngine`. All of it is unit-testable without a running app or an event tap, and
that's the reason the split exists — the interesting matching logic can be tested at a
desk instead of by typing into TextEdit and squinting.

**`FappSwapApp`** is everything that touches the system: the event tap, app activation,
text injection, the menu bar and the status panel. Not unit tested; verified by
running it.

If you're adding logic that could live in `Core`, put it in `Core`.

## The one event tap

`HotkeyTap` owns a single `CGEventTap` and is the reason every keyboard feature shares one
Accessibility permission — and shares its limitations.

Every key-down goes through it exactly once, and gets sorted into one of three paths:

```
key-down ─→ HotkeyTap
              ├─ ⌥⇥, the clipboard hotkey or the reminder hotkey? ─→ swallow it
              │      ─→ WindowCycler / ClipboardPanelController / ReminderInputController
              ├─ matches a binding? ─→ swallow it ─→ onMatch ─→ AppActivator
              └─ anything else? ─────→ pass through ─→ onUnmatchedKeyDown ─→ ExpansionEngine
```

Three constraints on this file that are easy to violate by accident, all documented at
greater length in the source:

- **The callback runs on the main run loop.** That's what makes the lookup table and the
  suspend flag safe to touch without locking — and it's also why *nothing on this path may
  block*. A synchronous wait on the main thread produces `.tapDisabledByTimeout`, which
  silently kills every shortcut in the app. Every delay in the codebase is an `asyncAfter`
  hop, never a sleep.
- **The instance must outlive its tap.** The C callback holds an unretained pointer back to
  `self` with nothing enforcing that lifetime.
- **`onHealthChange` is single-subscriber.** It's one closure property, not a multicast, and
  `AppDelegate` already claims it. Reassigning it from anywhere else silently breaks the
  panel's status line and the first-run panel pop at once. Chain through `AppDelegate`
  instead.

A 5-second watchdog rebuilds the tap if it dies, and it re-arms on wake from sleep. macOS
disables event taps for reasons outside the app's control, so self-healing isn't optional.

## Switching apps

`AppActivator` is by far the most fought-over file in the repo, and the commit log shows
it — a dozen commits converging on one working path. The short version:

- Already running and on this desktop: `NSRunningApplication.activate` and you're done.
- Not running: launch it — but **wait for the user to release the modifier keys first**.
  Apps read live hardware modifier state at startup; Firefox opens in troubleshoot mode if
  Option is down. Swallowing the keystroke doesn't change what the launching app sees.
  Capped at ~1 second so a stuck key can't block the launch forever.
- On another Space, or full screen: escalate to an Apple Event via `osascript`, off the
  main thread. This is the only method that both switches Spaces and takes focus. Several
  more obvious approaches were tried and don't work; the commit history is the record.

A `generation` counter guards the async paths: if you press a different binding while a
slow activation is still waiting, the stale request must not steal focus back from
whatever you asked for instead.

## Expanding snippets

`ExpansionEngine` (in `Core`) holds a short rolling buffer of recent typing and decides
when a trigger has been completed. Candidates are sorted longest-first, so the first suffix
hit is also the longest — that's what makes overlapping triggers decidable, and why the
editor rejects a trigger that would be shadowed by a shorter one.

**The buffer never holds more than `prefix + longest trigger` characters.** The app does
not accumulate a transcript of what you type, and that bound is load-bearing rather than an
optimisation — see [SECURITY.md](../SECURITY.md).

`TextInjector` performs the edit: backspace over the trigger, then paste. It pastes rather
than synthesising characters because snippets can be multi-line and hundreds of characters
long, where synthetic typing is slow and drops keys in some apps. The cost is that it has
to borrow the clipboard for a moment and put it back.

Injected events are stamped with a marker (`0x6661_7070`, `"fapp"`) so `HotkeyTap`
recognises the app's own synthetic keystrokes and never feeds them back into the buffer.
Without it, a snippet whose replacement contains a trigger would expand forever.

## Clipboard history

macOS has no clipboard-change notification, so `ClipboardRecorder` polls
`NSPasteboard.general.changeCount` — an integer — every 0.35 s on the main run loop and
reads contents only when it moves. Text goes straight to `ClipboardHistoryStore` (in
`Core`, tested); an image is read on the main thread and decoded, thumbnailed and
PNG-encoded on a background queue, then handed to the store as bytes. The store owns
`history.json` and the `images/` directory and reconciles the two on every load.

Pasteboard writes that must not be recorded as a user copy — the expander's
borrow-and-restore, the panel's own writes — go through `PasteboardWriter`, which
remembers the resulting `changeCount`s so the recorder can skip them. Without that, each
snippet expansion would record two items. A deliberate user-facing copy, like the
Snippets tab's "copy snippet", writes to `NSPasteboard.general` directly and is
recorded on purpose — it's a real copy.

`ClipboardPanelController` is an `NSPanel` with `.nonactivatingPanel`: it becomes key
without activating fappswap, so the app the user was in stays active and a synthetic `⌘V`
after the panel closes lands there. While the panel is open, keystrokes still flow through
the tap; `AppDelegate.handleTyped` drops them so the expander can't fire into the search
field.

## Reminders

`ReminderModel` owns `ReminderStore` and one non-repeating `Timer`, armed for the earliest
pending reminder and re-armed after every change. A `Timer` doesn't fire while the Mac
sleeps, so the model also listens for `NSWorkspace.didWakeNotification` and
`NSSystemClockDidChange` and re-checks on both; `start()` at launch does the same check, so
a reminder that came due while the app wasn't running fires immediately. Due dates are
absolute instants, so a timezone change moves nothing.

`ReminderTimeParser` (in `Core`, tested) is the whole "when" grammar; `ReminderFormatting`
(also `Core`) produces every string the rows, the preview and the card show, with calendar
and locale injectable so the tests are deterministic.

Two panels, both the `ClipboardPanel` recipe. `ReminderInputController` is the `⌥R`
two-step panel: key without activating the app, closes on losing key, drives `↩` / `⎋` /
`⌫` from a local key monitor with the same swallowed-key-up discipline as the clipboard
panel. `ReminderAlertController` is the card: shown with `orderFrontRegardless()` so it
*doesn't* become key — a reminder must never eat the keystroke you were typing — and made
key only when the reminder hotkey is pressed while it's visible. `⎋` hands the keyboard
back by ordering the panel out and back in without key, which is the only reliable way to
resign key status while staying on screen.

`HotkeyTap` has a third reserved slot for the reminder hotkey, checked after the clipboard
one and before the user's table; `AppDelegate.onReminder` decides between opening the
input and focusing the card.

## Storage

`BindingStore`, `SnippetStore` and `ReminderStore` are the same shape: a JSON file under
`~/Library/Application Support/fappswap/`, written atomically. A file that fails to decode
is moved aside to `.bak` and the store starts empty, so a corrupted file degrades into lost
settings rather than an app that won't launch.

`ClipboardHistoryStore` follows the same atomic-write discipline for
`clipboard/history.json`, but isn't self-contained the same way: each history entry for an
image points at a PNG file in `clipboard/images/` rather than embedding its bytes, so the
store also has to reconcile the two on load — deleting orphaned image files and dropping
entries whose file is missing.

## The UI

`StatusPanelController` owns the status item and the panel that hangs under it. The icon
reflects two states — healthy and missing permission — and `MenuBarIcon` draws the `⌥`
glyph at runtime as a template image, so macOS handles light bars, dark bars and the
inverted pressed state. The third state, paused while recording a shortcut, is a healthy
tap and says so in the panel's footer rather than on the icon.

There is no settings window and no menu. `LSUIElement` is true — no Dock icon, and an
accessory app's windows are invisible to `⌘Tab`, which is why the window that used to
exist was removed; the menu that replaced it closed on every click, which is why the panel
replaced *it*. Clicking the status item toggles a fixed-size `NSPanel`: a sidebar of five
tabs (Shortcuts, Snippets, Clipboard, Reminders, General) on the left, the tab's content on
the right, a status line and **Quit** along the bottom, and an update banner across the top
whenever `UpdateController` has something to say. It is the `ClipboardPanel` recipe —
`.nonactivatingPanel`, key without activating fappswap — so its fields take typing while
the app you were in stays frontmost. Clicking outside resigns key, and resigning key closes
it; `⎋` closes it too, unless an editor is open, in which case `⎋` cancels the editor first.

The content is SwiftUI in an `NSHostingView` over `StatusPanelModel`, an `ObservableObject`
that *snapshots* rather than observes: `reload()` reads every value the tabs display, and
runs on open and after every action. Rebuild-on-open was what kept the menu current with no
observation wiring; reload-on-action is the same trick one level up. The panel is a fixed
420-by-460 — sizing an `NSPanel` around an `NSHostingView` dynamically is the trap class
that cost the reminders release three separate fixes — so tab content scrolls inside it.

`StatusPanelController` builds no UI itself and never touches a store: the tabs call
closures in `SettingsActions`, `ClipboardActions` and `ReminderActions`, exactly the seam
the menu used. The four model classes (`BindingsModel`, `SnippetsModel`, `WindowCycleModel`,
`ClipboardModel`) behind those closures hold the logic and report errors as return values,
which `AppDelegate` shows in an `NSAlert`.

Everything that needs typing is edited in place, inside the tab: recording a shortcut,
adding or editing a snippet, changing the prefix, and recording the clipboard and reminder
shortcuts. `StatusPanelModel.ActiveEditor` names whichever one is open — one at a time —
and opening another, switching tabs or closing the panel clears it. Two consequences hang
off that single property:

- **Tap suspension.** `ActiveEditor.suspendsTap` is true for the three key recorders, and
  `didChangeEditor` is the only place `tap.isSuspended` is written. A recorder must suspend
  the tap or an already-bound combination could never be re-recorded — and a tap left
  suspended is an app where nothing works, which is why every path out of an editor lands
  on `activeEditor = nil`.
- **Modals.** A non-activating panel resigns key to any `NSAlert` or `NSOpenPanel`, and
  resigning key closes it. Every action that can raise one goes through
  `StatusPanelModel.perform`, which wraps it in `runPreservingPanel` — the panel ignores
  that one resignation and takes key back afterwards.

The `⌥⌘V` clipboard panel, the `⌥R` reminder input and the reminder card are separate
surfaces and unchanged by all this. The tap keeps running while the status panel is open,
but `AppDelegate.handleTyped` drops keystrokes whenever any of the three panels is visible,
so typing `§sig` into the snippet editor can't expand the snippet into it.
