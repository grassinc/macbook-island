import Foundation
@testable import PillCore

private func src(_ bundle: String, pid: Int32 = 1, outputting: Bool = true, name: String = "") -> AudioSource {
    AudioSource(pid: pid, bundleID: bundle, name: name.isEmpty ? bundle : name, isOutputting: outputting)
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

    // Two things playing at once: pick one deterministically rather than
    // flickering between them on every refresh.
    r.test("with several apps playing the choice is stable, not arbitrary") { r in
        let a = [src("com.spotify.client", pid: 20), src("app.zen-browser.zen", pid: 10)]
        let b = [src("app.zen-browser.zen", pid: 10), src("com.spotify.client", pid: 20)]
        r.expectEqual(NowPlayingSelector.primary(from: a)?.pid, NowPlayingSelector.primary(from: b)?.pid,
                      "order of the list must not change the answer")
    }

    r.test("nothing playing means nothing to show") { r in
        r.expect(NowPlayingSelector.primary(from: []) == nil, "empty list")
        r.expect(NowPlayingSelector.primary(from: [src("com.spotify.client", outputting: false)]) == nil,
                 "present but silent")
    }
}
