import Foundation
import CoreGraphics

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
