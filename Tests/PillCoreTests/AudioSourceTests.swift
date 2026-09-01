import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

private func src(_ bundle: String, pid: Int32 = 1, outputting: Bool = true,
                 name: String = "", startedAt: Date? = nil) -> AudioSource {
    AudioSource(pid: pid, bundleID: bundle, name: name.isEmpty ? bundle : name,
                isOutputting: outputting, startedOutputtingAt: startedAt ?? t0)
}

func runAudioSourceTests(_ r: TestRunner) {

    // Verified live on this machine: 18 audio processes exist, and all but one
    // are system infrastructure that is永 present and outputting nothing.
    r.test("only a process actually outputting audio is chosen") { r in
        let sources = [src("app.zen-browser.zen", outputting: false), src("com.spotify.client", outputting: true)]
        r.expectEqual(NowPlayingSelector.primary(from: sources)?.bundleID, "com.spotify.client",
                      "silent apps are not 'what you are listening to'")
    }

    // These sit in the process list permanently. Showing "controlcenter is
    // playing" would be nonsense.
    r.test("system audio infrastructure is never reported as the source") { r in
        for bundle in ["com.apple.audiomxd", "com.apple.mediaremoted", "com.apple.controlcenter",
                       "com.apple.assistantd", "com.apple.CoreSpeech", "com.apple.PowerChime",
                       "com.apple.avconferenced", "com.apple.TelephonyUtilities"] {
            r.expect(NowPlayingSelector.primary(from: [src(bundle)]) == nil, "\(bundle) is infrastructure")
        }
    }

    r.test("Pill never reports itself") { r in
        r.expect(NowPlayingSelector.primary(from: [src("com.pill.app")]) == nil, "self is excluded")
    }

    r.test("a process with no bundle id is ignored") { r in
        r.expect(NowPlayingSelector.primary(from: [src("")]) == nil, "anonymous processes are not shown")
    }

    r.test("a real app wins over infrastructure in the same list") { r in
        let sources = [src("com.apple.controlcenter"), src("com.apple.audiomxd"), src("app.zen-browser.zen")]
        r.expectEqual(NowPlayingSelector.primary(from: sources)?.bundleID, "app.zen-browser.zen",
                      "the real app is the answer")
    }

    // The bug this replaces: selecting by lowest pid meant a browser started
    // hours ago always beat Spotify, because browsers hold an output stream
    // open even when nothing audible is playing. What the user means by "what
    // I am listening to" is whatever most recently STARTED.
    r.test("the most recently started source wins over a long-running one") { r in
        let sources = [
            src("app.zen-browser.zen", pid: 675, startedAt: t0),
            src("com.spotify.client", pid: 14946, startedAt: t0.addingTimeInterval(3600)),
        ]
        r.expectEqual(NowPlayingSelector.primary(from: sources)?.bundleID, "com.spotify.client",
                      "Spotify started later, so it is what you are listening to")
    }

    r.test("list order still cannot change the answer") { r in
        let a = [src("com.spotify.client", pid: 20, startedAt: t0.addingTimeInterval(10)),
                 src("app.zen-browser.zen", pid: 10, startedAt: t0)]
        r.expectEqual(NowPlayingSelector.primary(from: a)?.pid,
                      NowPlayingSelector.primary(from: a.reversed())?.pid,
                      "order of the list must not change the answer")
    }

    r.test("identical start times fall back to a stable tiebreak") { r in
        let a = [src("com.spotify.client", pid: 20, startedAt: t0), src("app.zen-browser.zen", pid: 10, startedAt: t0)]
        r.expectEqual(NowPlayingSelector.primary(from: a)?.pid,
                      NowPlayingSelector.primary(from: a.reversed())?.pid,
                      "ties do not flicker")
    }

    r.test("nothing playing means nothing to show") { r in
        r.expect(NowPlayingSelector.primary(from: []) == nil, "empty list")
        r.expect(NowPlayingSelector.primary(from: [src("com.spotify.client", outputting: false)]) == nil,
                 "present but silent")
    }
}
