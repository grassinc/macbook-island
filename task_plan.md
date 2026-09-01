# Task Plan — Pill v0.1

**Goal:** Ship a working Dynamic-Island-style pill for macOS 26 on a 2020 M1 Air,
with three features: HUD replacement, audio output switcher, screenshot catch tray.

**Spec:** docs/superpowers/specs/2026-08-31-pill-design.md

## Global constraints
- macOS 26 deployment target. No back-compat shims for 13/14/15.
- No repeating timers anywhere. Event-driven only.
- Non-activating NSPanel; never steals focus; absent from Dock/Cmd-Tab/Mission Control.
- Modules cannot reach the window or each other.

## Phases
- [x] P0  Toolchain ready (CLT installed, swiftc verified)
- [x] P1  Buildable app bundle: SwiftPM package + Info.plist + build script + ad-hoc sign
- [x] P2  Core model: Activity, ActivityPriority, ActivityCoordinator (+ tests, TDD)
- [~] P3  Window layer: panel, positioning, hover DONE.
        FULLSCREEN POLICY NOT WIRED -- geometry is designed and unit-tested
        (PillGeometry.isMenuBarHidden) but the controller never observes
        activeSpaceDidChange, so the pill does NOT yet hide over fullscreen apps.
- [x] P4  Module boundary: PillModule, ModuleContext, registry
- [x] P5  Audio output switcher module (CoreAudio, no permissions)
- [x] P6  HUD volume (done). Brightness/backlight keys pass through, NOT yet handled
- [~] P8  Permission onboarding: just-in-time Accessibility row in the panel (done);
          full first-run window still pending

## Added at owner's request 2026-09-01 (brief features 3, 5, 6)
The shelf and the screenshot tray are the same thing wearing two hats: items with
thumbnails you can drag out. They share one ShelfItem model rather than being
built twice.
- [x] P10 ShelfItem model + ShelfStore (TDD: capacity, dedupe, ordering, expiry)
- [x] P11 File shelf: drag files IN (NSDraggingDestination) and OUT (NSFilePromise)
- [x] P12 Screenshot tray (brief #5): watch the capture dir, feed the same shelf
- [x] P13 Drop-to-transform (brief #6): HEIC->JPG, resize, zip, strip EXIF, ->PDF
- [ ] P9  Verification: idle CPU, focus-stealing, full manual pass


## Known gaps (honest list, 2026-09-01)
- Fullscreen hide/reveal: designed + geometry tested, NOT wired into the window.
- Brightness and keyboard-backlight HUD: keys are deliberately passed through,
  so they still work natively. Not implemented.
- Accessibility is not granted, so the volume HUD MIRRORS Apple's overlay rather
  than replacing it. The panel offers a row to grant it.
- Audio switching is unverified end-to-end: this machine has one output device.
- Screenshot detection falls back to "image file created in the last 10s" when
  Spotlight has not yet set kMDItemIsScreenCapture, so an image saved to the
  Desktop by other means can land in the shelf.
- No full first-run onboarding window yet.
