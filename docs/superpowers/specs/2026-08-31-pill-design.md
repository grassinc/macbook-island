# Pill — Design Spec (v0.1)

**Date:** 2026-08-31
**Status:** approved for implementation (scope, OS target, toolchain confirmed by project owner)

## 0. Corrections to the original brief

Two premises in the brief were wrong on the actual hardware. Both were verified
on this machine, not assumed.

| Brief said | Reality on this machine | Consequence |
|---|---|---|
| Target "macOS 13 Ventura and later" | `MacBookAir10,1`, 8 GB, running **macOS 26.6.2** (build 25G83) | v0.1 targets macOS 26 only. We cannot verify Ventura, and unverified support is a liability. |
| MediaRemote "progressively locked down — verify what is accessible" | Access is gated on **code identity**, not entitlements | Media player cannot be an in-process call. Deferred out of v0.1. See §4. |

The "no physical notch" premise is correct and load-bearing: `MacBookAir10,1`
has no notch, so the pill is a free-floating rounded rect whose width we own
completely. Nothing in the layout has to accommodate a hardware cutout.

## 1. Architecture

### 1.1 Window layer

A single `NSPanel` subclass, `PillPanel`, created once and reused for every state.

```
styleMask          [.borderless, .nonactivatingPanel]
level              .statusBar + 1   (above menu bar, below screen-lock UI)
collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
isFloatingPanel    true
hidesOnDeactivate  false
backgroundColor    .clear, isOpaque = false, hasShadow = false (shadow drawn in SwiftUI)
canBecomeKey       false by default; true only while a text field is focused
canBecomeMain      always false
```

`LSUIElement = true` in `Info.plist` keeps the process out of the Dock and the
`Cmd-Tab` switcher. `.ignoresCycle` and `.stationary` keep the panel out of
Mission Control and stop it sliding during space transitions. Together these
satisfy the brief's "must not steal focus or appear in Mission Control / the
app switcher."

**Sizing and hit-testing.** The panel is sized tightly to the current visual
state and animates its own frame; it is never a large transparent overlay.
A full-width invisible panel would swallow menu-bar clicks, which is the single
most common way these utilities become infuriating. Hover is detected with an
`NSTrackingArea` (`.mouseEntered`, `.mouseExited`, `.activeAlways`) — purely
event-driven, no polling. The collapsed panel carries a few points of invisible
margin so the hover target is slightly larger than the visible pill.

**Positioning.** Anchored top-center of the screen that owns the menu bar.
Recomputed on `NSApplication.didChangeScreenParametersNotification` only.

### 1.2 Fullscreen behaviour — decision and justification

**Decision: hide entirely by default; reveal on deliberate top-edge hover.
Interruptive activities (§1.3) still show, briefly.**

Justification. In fullscreen the menu bar auto-hides, which is an explicit
statement from the user that the top strip belongs to their content. A pill
that floats over a fullscreen video or editor is occlusion, not information.
But hiding unconditionally would break the HUD — the user pressing volume-up in
fullscreen still needs feedback, and that is exactly when the system HUD is the
only feedback they have.

So the rule is split by *who initiated*:

- **User-initiated at the pill** (moving the pointer to the top edge) → reveal.
  This costs nothing, because pushing to the top edge is already the gesture for
  revealing the menu bar. No new muscle memory.
- **User-initiated elsewhere** (pressing volume-up) → show the interruptive
  activity for its normal duration, then hide. The user asked for feedback.
- **Everything else** (a screenshot lands, ambient state changes) → stay hidden.
  Queue it; it will be there when they leave fullscreen.

Detection is event-driven: on `NSWorkspace.activeSpaceDidChangeNotification`
compare the screen's `frame` to its `visibleFrame`. When the menu bar is hidden
by a fullscreen app the two are equal. This needs no Screen Recording
permission and no window-list enumeration.

### 1.3 Activity queue and priority

The brief's hardest question is what the collapsed pill shows when several
things compete. The answer is a single ranked queue with preemption, not a
carousel — rotating content in a 200pt-wide strip is unreadable.

```swift
enum ActivityPriority: Int, Comparable {
    case ambient      = 0   // battery, idle state
    case info         = 10  // a digest, an unread count
    case transient    = 20  // screenshot landed, output device changed
    case interruptive = 30  // volume/brightness HUD — user is acting right now
}
```

An `Activity` is a value type with an `id`, a `priority`, an optional
`expiresAt`, and two view builders (collapsed, expanded). Modules publish and
retract activities; they never touch the window.

`ActivityCoordinator` holds them and selects what the collapsed pill shows:

1. Drop anything past `expiresAt`.
2. Take `max` by `(priority, startedAt)` — highest priority wins, newest breaks ties.
3. If the winner changed, cross-fade.

**Preemption and restoration is the rule that makes this feel right.** An
interruptive activity does not evict the previous one, it *covers* it. When the
HUD's 1.5s window closes, the coordinator re-selects and the pill falls back to
whatever was underneath. Pressing volume while a screenshot thumbnail is showing
must not destroy the thumbnail — that would be a data-loss bug wearing a UI
costume.

Expiry uses one-shot `DispatchWorkItem`s scheduled per activity, cancelled on
retraction. There is no repeating timer anywhere in the system.

### 1.4 Module (widget plugin) structure

```swift
protocol PillModule: AnyObject {
    static var identifier: String { get }
    func activate(context: ModuleContext)    // start event sources
    func deactivate()                        // tear down; must reach zero CPU
}
```

`ModuleContext` hands the module a `publish(Activity)` / `retract(id)` pair and
nothing else. Modules cannot see the panel, the queue, or each other. That
boundary is what lets a module be tested with no window on screen.

v0.1 uses **static in-process registration**, not dynamic bundle loading. A
plugin API is a public contract, and publishing one before the first three
modules exist would freeze a protocol designed against zero real users. The
`PillModule` boundary is deliberately shaped so a future `Bundle`-based loader
implements the same protocol without touching module code. Dynamic loading also
drags in codesigning and notarization problems that buy nothing at v0.1.

### 1.5 Permission onboarding

Progressive and just-in-time, never a wall of prompts at first launch. The
principle: **every feature that can work without a permission must work without
it**, and the UI has to be honest about what is degraded.

| Capability | Permission | Without it |
|---|---|---|
| Volume *display* | none (CoreAudio) | full function |
| Volume HUD *replacing Apple's* | **Accessibility** (event tap) | pill shows volume, but Apple's OSD also appears (duplicate) |
| Audio output switching | none (CoreAudio) | full function |
| Screenshot tray | Desktop folder (TCC, on first read) | tray stays empty |
| Brightness / keyboard-backlight HUD | **Accessibility** (`CGEventTap`) | volume HUD still works; brightness silently falls back to the system OSD |

First run shows a single explanatory window that names each permission, what it
unlocks, and what happens if it is refused — then a button that opens the
correct System Settings pane. Accessibility is requested only when the user
turns on brightness HUD, not at launch.

**TCC identity caveat.** Ad-hoc signed builds get their TCC identity from
signature plus path. Re-signing or moving the app re-prompts and can leave stale
entries in the Accessibility list. Build output therefore stays at one stable
path with one stable ad-hoc identity for the whole of v0.1.

### 1.6 Zero-CPU idle

The brief's "near-zero CPU, event-driven, no polling timers" is an architectural
constraint, not a performance goal, so it is stated as a rule: **no repeating
timer may enter the codebase.** Every source is a callback.

| Signal | Mechanism |
|---|---|
| Volume, mute, default-device change | `AudioObjectAddPropertyListenerBlock` |
| New screenshot | `FSEventStreamCreate` on the capture directory |
| Brightness / backlight keys | `CGEventTap` on `NSSystemDefined` (Accessibility) |
| Hover | `NSTrackingArea` |
| Display reconfiguration | `didChangeScreenParametersNotification` |
| Fullscreen transitions | `activeSpaceDidChangeNotification` |
| Activity expiry | one-shot `DispatchWorkItem` |

## 2. Feature-by-feature API risk assessment

Answering brief item 2. Assessed against macOS 26, on this machine.

### Blocked or badly degraded

- **(2) Media player — now playing, art, scrubbing.** The real finding of this
  review. `MediaRemote.framework` ships only `Support/mediaremoted` and
  `mediaremoteagent` on disk; the library itself lives in the dyld shared cache.
  `mediaremoted` holds ~40 private entitlements no third party can obtain.
  Since macOS 15.4 the now-playing C API is gated, and the gate is **code
  identity**: `/usr/bin/perl` and `/usr/bin/ruby` carry *zero* entitlements yet
  report `Platform identifier=26` — they are Apple platform binaries. That is
  why the community `mediaremote-adapter` approach works by loading MediaRemote
  inside system Perl and piping JSON out, and why an in-process call from our
  app cannot work regardless of what we sign it with.
  *Fallback:* per-app AppleScript (Music, Spotify) covers metadata and transport
  but not arbitrary apps, and needs Automation consent per app. A helper-process
  design is viable but is its own project. **Deferred to v0.2.**
- **(9) Mic/camera in-use indicator naming the app.** The indicator state is
  observable; reliably attributing it to a *named* app is not, without private
  CoreAudio tap APIs or Endpoint Security entitlement. Expect "camera in use",
  not "Zoom is using your camera".
- **(14) Screen-share mode.** Detecting that a screen *is being shared* is the
  weak link; the suppression behaviour itself is easy. Depends on Screen
  Recording heuristics that vary by conferencing app.

### Reliable but permission- or consent-heavy

- **(1) HUD** — CoreAudio is free; brightness/backlight need Accessibility.
  Suppressing Apple's own OSD means stopping `OSDUIHelper`, which respawns.
- **(7) Battery for AirPods / Magic Mouse / trackpad / iPhone** — IOKit exposes
  built-in and some Bluetooth levels; iPhone requires a paired-device channel
  that is not generally available.
- **(8) Calendar peek** — EventKit, clean API, full-calendar consent prompt.
- **(11) Clipboard history** — `NSPasteboard` has **no change notification**.
  The only general mechanism is polling `changeCount`. This directly contradicts
  the no-polling rule; it is the one feature whose cost is structural.
- **(10) Download progress rings** — no system-wide download API. Requires
  per-source integration or watching `.download` files.
- **Email (Apple Mail)** — AppleScript/ScriptingBridge works and Automation
  consent is a normal prompt. The brief's instruction to avoid the Notification
  Center database is correct and should be held to.

### Low risk

(3) File shelf, (4) audio output switcher, (5) screenshot tray, (6)
drop-to-transform, (12) timers, (13) thermal state (`NSProcessInfo.thermalState`
is public and notification-driven), (15) Shortcuts via `shortcuts` CLI,
(16) Focus modes — readable, though the API is awkward.

## 3. v0.1 scope

Answering brief item 3. **HUD replacement + audio output switcher + screenshot
catch tray.**

Why these three:

1. **Zero private-API risk.** CoreAudio, FSEvents, and IOKit are all public and
   stable. Nothing here can be taken away by a point release — which is exactly
   what disqualified the media player.
2. **They exercise every subsystem.** The HUD forces interruptive priority and
   preemption; the screenshot tray forces transient expiry and drag-out; the
   audio switcher forces the expanded panel and a real click target. Between
   them they prove the window layer, the queue, the module boundary, and the
   zero-CPU claim. A v0.1 that did not stress the priority queue would be a
   demo, not a foundation.
3. **HUD and switcher are one coherent surface.** Both are "system output".
   Volume expands naturally into "…and here is where that audio is going",
   which is a better interaction than either feature alone.
4. **One optional permission.** Everything works out of the box except
   brightness, which degrades to the system OSD. Nothing is dead on first launch.

Deliberately excluded: media player (§2), file shelf (overlaps the tray without
testing expiry), email (a subsystem, and it needs the pill to be trustworthy
first).

## 4. Testing strategy

The window layer resists unit testing; the logic does not, and that is where the
bugs will be. Tests target `ActivityCoordinator` — priority ordering, tie-break
by recency, expiry, and specifically **preemption restoration** (that a HUD
covering a screenshot thumbnail restores it rather than dropping it). Module
event sources are behind protocols so they can be driven with synthetic events
and no hardware.
