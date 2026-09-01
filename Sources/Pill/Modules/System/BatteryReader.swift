import Foundation
import IOKit
import IOKit.ps
import PillCore

/// Reads battery levels for the Mac and connected accessories.
///
/// What is actually reachable with public API:
///  - The internal battery, via IOPowerSources. Reliable.
///  - Magic Mouse / Magic Trackpad / Magic Keyboard, via the IORegistry
///    `BatteryPercent` property on AppleDeviceManagementHIDEventService.
///
/// What is NOT reachable, and why:
///  - AirPods: the level is exchanged over a Bluetooth profile Apple does not
///    expose publicly. Third-party apps that show it use private frameworks.
///  - iPhone: there is no public channel for a paired iPhone's battery. Over USB
///    the device appears in the IORegistry, so this scans for a battery property
///    there, but Apple does not document one and it may simply be absent.
enum BatteryReader {

    static func read() -> [BatteryState] {
        internalBatteries() + hidAccessoryBatteries()
    }

    // MARK: Internal

    private static func internalBatteries() -> [BatteryState] {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }

        return sources.compactMap { source in
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0
            else { return nil }

            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            let name = (description[kIOPSNameKey] as? String) ?? "Battery"
            return BatteryState(level: Double(current) / Double(maximum),
                                isCharging: charging,
                                source: .internalBattery,
                                name: name)
        }
    }

    // MARK: Accessories

    /// Magic Mouse / Trackpad / Keyboard publish `BatteryPercent` here.
    private static func hidAccessoryBatteries() -> [BatteryState] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var found: [BatteryState] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let percent = property(service, "BatteryPercent") as? Int else { continue }
            let name = (property(service, "Product") as? String) ?? "Accessory"
            found.append(BatteryState(level: Double(percent) / 100.0,
                                      isCharging: false,
                                      source: .bluetoothAccessory,
                                      name: name))
        }
        return found
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
