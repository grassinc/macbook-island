# Findings — Pill

## Environment (verified 2026-08-31)
- Machine IS the target: MacBookAir10,1 (2020 M1), 8 GB. No notch — pill width is ours.
- macOS **26.6.2** (25G83), NOT Ventura 13 as the brief assumed.
- No Xcode, no CommandLineTools, no Homebrew at session start. `swiftc` was a stub.
- `/usr/bin/python3` is a CLT shim (non-functional). Real: perl 5.34.1, ruby 2.6.10.
- Disk: 126 GB free.

## MediaRemote gate — the decisive finding
- Framework dir has only `Support/mediaremoted` (10 MB) + `Support/mediaremoteagent`;
  the library itself is in the dyld shared cache.
- `mediaremoted` carries ~40 private entitlements (`com.apple.itunesstored.private`,
  `com.apple.airplay.receiver.mediaremote.services`, ...). Unobtainable by third parties.
- `/usr/bin/perl` and `/usr/bin/ruby`: **zero entitlements** but `Platform identifier=26`
  => Apple platform binaries.
- Conclusion: the post-15.4 gate keys on **code identity**, not entitlements. An
  in-process MediaRemote call from our app cannot work. Helper-process only.
  => Media player deferred out of v0.1.

## Screenshot capture settings
- `com.apple.screencapture location` is UNSET => defaults to ~/Desktop.
- `com.apple.screencapture type` is UNSET => defaults to png.
- Code must handle absent keys, not assume they exist.

## Toolchain gotchas (verified)
- `softwareupdate` only lists the CLT package while
  `/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress` exists.
  Dismissing the install dialog deletes it, so a later `softwareupdate --install`
  fails with "No such update". Arm the flag and install in one root shell.
- CLT has NO XCTest and NO swift-testing. Only the private XCTestSupport stub
  exists. A test framework requires full Xcode; we use a local harness instead.

## Suppressing Apple's volume OSD (verified 2026-09-01)
- OSDUIHelper is a LaunchAgent: /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist
  -> /System/Library/CoreServices/OSDUIHelper.app. Idle state is "not running";
  launchd starts it on demand when a volume/brightness key is pressed.
- `launchctl bootout gui/$UID/com.apple.OSDUIHelper` FAILS:
  "150: Operation not permitted while System Integrity Protection is engaged".
  Disabling the agent is therefore off the table (we will not ask anyone to
  disable SIP). The failed attempt changed nothing.
- Consequence, and a CORRECTION to the design spec: showing volume in the pill
  is permission-free (CoreAudio listener), but REPLACING Apple's overlay is not.
  The only clean way to stop the OSD appearing is to intercept the media keys
  with a CGEventTap and consume them, which needs Accessibility. Killing
  OSDUIHelper per-event is the alternative and it races, so the OSD can flash.
- CoreAudio volume ground truth: default device 72 exposes main-element
  kAudioDevicePropertyVolumeScalar (read 0.0625) and Mute. Per-channel volume is
  ABSENT on this device, so code must try main element first and fall back to
  channels for devices that only expose those.

## Open questions
- Does stopping OSDUIHelper require anything beyond killing it on macOS 26? Verify.
- Confirm ad-hoc signed bundle can hold a stable TCC identity across rebuilds.
