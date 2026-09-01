import Foundation
import CoreGraphics
@testable import PillCore

// macOS screen coordinates: origin bottom-left, y increases upward.
// The built-in display on this machine is 2560x1600 at 2x => 1440x900 points.
private let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)

func runPillGeometryTests(_ r: TestRunner) {

    r.test("pill is horizontally centred on its screen") { r in
        let origin = PillGeometry.origin(forSize: CGSize(width: 200, height: 32),
                                         onScreen: builtIn, topInset: 0)
        r.expectEqual(origin.x, 620, "centred: (1440 - 200) / 2")
    }

    r.test("pill hangs from the top edge, overlapping the menu bar") { r in
        let origin = PillGeometry.origin(forSize: CGSize(width: 200, height: 32),
                                         onScreen: builtIn, topInset: 0)
        r.expectEqual(origin.y, 868, "top-anchored: 900 - 0 - 32")
    }

    r.test("top inset pushes the pill down from the screen edge") { r in
        let origin = PillGeometry.origin(forSize: CGSize(width: 200, height: 32),
                                         onScreen: builtIn, topInset: 4)
        r.expectEqual(origin.y, 864, "900 - 4 - 32")
    }

    r.test("a screen with a non-zero origin still centres correctly") { r in
        // A second display placed to the left of the built-in one.
        let external = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let origin = PillGeometry.origin(forSize: CGSize(width: 300, height: 32),
                                         onScreen: external, topInset: 0)
        r.expectEqual(origin.x, -1110, "-1920 + (1920 - 300)/2")
        r.expectEqual(origin.y, 1048, "1080 - 32")
    }

    // Fullscreen detection without Screen Recording permission: when an app goes
    // fullscreen the menu bar auto-hides, and visibleFrame then reaches the top
    // of the screen. The Dock only affects the bottom, so comparing maxY is safe.
    r.test("menu bar showing is detected as not fullscreen") { r in
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)  // 25pt menu bar
        r.expect(PillGeometry.isMenuBarHidden(screenFrame: builtIn, visibleFrame: visible) == false,
                 "menu bar present should read as not hidden")
    }

    r.test("visible frame reaching the top edge is detected as fullscreen") { r in
        r.expect(PillGeometry.isMenuBarHidden(screenFrame: builtIn, visibleFrame: builtIn) == true,
                 "visibleFrame flush with the top means the menu bar is hidden")
    }

    r.test("a Dock at the bottom does not read as fullscreen") { r in
        // Dock reduces height from the bottom: origin.y rises, maxY unchanged.
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        r.expect(PillGeometry.isMenuBarHidden(screenFrame: builtIn, visibleFrame: visible) == false,
                 "a Dock must not be mistaken for fullscreen")
    }

    // Custom placement: the user can drag the pill somewhere else.

    r.test("a custom placement positions by the pill's centre, not its left edge") { r in
        // Centre must stay put when the pill grows on hover, otherwise the panel
        // visibly slides sideways every time it opens.
        let placement = PillPlacement(centerX: 400, topInset: 10)
        let collapsed = PillGeometry.origin(forSize: CGSize(width: 190, height: 30),
                                            onScreen: builtIn, placement: placement)
        let expanded = PillGeometry.origin(forSize: CGSize(width: 360, height: 288),
                                           onScreen: builtIn, placement: placement)
        r.expectEqual(collapsed.x, 305, "400 - 190/2")
        r.expectEqual(expanded.x, 220, "400 - 360/2")
        r.expectEqual(collapsed.x + 95, expanded.x + 180, "centre is identical in both states")
    }

    r.test("a custom placement respects its distance from the top") { r in
        let origin = PillGeometry.origin(forSize: CGSize(width: 190, height: 30),
                                         onScreen: builtIn,
                                         placement: PillPlacement(centerX: 400, topInset: 40))
        r.expectEqual(origin.y, 830, "900 - 40 - 30")
    }

    // Dragging the pill nearly off-screen must not strand it somewhere the
    // pointer cannot reach it again.
    r.test("placement is clamped so the pill stays reachable") { r in
        let offLeft = PillGeometry.clamp(PillPlacement(centerX: -500, topInset: 10),
                                         forSize: CGSize(width: 190, height: 30), onScreen: builtIn)
        r.expectEqual(offLeft.centerX, 95, "half the pill width from the left edge")

        let offRight = PillGeometry.clamp(PillPlacement(centerX: 5000, topInset: 10),
                                          forSize: CGSize(width: 190, height: 30), onScreen: builtIn)
        r.expectEqual(offRight.centerX, 1345, "1440 - 95")
    }

    r.test("placement cannot be dragged above the screen or below its bottom") { r in
        let tooHigh = PillGeometry.clamp(PillPlacement(centerX: 700, topInset: -80),
                                         forSize: CGSize(width: 190, height: 30), onScreen: builtIn)
        r.expectEqual(tooHigh.topInset, 0, "cannot go above the top edge")

        let tooLow = PillGeometry.clamp(PillPlacement(centerX: 700, topInset: 4000),
                                        forSize: CGSize(width: 190, height: 30), onScreen: builtIn)
        r.expectEqual(tooLow.topInset, 870, "900 - 30, still fully on screen")
    }

    r.test("a placement round-trips through JSON so it survives a restart") { r in
        let placement = PillPlacement(centerX: 512.5, topInset: 18)
        guard let data = try? JSONEncoder().encode(placement),
              let back = try? JSONDecoder().decode(PillPlacement.self, from: data) else {
            r.expect(false, "round trip threw"); return
        }
        r.expectEqual(back, placement, "survives encoding")
    }
}
