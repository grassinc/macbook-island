import Foundation

/// The hardware keys the HUD replaces.
///
/// These are the `NX_KEYTYPE_*` codes carried in `NSSystemDefined` events.
public enum MediaKey: Equatable, Sendable {
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
    case keyboardBacklightUp, keyboardBacklightDown

    /// Returns nil for any key we do not handle.
    ///
    /// Mapping unknown codes to nil matters: the event tap only consumes keys
    /// that map to a case, so play/pause and track skip keep working normally.
    public init?(keyCode: Int32) {
        switch keyCode {
        case 0:  self = .volumeUp                 // NX_KEYTYPE_SOUND_UP
        case 1:  self = .volumeDown               // NX_KEYTYPE_SOUND_DOWN
        case 7:  self = .mute                     // NX_KEYTYPE_MUTE
        case 2:  self = .brightnessUp             // NX_KEYTYPE_BRIGHTNESS_UP
        case 3:  self = .brightnessDown           // NX_KEYTYPE_BRIGHTNESS_DOWN
        case 21: self = .keyboardBacklightUp      // NX_KEYTYPE_ILLUMINATION_UP
        case 22: self = .keyboardBacklightDown    // NX_KEYTYPE_ILLUMINATION_DOWN
        default: return nil
        }
    }
}

/// Level arithmetic for volume and brightness alike, matching the system's 16
/// notches so stepping feels native rather than approximated.
public enum LevelStepper {
    public enum Direction { case up, down }

    /// One sixteenth per press, the same increment macOS uses.
    public static let notch = 1.0 / 16.0

    public static func step(from level: Double, direction: Direction) -> Double {
        let next = direction == .up ? level + notch : level - notch
        return min(max(next, 0), 1)
    }
}
