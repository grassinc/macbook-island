import AppKit
import Foundation

/// Notices when a drag-out finishes.
///
/// SwiftUI's `.onDrag` tells us when a drag *starts* but never when it ends, and
/// the pill needs to know: it stays expanded for the duration so the drag source
/// is not torn out of the view tree mid-flight.
///
/// A drag always ends with a mouse-up, wherever that happens. Both monitors are
/// needed — the local one catches a release back over the pill, the global one
/// catches the release over the destination app, which is the normal case.
///
/// Mouse events do not require Accessibility for global monitoring (only key
/// events do), so this works with no permissions.
@MainActor
final class DragEndMonitor {

    var onDragEnd: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDragEnd?() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.onDragEnd?() }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
