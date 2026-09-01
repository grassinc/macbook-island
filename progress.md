# Progress — Pill

## 2026-08-31
- Verified environment; found no Swift toolchain. Triggered CLT install (920 MB).
- Corrected two wrong premises in the brief (OS version; MediaRemote mechanism).
- Design spec written: docs/superpowers/specs/2026-08-31-pill-design.md
- Scope locked with owner: macOS 26 target, CLT toolchain,
  v0.1 = HUD + audio output switcher + screenshot tray.
- Status: waiting on CLT download before any code can be compiled.

- CLT 26.6 installed; Swift 6.3.3, target arm64-apple-macosx26.0.
- Discovered CLT ships NO test framework (no XCTest, no swift-testing; only the
  private XCTestSupport stub). Wrote a ~50-line harness instead of requiring
  a 15 GB Xcode install. Suite runs via `swift run PillCoreTests`.
- P2 DONE: Activity, ActivityPriority, ActivityCoordinator. 11 checks green,
  including preemption-restoration (HUD covers a screenshot thumbnail and the
  thumbnail returns on expiry) and republish-replaces-by-id.
- P1+P3 DONE: app bundle builds, launches, pill visible at top-centre.
  Verified against the real display (CGWindowList, needs no Screen Recording):
    X=625 Y=2 W=190 H=30 layer=26 alpha=1.0
  X=625 == (1440-190)/2 exactly matches the centring unit test.
  Focus not stolen (frontmost stayed 'zen'); ApplicationType=UIElement;
  idle CPU time 0:00.93 -> 0:00.93 across 12s (zero), RSS 25 MB.
  Note: `screencapture` is blocked (no Screen Recording for the terminal), so
  visual checks use CGWindowListCopyWindowInfo instead.

## 2026-09-01
- P4+P5 DONE. Module boundary (PillModule/ModuleContext/ModuleRegistry, main-actor
  isolated) and the audio output switcher on public CoreAudio, zero permissions.
- ActivityPresenter schedules ONE wake-up at the next expiry instead of ticking.
- Verified live: hover 190x30 -> 320x82 -> 190x30. The 82 is 52 + 1 device x 30,
  confirming the expanded panel sizes itself to the real device count.
- CoreAudio ground truth here: a single output (id=72 'MacBook Air Speakers',
  transport bltn). The switcher is correct but has nothing to switch to until a
  second device is paired; end-to-end route-change announcement is UNVERIFIED
  for that reason.
- 44 checks green.
- P6 DONE (volume). Live: 6%->25% gave showing=hud, level=0.25, then
  showing=nothing 1.645s later. accessibility=false at launch, so the pill
  currently MIRRORS volume while Apple's OSD also shows; the panel now offers a
  just-in-time "Replace system volume HUD" row that requests Accessibility and
  retries the tap on expand (no polling). Expanded panel measured 320x116,
  matching 52 + 1 device*30 + 34 permission row.
- Brightness/keyboard-backlight keys are deliberately NOT consumed yet, so they
  keep working natively until implemented.
- Owner asked for the file shelf and transform options (brief 3/5/6); planned as
  P10-P13 on a shared ShelfItem model.
- P10-P13 DONE: shelf, screenshot tray, drag in/out, transforms.
- Live: fsevents saw the new Desktop file -> "caught screenshot" -> showing=shelf.
- Fixed hover flapping (tracking area rebuilt on resize caused exit/enter);
  180ms collapse grace. One clean transition per hover, was four.
- Idle CPU scare resolved: a reading of ~10% was launch-time work. Sampler showed
  all threads in semaphore_wait_trap, and a settled 20s re-measure gave 0.00%.
  113 checks green. RSS ~49 MB.

- Drag-OUT hardening for the park-then-send flow (drag a shelf item into
  WhatsApp/Mail/Finder):
  * Panel no longer collapses mid-drag. Dragging out means the pointer leaves
    the pill by definition, and collapsing tore the drag source out of the view
    tree. DragEndMonitor watches leftMouseUp (global + local; mouse events need
    no Accessibility) and only runs for the duration of a drag.
  * Shelf holds references, not copies, so tiles are pruned on panel open when
    the underlying file has been moved or deleted. Otherwise a dead tile fails
    silently at the moment of dropping into another app.
- KNOWN GAP: the shelf does NOT persist across restarts; quitting Pill empties it.

## 2026-09-01 (bug fix)
- PANEL WAS CLIPPING ITS OWN CONTENT. The expanded height was hand-computed by
  adding section heights, and the VStack spacing was never included: the formula
  gave 218pt where the content actually needs 260pt, so ~42pt was cut off the
  bottom (the permission row and part of the timer row simply were not visible).
- Fixed by making the panel self-measuring: width is chosen, height is REPORTED
  by the view via onGeometryChange. No arithmetic to rot when a section is added.
  Also removed a maxHeight: .infinity that is meaningless once height is
  unbounded. Verified 360x260 expanded, 190x30 collapsed, one clean hover cycle,
  no oscillation, 0% CPU.
- Deduped volume publishes: CoreAudio notifies both the volume and mute listeners
  for one change, so every keypress did the work (and the OSD dismissal) twice.
  Now 1 publish per change, verified.

## 2026-09-01 (brightness, signing, Graph email)
- Brightness HUD via DisplayServices (dlopen). Public IOKit reads but cannot
  write on Apple Silicon: IODisplaySetFloatParameter -> -536870201. Verified
  DS get 0.687 -> set 0.737 -> restored.
- Stable code-signing cert "Pill Local Dev" created and trusted. Designated
  requirement is now certificate-based and VERIFIED IDENTICAL across a rebuild,
  so TCC grants finally survive. The app's identity changed, so the old ad-hoc
  TCC entry is stale and must be re-granted ONCE.
- Outlook: Graph implementation complete (device-code OAuth, Mail.ReadBasic,
  refresh token in keychain, filter + digest, UI row). Blocked on the user
  creating an Azure app registration -- see docs/graph-setup.md.
- Fixed a NEW bug introduced by the self-measuring panel: onGeometryChange was
  reporting animated intermediate heights, so the window chased its own
  animation and settled at 345x265 instead of collapsing. Removed the SwiftUI
  size animation; the window controller animates the frame while SwiftUI lays
  out at the final size. Verified 190x30 -> 360x288 -> 190x30 twice.

## 2026-09-01 (collapse + movable pill)
- COLLAPSE BUG FIXED. Closing was driven by SwiftUI .onHover, which is not
  reliable for exit: the panel resizes under the pointer and when the window
  shrinks away AppKit may deliver no exit event at all, leaving the pill open.
  Closing is now driven by the real pointer position via a global mouse monitor
  installed only while the panel is open (mouse events need no Accessibility).
  6pt of slack so grazing an edge does not snap it shut.
- Also fixed: a spurious hover at launch left the pill expanded until the mouse
  next moved, because the panel is born at the origin and then moved into place.
  show() now settles the state explicitly.
- PILL IS NOW MOVABLE. Drag it anywhere; position persists across restarts.
  Cmd-/ resets it to top centre, registered through Carbon so it needs NO
  Accessibility permission. Placement is stored as a CENTRE x, so the pill does
  not slide sideways when it opens, and is clamped so it cannot be stranded
  off-screen.
- Two bugs found while testing placement: our own repositioning was being
  recorded as a user drag (the didMove notification races an async flag, and
  animation fires didMove for every intermediate frame). Now gated on the
  primary mouse button actually being down, which only a real drag produces.
- Verified: 190x30 -> 360x288 -> 190x30 on both downward and sideways exits,
  and the placement key stays unset through launch and a full hover cycle.
