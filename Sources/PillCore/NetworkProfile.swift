import Foundation

/// How the machine identifies the network it is on.
///
/// Two identifiers, because the obvious one is not free. Reading the SSID needs
/// Location Services on macOS 14+ — verified here: `CWInterface.ssid()` returns
/// nil with authorization `notDetermined`, and `networksetup` claims you are not
/// associated at all. The default gateway's MAC address is not gated, is stable
/// for a given router, and identifies a network just as well. So the SSID is
/// used when it is available and the gateway fingerprint always is.
public struct NetworkIdentity: Equatable, Sendable {
    public let ssid: String?
    public let gatewayMAC: String?

    public init(ssid: String? = nil, gatewayMAC: String? = nil) {
        self.ssid = ssid
        self.gatewayMAC = NetworkIdentity.normalizeMAC(gatewayMAC)
    }

    public var isKnown: Bool { ssid != nil || gatewayMAC != nil }

    /// `arp` prints `0:9:f:9:1:1a` while people write `00:09:0F:09:01:1A`.
    /// Both must compare equal or a profile silently never matches.
    public static func normalizeMAC(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }
        var octets: [String] = []
        for part in parts {
            guard part.count <= 2, !part.isEmpty,
                  let value = UInt8(part, radix: 16) else { return nil }
            octets.append(String(format: "%02x", value))
        }
        return octets.joined(separator: ":")
    }
}

/// What the pill should do on a given network.
public struct NetworkProfile: Equatable, Sendable, Codable {
    public let name: String
    /// Match on either. SSID wins when both are present and both match.
    public let ssid: String?
    public let gateway: String?
    /// Turn on screen-share mode automatically — the point of a work profile.
    public let screenShare: Bool
    /// Hide the pill from screen recordings while on this network.
    public let hideFromCapture: Bool

    public init(name: String, ssid: String? = nil, gateway: String? = nil,
                screenShare: Bool = false, hideFromCapture: Bool = false) {
        self.name = name
        self.ssid = ssid
        self.gateway = gateway
        self.screenShare = screenShare
        self.hideFromCapture = hideFromCapture
    }
}

public enum ProfileMatcher {
    /// The first profile whose SSID matches wins; failing that, the first whose
    /// gateway matches. SSID is preferred because it survives a router swap and
    /// is what the user actually named the network.
    public static func match(_ profiles: [NetworkProfile],
                             to identity: NetworkIdentity) -> NetworkProfile? {
        if let ssid = identity.ssid,
           let hit = profiles.first(where: { $0.ssid?.caseInsensitiveCompare(ssid) == .orderedSame }) {
            return hit
        }
        if let mac = identity.gatewayMAC,
           let hit = profiles.first(where: { NetworkIdentity.normalizeMAC($0.gateway) == mac }) {
            return hit
        }
        return nil
    }
}
