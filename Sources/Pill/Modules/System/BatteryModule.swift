import Foundation
import IOKit.ps
import PillCore

@MainActor
final class BatteryStore: ObservableObject {
    @Published fileprivate(set) var batteries: [BatteryState] = []

    var mac: BatteryState? { batteries.first { $0.source == .internalBattery } }
    var accessories: [BatteryState] { batteries.filter { $0.source != .internalBattery } }
}

/// Battery and charging state (brief feature 7).
///
/// IOPowerSources posts a run-loop notification whenever anything changes, so
/// nothing here polls.
@MainActor
final class BatteryModule: PillModule {
    static let identifier = "battery"

    private let store: BatteryStore
    private var context: ModuleContext?
    private var runLoopSource: CFRunLoopSource?
    private var wasLow = false

    init(store: BatteryStore) { self.store = store }

    func activate(context: ModuleContext) {
        self.context = context

        let callback: IOPowerSourceCallbackType = { pointer in
            guard let pointer else { return }
            let module = Unmanaged<BatteryModule>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { module.refresh() } }
        }
        if let source = IOPSNotificationCreateRunLoopSource(
            callback, Unmanaged.passUnretained(self).toOpaque()
        )?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        refresh()
    }

    func deactivate() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        context?.retract(id: Self.identifier)
    }

    private func refresh() {
        store.batteries = BatteryReader.read()
        guard let mac = store.mac else { return }
        Log.activity.notice("battery \(mac.percent, privacy: .public)% charging=\(mac.isCharging, privacy: .public) accessories=\(self.store.accessories.count, privacy: .public)")

        // Announce only on the transition into low, not continuously. A warning
        // that is always present is furniture, and gets ignored.
        guard mac.isLow else {
            wasLow = false
            context?.retract(id: Self.identifier)
            return
        }
        guard !wasLow else { return }
        wasLow = true

        let now = Date()
        context?.publish(Activity(
            id: Self.identifier,
            kind: .battery,
            title: "\(mac.percent)%",
            subtitle: "Battery low",
            priority: .transient,
            startedAt: now,
            expiresAt: now.addingTimeInterval(6),
            progress: mac.level
        ))
    }
}
