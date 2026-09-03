import Foundation
import PillCore

func runProfileTests(_ runner: TestRunner) {
    runner.test("MAC normalisation") { t in
        // arp prints short octets; people write padded ones. Both must match or
        // a profile silently never fires.
        t.expectEqual(NetworkIdentity.normalizeMAC("0:9:f:9:1:1a"), "00:09:0f:09:01:1a",
                      "short octets are padded")
        t.expectEqual(NetworkIdentity.normalizeMAC("00:09:0F:09:01:1A"), "00:09:0f:09:01:1a",
                      "case is folded")
        t.expectEqual(NetworkIdentity.normalizeMAC("garbage"), nil, "junk is rejected, not guessed")
        t.expectEqual(NetworkIdentity.normalizeMAC("0:9:f:9:1"), nil, "five octets is not a MAC")
        t.expectEqual(NetworkIdentity.normalizeMAC(""), nil, "empty is nil")
    }

    runner.test("ProfileMatcher") { t in
        let home = NetworkProfile(name: "Home", ssid: "Abu-WiFi")
        let work = NetworkProfile(name: "Work", gateway: "00:09:0F:09:01:1A",
                                  screenShare: true, hideFromCapture: true)
        let profiles = [home, work]

        t.expectEqual(ProfileMatcher.match(profiles, to: NetworkIdentity(ssid: "Abu-WiFi"))?.name,
                      "Home", "matches on SSID")
        t.expectEqual(ProfileMatcher.match(profiles, to: NetworkIdentity(ssid: "abu-wifi"))?.name,
                      "Home", "SSID match is case-insensitive")
        // The gateway is written padded and read short; they must still meet.
        t.expectEqual(ProfileMatcher.match(profiles, to: NetworkIdentity(gatewayMAC: "0:9:f:9:1:1a"))?.name,
                      "Work", "matches on gateway even when written differently")
        t.expectEqual(ProfileMatcher.match(profiles, to: NetworkIdentity(ssid: "Cafe"))?.name,
                      nil, "an unknown network matches nothing")
        t.expectEqual(ProfileMatcher.match([], to: NetworkIdentity(ssid: "Abu-WiFi"))?.name,
                      nil, "no profiles, no match")

        // SSID is preferred: it survives a router swap.
        let both = [NetworkProfile(name: "ByGateway", gateway: "0:9:f:9:1:1a"),
                    NetworkProfile(name: "BySSID", ssid: "Abu-WiFi")]
        t.expectEqual(ProfileMatcher.match(both, to: NetworkIdentity(ssid: "Abu-WiFi",
                                                                    gatewayMAC: "0:9:f:9:1:1a"))?.name,
                      "BySSID", "SSID wins over gateway")
    }

    runner.test("CalendarPeek.isImminent") { t in
        let now = Date()
        t.expect(CalendarPeek.isImminent(now.addingTimeInterval(300), at: now),
                 "five minutes away is imminent")
        t.expect(CalendarPeek.isImminent(now.addingTimeInterval(30 * 60), at: now),
                 "exactly at the window edge still counts")
        t.expect(!CalendarPeek.isImminent(now.addingTimeInterval(6 * 3600), at: now),
                 "six hours away is not, or it would sit on the pill all day")
        // A meeting that just started is still worth showing; one long finished is not.
        t.expect(CalendarPeek.isImminent(now.addingTimeInterval(-30), at: now),
                 "just started is still imminent")
        t.expect(!CalendarPeek.isImminent(now.addingTimeInterval(-300), at: now),
                 "five minutes past is done")
    }
}
