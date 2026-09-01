import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

func runHUDTests(_ r: TestRunner) {

    r.test("an activity can carry a progress value for meters") { r in
        let a = Activity(id: "hud.volume", kind: .hud, title: "Volume",
                         priority: .interruptive, startedAt: t0, progress: 0.25)
        r.expectEqual(a.progress, 0.25, "progress is carried")
    }

    // A device can report a level slightly outside 0...1, and a meter drawn from
    // an unclamped value overflows its track.
    r.test("progress is clamped into 0...1") { r in
        let high = Activity(id: "a", kind: .hud, title: "", priority: .interruptive, startedAt: t0, progress: 1.4)
        let low = Activity(id: "b", kind: .hud, title: "", priority: .interruptive, startedAt: t0, progress: -0.3)
        r.expectEqual(high.progress, 1.0, "above range clamps to 1")
        r.expectEqual(low.progress, 0.0, "below range clamps to 0")
    }

    r.test("an activity with no meter has no progress") { r in
        let a = Activity(id: "x", priority: .info, startedAt: t0)
        r.expect(a.progress == nil, "progress stays nil when not supplied")
    }

    // Raw NX_KEYTYPE codes carried in NSSystemDefined events.
    r.test("system-defined key codes map to media keys") { r in
        r.expectEqual(MediaKey(keyCode: 0), .volumeUp, "NX_KEYTYPE_SOUND_UP")
        r.expectEqual(MediaKey(keyCode: 1), .volumeDown, "NX_KEYTYPE_SOUND_DOWN")
        r.expectEqual(MediaKey(keyCode: 7), .mute, "NX_KEYTYPE_MUTE")
        r.expectEqual(MediaKey(keyCode: 2), .brightnessUp, "NX_KEYTYPE_BRIGHTNESS_UP")
        r.expectEqual(MediaKey(keyCode: 3), .brightnessDown, "NX_KEYTYPE_BRIGHTNESS_DOWN")
        r.expectEqual(MediaKey(keyCode: 21), .keyboardBacklightUp, "NX_KEYTYPE_ILLUMINATION_UP")
        r.expectEqual(MediaKey(keyCode: 22), .keyboardBacklightDown, "NX_KEYTYPE_ILLUMINATION_DOWN")
    }

    r.test("unrelated key codes are ignored rather than misread") { r in
        // Play/pause is 16. We must not consume keys we do not handle, or we
        // would break the user's media controls.
        r.expect(MediaKey(keyCode: 16) == nil, "unhandled codes map to nil")
        r.expect(MediaKey(keyCode: 999) == nil, "nonsense codes map to nil")
    }

    // Volume steps match the system's 16 notches, so our stepping feels native.
    r.test("volume steps in sixteenths") { r in
        r.expectEqual(VolumeStepper.step(from: 0.5, direction: .up), 0.5625, "up one sixteenth")
        r.expectEqual(VolumeStepper.step(from: 0.5, direction: .down), 0.4375, "down one sixteenth")
    }

    r.test("volume stepping saturates at the ends instead of wrapping") { r in
        r.expectEqual(VolumeStepper.step(from: 1.0, direction: .up), 1.0, "cannot exceed full")
        r.expectEqual(VolumeStepper.step(from: 0.0, direction: .down), 0.0, "cannot go below silent")
    }
}
