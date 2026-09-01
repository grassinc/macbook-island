import Foundation
import PillCore

@MainActor
final class ThermalStore: ObservableObject {
    @Published fileprivate(set) var level: ThermalLevel = .nominal
}

/// Thermal throttle indicator (brief feature 13).
///
/// The M1 Air is fanless, so sustained load throttles instead of spinning up a
/// fan — the machine just quietly gets slower, with no feedback. That is exactly
/// the gap worth filling.
///
/// `ProcessInfo` posts a notification on change, so this costs nothing at idle.
@MainActor
final class ThermalModule: PillModule {
    static let identifier = "thermal"

    private let store: ThermalStore
    private var context: ModuleContext?
    private var observer: NSObjectProtocol?

    init(store: ThermalStore) { self.store = store }

    func activate(context: ModuleContext) {
        self.context = context
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func deactivate() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        context?.retract(id: Self.identifier)
    }

    private func refresh() {
        let level: ThermalLevel = switch ProcessInfo.processInfo.thermalState {
        case .nominal:  .nominal
        case .fair:     .fair
        case .serious:  .serious
        case .critical: .critical
        @unknown default: .nominal
        }
        store.level = level
        Log.activity.notice("thermal=\(level.label, privacy: .public)")

        // Ambient priority: worth knowing, never worth interrupting for. It
        // stays until the machine cools rather than expiring on a timer.
        guard level.shouldWarn else {
            context?.retract(id: Self.identifier)
            return
        }
        context?.publish(Activity(
            id: Self.identifier,
            kind: .thermal,
            title: level.label,
            subtitle: "Thermal",
            priority: .ambient,
            startedAt: Date()
        ))
    }
}
