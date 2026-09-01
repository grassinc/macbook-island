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
- [x] P3  Window layer: PillPanel, positioning, hover tracking, fullscreen policy
- [x] P4  Module boundary: PillModule, ModuleContext, registry
- [x] P5  Audio output switcher module (CoreAudio, no permissions)
- [ ] P6  HUD module (volume first; brightness/backlight behind Accessibility)
- [ ] P7  Screenshot tray module (FSEvents + drag-out)
- [ ] P8  Permission onboarding window
- [ ] P9  Verification: idle CPU measurement, focus-stealing check, full manual pass
