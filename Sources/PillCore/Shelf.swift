import Foundation

/// Where a shelf item came from. Only affects presentation — a screenshot
/// announces itself in the pill, a dropped file does not.
public enum ShelfItemSource: String, Sendable, Equatable, Codable {
    case dropped
    case screenshot
}

/// A file parked in the shelf.
public struct ShelfItem: Identifiable, Equatable, Sendable, Codable {
    /// The file path. Identity is the path so the same file cannot occupy two
    /// tiles, however it arrived.
    public let id: String
    public let url: URL
    public let addedAt: Date
    public let source: ShelfItemSource

    public var name: String { url.lastPathComponent }
    public var fileExtension: String { url.pathExtension.lowercased() }

    public init(url: URL, addedAt: Date, source: ShelfItemSource = .dropped) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.addedAt = addedAt
        self.source = source
    }
}

/// Holds parked files, newest first.
///
/// Shared by the file shelf and the screenshot tray: both are "items with
/// thumbnails you can drag out", so they are one store rather than two
/// near-identical ones.
public final class ShelfStore {
    public private(set) var items: [ShelfItem] = []
    public let capacity: Int

    /// Fires on every mutation, so the app can refresh without polling.
    public var onChange: (() -> Void)?

    public init(capacity: Int = 20) {
        self.capacity = capacity
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Adding a file already on the shelf moves it back to the front instead of
    /// creating a second tile — dropping the same file twice is a normal slip.
    public func add(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if items.count > capacity {
            items.removeLast(items.count - capacity)
        }
        onChange?()
    }

    /// Reinstates a saved shelf at launch.
    ///
    /// Not a mutation from the user's point of view, so it deliberately does not
    /// fire `onChange` — doing so would write the file straight back out on every
    /// launch for no reason. Capacity still applies, in case it was lowered
    /// since the file was written.
    public func restore(_ saved: [ShelfItem]) {
        items = Array(saved.prefix(capacity))
    }

    public func remove(id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        onChange?()
    }

    /// Drops items whose files are no longer on disk.
    ///
    /// The shelf holds references, not copies, so a parked file can be moved or
    /// deleted behind our back. A tile pointing at nothing fails silently when
    /// dragged into another app, which is the worst way for the user to find
    /// out. Existence is injected so this is testable without touching a disk.
    public func pruneMissing(using exists: (URL) -> Bool) {
        let survivors = items.filter { exists($0.url) }
        guard survivors.count != items.count else { return }
        items = survivors
        onChange?()
    }

    public func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        onChange?()
    }
}
