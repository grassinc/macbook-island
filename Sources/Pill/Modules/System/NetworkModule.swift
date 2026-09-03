import Foundation
import Network
import PillCore

@MainActor
final class NetworkStore: ObservableObject {
    @Published fileprivate(set) var state: NetworkState = .online
    @Published fileprivate(set) var identity = NetworkIdentity()
    /// The profile matching the current network, if the user has defined one.
    @Published fileprivate(set) var profile: NetworkProfile?
    @Published fileprivate(set) var profileCount = 0
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

    /// Applies a matched profile. Set by the app so this module does not have
    /// to know what a profile turns on.
    var onProfileChange: ((NetworkProfile?) -> Void)?

    init(store: NetworkStore) { self.store = store }

    /// Where the user writes their profiles. Kept out of the app so it can be
    /// edited without a rebuild.
    static var profilesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pill/profiles.json")
    }

    private var profiles: [NetworkProfile] = []

    private func loadProfiles() {
        guard let data = try? Data(contentsOf: Self.profilesURL),
              let decoded = try? JSONDecoder().decode([NetworkProfile].self, from: data) else {
            profiles = []
            store.profileCount = 0
            return
        }
        profiles = decoded
        store.profileCount = decoded.count
        Log.activity.notice("loaded \(decoded.count, privacy: .public) network profile(s)")
    }

    /// Identifies the current network.
    ///
    /// The SSID needs Location Services, which this app does not ask for, so the
    /// default gateway's MAC is the identifier that always works. It is stable
    /// per router and distinguishes home from work from a cafe without knowing
    /// -- or telling anyone -- where those places are.
    private func currentIdentity() -> NetworkIdentity {
        guard let gateway = shell("/sbin/route", ["-n", "get", "default"])?
                .split(separator: "\n")
                .first(where: { $0.contains("gateway:") })?
                .split(separator: ":").last?
                .trimmingCharacters(in: .whitespaces),
              !gateway.isEmpty else { return NetworkIdentity() }

        let mac = shell("/usr/sbin/arp", ["-n", gateway])?
            .split(separator: " ")
            .first(where: { $0.contains(":") && $0.split(separator: ":").count == 6 })
            .map(String.init)
        return NetworkIdentity(ssid: nil, gatewayMAC: mac)
    }

    private func shell(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private func refreshProfile() {
        let identity = currentIdentity()
        store.identity = identity
        let matched = ProfileMatcher.match(profiles, to: identity)
        guard matched != store.profile else { return }
        store.profile = matched
        Log.activity.notice("network profile: \(matched?.name ?? "none", privacy: .public) (gateway \(identity.gatewayMAC ?? "unknown", privacy: .public))")
        onProfileChange?(matched)
    }

    func activate(context: ModuleContext) {
        self.context = context
        monitor.pathUpdateHandler = { [weak self] path in
            let state: NetworkState = path.status == .satisfied ? .online : .offline
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(state) }
            }
        }
        monitor.start(queue: queue)
        loadProfiles()
    }

    func deactivate() {
        monitor.cancel()
        context?.retract(id: Self.identifier)
    }

    private func apply(_ state: NetworkState) {
        let changed = state != store.state
        store.state = state
        // The route table settles a moment after the path does, so the identity
        // is read on a short delay rather than immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated { self?.refreshProfile() }
        }

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
