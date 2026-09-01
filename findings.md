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

## Battery reachability (verified 2026-09-01)
- Internal battery: IOPowerSources. Works. Read 46-49% during testing.
- Magic Mouse/Trackpad/Keyboard: IORegistry AppleDeviceManagementHIDEventService
  `BatteryPercent`. Implemented; none connected here so UNVERIFIED.
- AirPods: level travels over a Bluetooth profile Apple does not expose publicly.
  Apps that show it use private frameworks. NOT DONE.
- iPhone: no public channel for a paired iPhone's battery. `ioreg -k BatteryPercent`
  returned nothing with no device attached; needs retesting with an iPhone plugged
  in before claiming anything either way. NOT DONE.

## TCC identity trap (verified 2026-09-01)
- Ad-hoc signed apps are identified to TCC by cdhash. EVERY rebuild changes it,
  silently invalidating an Accessibility grant while the app still appears ticked
  in System Settings. Confirmed: user granted at 12:05, two rebuilds followed,
  and the app still reported accessibility=false.
- Workarounds: (a) grant AFTER the final build, or (b) sign with a stable
  self-signed certificate so identity survives rebuilds.

## Brightness (verified 2026-09-01)
- READ works via public IOKit: AppleARMBacklight -> IODisplayParameters ->
  brightness {min 0, max 65536}. WRITE does not: IODisplaySetFloatParameter
  returns -536870201 (kIOReturnUnsupported) on this machine.
- Private DisplayServices DOES work: dlopen +
  DisplayServicesGetBrightness/SetBrightness. Verified get 0.687 -> set 0.737 ->
  changed -> restored. Loaded via dlopen, not linked, so a future removal
  degrades to "unavailable" rather than failing to launch.
- Keyboard backlight: no working write path found. Keys stay with the system.

## Outlook: legacy AppleScript CANNOT see the real mailbox (verified 2026-09-01)
- Outlook 16.112.2 with `IsRunningNewOutlook = 1`, `RunningNewOutlook = 1`,
  `AllAccountsMigratedFromLegacy = 1` -- the new Hx engine.
- The .sdef still ships and AppleScript partly answers: `get version` works,
  `count of mail folders` returns 10. But `get every account` fails with -1728,
  `every exchange account` is empty, and the only visible folders are the local
  "On My Computer" set. The Inbox it exposes reports 0 messages.
- The real mailbox lives in HxStore.hxd and is not reachable through the legacy
  object model. So the brief's "start with AppleScript" plan does NOT work for
  new Outlook.
- Sound route: Microsoft Graph API (OAuth + Azure app registration). Reading
  HxStore.hxd or scraping Notification Center are both excluded -- the brief
  rules them out and they are fragile across releases.

## Open questions
- Does stopping OSDUIHelper require anything beyond killing it on macOS 26? Verify.
- Confirm ad-hoc signed bundle can hold a stable TCC identity across rebuilds.
