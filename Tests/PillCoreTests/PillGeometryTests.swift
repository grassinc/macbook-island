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
}
