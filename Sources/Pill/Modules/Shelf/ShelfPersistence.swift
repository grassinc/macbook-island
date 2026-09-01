import Foundation
import PillCore

/// Saves and restores the shelf so parked files survive quitting Pill and
/// rebooting the Mac.
///
/// References are stored, not copies. Parking a file does not duplicate it or
/// silently consume disk, and dragging a tile out hands over the real file
/// rather than a stale clone. The trade-off is that moving or deleting the
/// original orphans the tile, which is why the shelf prunes missing files when
/// the panel opens.
enum ShelfPersistence {

    private static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Pill", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("shelf.json") }

    static func save(_ items: [ShelfItem]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            // Atomic so a crash mid-write cannot leave a truncated file that
            // fails to parse and silently empties the shelf on next launch.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.activity.error("shelf save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func load() -> [ShelfItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([ShelfItem].self, from: data)
        } catch {
            // A corrupt file must not block launch; start empty and move on.
            Log.activity.error("shelf load failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
