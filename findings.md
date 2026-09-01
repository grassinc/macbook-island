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

## Open questions
- Does stopping OSDUIHelper require anything beyond killing it on macOS 26? Verify.
- Confirm ad-hoc signed bundle can hold a stable TCC identity across rebuilds.
