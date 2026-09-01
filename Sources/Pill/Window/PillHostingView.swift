import AppKit
import SwiftUI

/// Hosting view that responds to the first click.
///
/// The panel never becomes key, and AppKit's default is to swallow the first
/// click into a non-key window as an activation click. Without this override
/// every button in the pill would need to be clicked twice.
final class PillHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
