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
