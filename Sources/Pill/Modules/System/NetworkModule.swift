import Foundation
import Network
import PillCore

@MainActor
final class NetworkStore: ObservableObject {
    @Published fileprivate(set) var state: NetworkState = .online
}

/// Connectivity for the resting pill.
///
/// `NWPathMonitor` calls back only when the route actually changes, so this
/// costs nothing while the network is stable — no reachability polling, no
/// timer. It is the same mechanism URLSession uses internally.
@MainActor
final class NetworkModule: PillModule {
    static let identifier = "network"

    private let store: NetworkStore
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.pill.network")
    private var context: ModuleContext?
    /// The first callback is the current state, not a change. Announcing it
    /// would flash "Offline" at every launch on a machine that simply has not
    /// associated yet.
    private var hasReading = false

    init(store: NetworkStore) { self.store = store }

    func activate(context: ModuleContext) {
        self.context = context
        monitor.pathUpdateHandler = { [weak self] path in
            let state: NetworkState = path.status == .satisfied ? .online : .offline
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(state) }
            }
        }
        monitor.start(queue: queue)
    }

    func deactivate() {
        monitor.cancel()
        context?.retract(id: Self.identifier)
    }

    private func apply(_ state: NetworkState) {
        let changed = state != store.state
        store.state = state
        guard hasReading else {
            hasReading = true
            Log.activity.notice("network=\(state.label, privacy: .public) (initial)")
            return
        }
        guard changed else { return }
        Log.activity.notice("network=\(state.label, privacy: .public)")

        // Losing the connection is worth saying once. Regaining it retracts the
        // warning rather than announcing again — the resting pill already shows
        // the word, so a second interruption would add nothing.
        guard !state.isOnline else {
            context?.retract(id: Self.identifier)
            return
        }
        let now = Date()
        context?.publish(Activity(
            id: Self.identifier,
            kind: .network,
            title: "Offline",
            subtitle: "No connection",
            priority: .transient,
            startedAt: now,
            expiresAt: now.addingTimeInterval(4)
        ))
    }
}
