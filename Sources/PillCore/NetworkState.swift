import Foundation

/// Whether the machine currently has a usable route to the internet.
public enum NetworkState: Equatable, Sendable {
    case online
    case offline

    public var label: String {
        switch self {
        case .online:  "Online"
        case .offline: "Offline"
        }
    }

    public var isOnline: Bool { self == .online }
}

/// The resting line the collapsed pill shows when nothing else is competing:
/// charge and connectivity, in that order.
///
/// This is the only thing on screen most of the time, so it is built from the
/// two facts that are always true and always cheap to know. A Mac with no
/// battery (a Mini, a Studio) drops the charge and shows connectivity alone
/// rather than printing a misleading zero.
public enum StatusLine {
    public static func text(batteryPercent: Int?, network: NetworkState) -> String {
        guard let batteryPercent else { return network.label }
        return "\(batteryPercent)%, \(network.label)"
    }
}
