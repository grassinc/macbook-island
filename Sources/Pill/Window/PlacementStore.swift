import Foundation
import PillCore

/// Remembers where the user dragged the pill.
///
/// `nil` means "wherever the default is" — top centre — rather than a stored
/// copy of the default, so the pill follows display changes until the user
/// deliberately moves it.
enum PlacementStore {
    private static let key = "pill.placement"

    static func load() -> PillPlacement? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PillPlacement.self, from: data)
    }

    static func save(_ placement: PillPlacement) {
        guard let data = try? JSONEncoder().encode(placement) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
