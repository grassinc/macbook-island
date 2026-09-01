import Foundation
import PillCore

/// SwiftUI-facing mirror of the pure `ShelfStore`.
@MainActor
final class ShelfObservable: ObservableObject {
    @Published fileprivate(set) var items: [ShelfItem] = []
    /// Set while a drag is hovering the panel, so the drop zone can light up.
    @Published var isDropTargeted = false
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

    /// How long a newly caught screenshot announces itself in the collapsed pill.
    private let announceFor: TimeInterval = 4

    init(observable: ShelfObservable) {
        self.observable = observable
    }

    func activate(context: ModuleContext) {
        self.context = context

        store.onChange = { [weak self] in
            guard let self else { return }
            self.observable.items = self.store.items
        }

        let watcher = ScreenshotWatcher { [weak self] urls in
            DispatchQueue.main.async { self?.captured(urls) }
        }
        watcher.start()
        self.watcher = watcher
        Log.activity.notice("shelf watching \(ScreenshotWatcher.captureDirectory().path, privacy: .public)")
    }

    func deactivate() {
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
