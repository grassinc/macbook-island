import Foundation
import PillCore

/// SwiftUI-facing mirror of the pure `ShelfStore`.
@MainActor
final class ShelfObservable: ObservableObject {
    @Published fileprivate(set) var items: [ShelfItem] = []
    /// Set while a drag is hovering the panel, so the drop zone can light up.
    @Published var isDropTargeted = false
    /// Set while the user is dragging an item OUT of the shelf. The panel must
    /// not collapse during this: collapsing removes the shelf from the view
    /// tree, which pulls the drag source out from under an in-flight drag.
    @Published var isDraggingOut = false
    /// Last transform failure, surfaced in the panel rather than swallowed.
    @Published fileprivate(set) var lastError: String?
}

/// The file shelf and screenshot tray (brief features 3, 5 and 6).
///
/// One module serves both because they are the same object: files with
/// thumbnails you can drag back out. The only difference is how they arrive.
@MainActor
final class ShelfModule: PillModule {
    static let identifier = "shelf"

    private let store = ShelfStore(capacity: 20)
    private let observable: ShelfObservable
    private var context: ModuleContext?
    private var watcher: ScreenshotWatcher?
    private let dragEnd = DragEndMonitor()

    /// Called when a drag-out finishes, so the panel can re-evaluate collapsing.
    var onDragEnded: (() -> Void)?

    /// How long a newly caught screenshot announces itself in the collapsed pill.
    private let announceFor: TimeInterval = 4

    init(observable: ShelfObservable) {
        self.observable = observable
    }

    func activate(context: ModuleContext) {
        self.context = context

        // Restore before wiring onChange, so reinstating the saved shelf does
        // not immediately write it back out.
        store.restore(ShelfPersistence.load())
        pruneMissing()
        observable.items = store.items
        Log.activity.notice("shelf restored \(self.store.items.count, privacy: .public) item(s)")

        store.onChange = { [weak self] in
            guard let self else { return }
            self.observable.items = self.store.items
            ShelfPersistence.save(self.store.items)
        }

        let watcher = ScreenshotWatcher { [weak self] urls in
            DispatchQueue.main.async { self?.captured(urls) }
        }
        watcher.start()
        self.watcher = watcher
        Log.activity.notice("shelf watching \(ScreenshotWatcher.captureDirectory().path, privacy: .public)")
    }

    func deactivate() {
        dragEnd.stop()
        watcher?.stop()
        watcher = nil
        store.onChange = nil
        context?.retract(id: Self.identifier)
    }

    // MARK: - Adding

    /// Files dropped on the pill. Parking a file is silent — the user just did
    /// it deliberately, so announcing it back to them is noise.
    func addDropped(_ urls: [URL]) {
        let now = Date()
        for url in urls {
            store.add(ShelfItem(url: url, addedAt: now, source: .dropped))
        }
    }

    /// Screenshots arrive unannounced, so these do get a pill notification.
    private func captured(_ urls: [URL]) {
        let now = Date()
        for url in urls {
            store.add(ShelfItem(url: url, addedAt: now, source: .screenshot))
        }
        guard let newest = urls.last else { return }
        context?.publish(Activity(
            id: Self.identifier,
            kind: .screenshot,
            title: newest.lastPathComponent,
            subtitle: "Screenshot",
            priority: .transient,
            startedAt: now,
            expiresAt: now.addingTimeInterval(announceFor)
        ))
        Log.activity.notice("caught screenshot \(newest.lastPathComponent, privacy: .public)")
    }

    /// Called when the panel opens, so the user never sees a tile for a file
    /// that is no longer there.
    func pruneMissing() {
        store.pruneMissing { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Dragging out

    /// The mouse-up monitor runs only for the duration of a drag, so the idle
    /// path keeps no event monitors installed.
    func beginDrag() {
        observable.isDraggingOut = true
        dragEnd.onDragEnd = { [weak self] in
            guard let self, self.observable.isDraggingOut else { return }
            self.observable.isDraggingOut = false
            self.dragEnd.stop()
            Log.activity.debug("drag-out finished")
            self.onDragEnded?()
        }
        dragEnd.start()
        Log.activity.debug("drag-out started")
    }

    // MARK: - Acting on items

    func remove(_ item: ShelfItem) {
        store.remove(id: item.id)
    }

    func clear() {
        store.clear()
    }

    /// Runs a transform and parks the result on the shelf next to its source,
    /// so the output is immediately draggable too.
    func runTransform(_ action: TransformAction, on item: ShelfItem) {
        observable.lastError = nil
        do {
            let output = try TransformRunner.run(action, on: item)
            store.add(ShelfItem(url: output, addedAt: Date(), source: .dropped))
            Log.activity.notice("transform \(action.title, privacy: .public) -> \(output.lastPathComponent, privacy: .public)")
        } catch {
            observable.lastError = error.localizedDescription
            Log.activity.error("transform failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
