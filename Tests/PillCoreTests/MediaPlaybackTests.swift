import Foundation
@testable import PillCore

func runMediaPlaybackTests(_ r: TestRunner) {

    // Real values read from Spotify on this machine.
    let track = MediaPlayback(
        title: "FE!N (feat. Playboi Carti)", artist: "Travis Scott", album: "UTOPIA",
        artworkURL: URL(string: "https://i.scdn.co/image/ab67616d0000b27304481c826dd292e5e4983b3f"),
        durationMilliseconds: 191_700, positionMilliseconds: 161_877, isPlaying: true)

    r.test("progress is position over duration") { r in
        r.expect(abs(track.progress - 0.8444) < 0.001, "161877 / 191700")
    }

    r.test("times read as minutes and seconds") { r in
        r.expectEqual(track.positionText, "2:41", "161.877s")
        r.expectEqual(track.durationText, "3:11", "191.7s")
    }

    // A track can report duration 0 before it has loaded; dividing by that
    // would produce NaN and blow up the progress bar's layout.
    r.test("zero duration yields zero progress rather than NaN") { r in
        let loading = MediaPlayback(title: "x", artist: "y", album: "", artworkURL: nil,
                                    durationMilliseconds: 0, positionMilliseconds: 0, isPlaying: false)
        r.expectEqual(loading.progress, 0, "no division by zero")
        r.expectEqual(loading.durationText, "0:00", "still formats")
    }

    r.test("progress cannot exceed one even if position overruns duration") { r in
        let overrun = MediaPlayback(title: "x", artist: "y", album: "", artworkURL: nil,
                                    durationMilliseconds: 1000, positionMilliseconds: 5000, isPlaying: true)
        r.expectEqual(overrun.progress, 1, "clamped")
    }

    // AppleScript formats numbers using the user's locale. This machine returns
    // "161,876998901367" for a position, so a naive Double(string) returns nil
    // and the scrubber silently sits at zero.
    r.test("locale-formatted numbers parse regardless of separator") { r in
        r.expectEqual(AppleScriptNumber.parse("161,876998901367"), 161.876998901367, "comma separator")
        r.expectEqual(AppleScriptNumber.parse("161.876998901367"), 161.876998901367, "dot separator")
        r.expectEqual(AppleScriptNumber.parse("191700"), 191700, "plain integer")
        r.expect(AppleScriptNumber.parse("not a number") == nil, "garbage is rejected")
    }

    r.test("a track with no artwork is still valid") { r in
        let bare = MediaPlayback(title: "Podcast", artist: "Someone", album: "", artworkURL: nil,
                                 durationMilliseconds: 60_000, positionMilliseconds: 0, isPlaying: true)
        r.expect(bare.artworkURL == nil, "artwork is optional")
        r.expectEqual(bare.durationText, "1:00", "still usable")
    }
}
