import Foundation
import PillCore

func runStatusLineTests(_ runner: TestRunner) {
    runner.test("StatusLine") { t in
        t.expectEqual(StatusLine.text(batteryPercent: 20, network: .offline),
                      "20%, Offline",
                      "charge and connectivity, in that order")
        t.expectEqual(StatusLine.text(batteryPercent: 20, network: .online),
                      "20%, Online",
                      "the connectivity word flips with the route")
        t.expectEqual(StatusLine.text(batteryPercent: 100, network: .online),
                      "100%, Online",
                      "a full battery is not a special case")

        // A Mac Mini or Studio reports no internal battery. Printing "0%" there
        // would be a lie about the hardware, so the charge is dropped instead.
        t.expectEqual(StatusLine.text(batteryPercent: nil, network: .offline),
                      "Offline",
                      "no battery means connectivity alone")
        t.expectEqual(StatusLine.text(batteryPercent: nil, network: .online),
                      "Online",
                      "no battery, connected")
    }

    runner.test("NetworkState") { t in
        t.expect(NetworkState.online.isOnline, "online is online")
        t.expect(!NetworkState.offline.isOnline, "offline is not online")
        t.expectEqual(NetworkState.offline.label, "Offline", "offline label")
        t.expectEqual(NetworkState.online.label, "Online", "online label")
    }
}
