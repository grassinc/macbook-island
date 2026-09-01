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
