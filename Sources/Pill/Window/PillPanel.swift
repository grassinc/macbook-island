import AppKit

/// The floating pill window.
///
/// A non-activating panel: clicking it must never pull focus away from whatever
/// the user is typing in, and it must not appear in Mission Control or the
/// Cmd-Tab switcher. `LSUIElement` in Info.plist handles the Dock and switcher;
/// the collection behaviour here handles the rest.
final class PillPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above the menu bar, which the pill deliberately overlaps.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        hidesOnDeactivate = false
        // Draggable by its background so the user can put it wherever they
        // like. SwiftUI controls consume their own mouse events, so buttons and
        // shelf-tile drags still work.
        isMovable = true
        isMovableByWindowBackground = true

        // The rounded shape and shadow are drawn in SwiftUI, so the window
        // itself is a clear rectangle.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        // Needed for hover tracking to fire without the panel being key.
        acceptsMouseMovedEvents = true
    }

    // Never steal focus. Text entry, if it is ever added, will need to flip
    // this on deliberately and only while a field is focused.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
