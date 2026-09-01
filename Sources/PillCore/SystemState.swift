import Foundation

/// Thermal pressure. The M1 Air is fanless, so sustained load throttles rather
/// than spinning up — which is exactly why this is worth surfacing.
public enum ThermalLevel: Equatable, Sendable, CaseIterable {
    case nominal, fair, serious, critical

    /// Only the levels the user can act on interrupt them. Warning at "fair"
    /// would make the indicator background noise and train them to ignore it.
    public var shouldWarn: Bool {
        self == .serious || self == .critical
    }

    public var label: String {
        switch self {
        case .nominal:  "Normal"
        case .fair:     "Warm"
        case .serious:  "Throttling"
        case .critical: "Overheating"
        }
    }
}

/// Where a battery reading came from.
public enum BatterySource: Equatable, Sendable {
    case internalBattery
    case bluetoothAccessory
    case connectedDevice
}

public struct BatteryState: Equatable, Sendable, Identifiable {
    public let level: Double        // 0...1
    public let isCharging: Bool
    public let source: BatterySource
    public let name: String

    public var id: String { "\(source)-\(name)" }

    public init(level: Double, isCharging: Bool, source: BatterySource, name: String) {
        self.level = min(max(level, 0), 1)
        self.isCharging = isCharging
        self.source = source
        self.name = name
    }

    public var percent: Int { Int((level * 100).rounded()) }

    /// Charging at 15% is not a problem, so it is not an alarm.
    public var isLow: Bool { !isCharging && level <= 0.20 }

    /// SF Symbols only ship battery glyphs at 0/25/50/75/100.
    public var symbol: String {
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case 88...100: return "battery.100"
        case 63..<88:  return "battery.75"
        case 38..<63:  return "battery.50"
        case 13..<38:  return "battery.25"
        default:       return "battery.0"
        }
    }
}
