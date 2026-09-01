import Foundation
import CoreGraphics

/// Where the user has dragged the pill.
///
/// Stored as a CENTRE x rather than a left edge: the panel changes width when it
/// opens, and anchoring by the edge would make it visibly slide sideways on
/// every hover.
public struct PillPlacement: Equatable, Sendable, Codable {
    public var centerX: CGFloat
    /// Distance from the top of the screen to the top of the pill.
    public var topInset: CGFloat

    public init(centerX: CGFloat, topInset: CGFloat) {
        self.centerX = centerX
        self.topInset = topInset
    }
}

/// Pure placement maths for the pill. Kept free of AppKit so it can be tested
/// headlessly against synthetic screen layouts, including ones this machine
/// does not have.
public enum PillGeometry {

    /// Top-centre of the given screen, deliberately overlapping the menu bar.
    ///
    /// This machine has no notch, so there is no hardware cutout to accommodate
    /// and the pill's width is entirely ours to choose.
    public static func origin(forSize size: CGSize,
                              onScreen screenFrame: CGRect,
                              topInset: CGFloat) -> CGPoint {
        CGPoint(
            x: screenFrame.origin.x + (screenFrame.width - size.width) / 2,
            y: screenFrame.maxY - topInset - size.height
        )
    }

    /// Origin for a user-chosen placement.
    public static func origin(forSize size: CGSize,
                              onScreen screenFrame: CGRect,
                              placement: PillPlacement) -> CGPoint {
        CGPoint(
            x: placement.centerX - size.width / 2,
            y: screenFrame.maxY - placement.topInset - size.height
        )
    }

    /// Keeps a placement fully on screen.
    ///
    /// Without this the pill can be dragged almost entirely off an edge, and
    /// then there is nothing left to grab to drag it back.
    public static func clamp(_ placement: PillPlacement,
                             forSize size: CGSize,
                             onScreen screenFrame: CGRect) -> PillPlacement {
        let halfWidth = size.width / 2
        return PillPlacement(
            centerX: min(max(placement.centerX, screenFrame.minX + halfWidth),
                         screenFrame.maxX - halfWidth),
            topInset: min(max(placement.topInset, 0), screenFrame.height - size.height)
        )
    }

    /// Whether the menu bar is currently hidden on this screen, which is our
    /// proxy for "an app is fullscreen here".
    ///
    /// Comparing the top edges is enough: the Dock only ever shortens
    /// `visibleFrame` from the bottom, so `maxY` is unaffected by it. This
    /// avoids needing Screen Recording permission or window-list enumeration.
    public static func isMenuBarHidden(screenFrame: CGRect, visibleFrame: CGRect) -> Bool {
        visibleFrame.maxY >= screenFrame.maxY
    }
}
