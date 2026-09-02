import Foundation
import IOBluetooth
import PillCore

@MainActor
final class BluetoothStore: ObservableObject {
    @Published fileprivate(set) var connected: [String] = []
    /// Remembered so the pill can draw the right glyph for a device that has
    /// just disconnected, when it is too late to ask the device anything.
    @Published fileprivate(set) var kinds: [String: BluetoothDeviceKind] = [:]

    func kind(named name: String) -> BluetoothDeviceKind { kinds[name] ?? .other }
}

/// Bluetooth connect and disconnect, shown in the pill instead of the corner.
///
/// This is not notification interception, and could not be: there is no public
/// way to receive another app's banners, and the two private routes — reading
/// Notification Center's database and scraping the banner with the
/// Accessibility API — are both ruled out by the brief. What this does instead
/// is watch the same system state the system notification is generated from,
/// which is more reliable than scraping a banner and needs no permission at all.
///
/// `IOBluetooth` posts these as run-loop notifications. Verified on this Mac:
/// three paired devices enumerate and registration succeeds with no TCC prompt.
@MainActor
final class BluetoothModule: NSObject, PillModule {
    static let identifier = "bluetooth"

    private let store: BluetoothStore
    private var context: ModuleContext?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    init(store: BluetoothStore) {
        self.store = store
        super.init()
    }

    func activate(context: ModuleContext) {
        self.context = context

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:)))

        // Devices already connected at launch are watched for disconnect, but
        // never announced. Announcing them would fire a burst of banners every
        // time the app starts, for things the user connected long ago.
        for device in pairedDevices() where device.isConnected() {
            track(device)
            let name = device.name ?? "Device"
            store.kinds[name] = BluetoothDeviceKind.from(classOfDevice: UInt32(device.classOfDevice))
            store.connected.append(name)
        }
        Log.activity.notice("bluetooth watching, \(self.store.connected.count, privacy: .public) already connected")
    }

    func deactivate() {
        connectNotification?.unregister()
        connectNotification = nil
        for notification in disconnectNotifications.values { notification.unregister() }
        disconnectNotifications.removeAll()
        context?.retract(id: Self.identifier)
    }

    private func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    }

    /// A disconnect notification has to be registered per device, and only once
    /// it is connected — there is no global disconnect stream.
    private func track(_ device: IOBluetoothDevice) {
        let key = device.addressString ?? device.name ?? UUID().uuidString
        disconnectNotifications[key]?.unregister()
        disconnectNotifications[key] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:)))
    }

    // IOBluetooth delivers these on the main run loop, which is why they can be
    // main-actor isolated: the selector is never called from anywhere else.
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification,
                                       device: IOBluetoothDevice) {
        announce(device, connected: true)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification,
                                          device: IOBluetoothDevice) {
        announce(device, connected: false)
    }

    private func announce(_ device: IOBluetoothDevice, connected: Bool) {
        let name = device.name ?? "Bluetooth device"
        store.kinds[name] = BluetoothDeviceKind.from(classOfDevice: UInt32(device.classOfDevice))
        if connected {
            track(device)
            if !store.connected.contains(name) { store.connected.append(name) }
        } else {
            let key = device.addressString ?? name
            disconnectNotifications[key]?.unregister()
            disconnectNotifications[key] = nil
            store.connected.removeAll { $0 == name }
        }
        Log.activity.notice("bluetooth \(name, privacy: .public) \(connected ? "connected" : "disconnected", privacy: .public)")

        let now = Date()
        context?.publish(Activity(
            id: Self.identifier,
            kind: .bluetooth,
            title: name,
            subtitle: connected ? "Connected" : "Disconnected",
            priority: .transient,
            startedAt: now,
            expiresAt: now.addingTimeInterval(3)
        ))
    }

    /// The glyph for the pill, from the device's Class of Device.
    static func symbol(for device: IOBluetoothDevice) -> String {
        symbol(for: BluetoothDeviceKind.from(classOfDevice: UInt32(device.classOfDevice)))
    }

    static func symbol(for kind: BluetoothDeviceKind) -> String {
        switch kind {
        case .headphones: "airpods.pro"
        case .speaker:    "hifispeaker.fill"
        case .mouse:      "magicmouse"
        case .keyboard:   "keyboard"
        case .phone:      "iphone"
        case .computer:   "laptopcomputer"
        case .other:      "dot.radiowaves.left.and.right"
        }
    }
}
