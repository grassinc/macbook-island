import Foundation

/// What sort of Bluetooth device connected, decoded from its Class of Device.
///
/// The class is a bitfield defined by the Bluetooth SIG: bits 8-12 are the major
/// device class and bits 2-7 the minor. Decoding it is what lets the pill show
/// headphones for AirPods and a mouse for a mouse, rather than one generic
/// Bluetooth glyph for everything.
public enum BluetoothDeviceKind: Equatable, Sendable {
    case headphones
    case speaker
    case mouse
    case keyboard
    case phone
    case computer
    case other

    public static func from(classOfDevice: UInt32) -> Self {
        let major = (classOfDevice >> 8) & 0x1F
        let minor = (classOfDevice >> 2) & 0x3F
        switch major {
        case 0x01: return .computer
        case 0x02: return .phone
        case 0x04:                                  // Audio / Video
            switch minor {
            case 0x01, 0x02, 0x06: return .headphones   // headset, hands-free, headphones
            case 0x05: return .speaker
            default: return .headphones
            }
        case 0x05:                                  // Peripheral
            // The top two bits of the minor field say keyboard / pointing.
            switch (minor >> 4) & 0x03 {
            case 0x01: return .keyboard
            case 0x02: return .mouse
            default: return .other
            }
        default: return .other
        }
    }
}

/// Whether to advise unplugging, for battery longevity on Apple silicon.
///
/// Advice only: actually holding the charge would mean writing to the SMC,
/// which needs root and is not something this app should do to someone's
/// hardware. macOS may also be running Optimized Battery Charging already, so
/// this is a nudge and is said once per charge session, not repeatedly.
public enum ChargeAdvice {
    public static let healthyCeiling = 80

    public static func shouldSuggestUnplug(percent: Int,
                                           isCharging: Bool,
                                           alreadySuggested: Bool) -> Bool {
        isCharging && percent >= healthyCeiling && !alreadySuggested
    }

    /// Unplugging resets the advice, so the next charge session can nudge again.
    public static func shouldResetAdvice(isCharging: Bool) -> Bool { !isCharging }
}
