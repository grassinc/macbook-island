import Foundation

/// How an output device is attached. CoreAudio reports this as a four-character
/// code; the built-in speakers on this machine report `bltn`.
public enum AudioTransport: Sendable, Equatable {
    case builtIn, bluetooth, usb, hdmi, displayPort, airPlay, virtual, unknown

    public init(fourCC: String) {
        switch fourCC {
        case "bltn": self = .builtIn
        case "blue": self = .bluetooth
        case "usb ": self = .usb          // CoreAudio pads this code to four chars
        case "hdmi": self = .hdmi
        case "dprt": self = .displayPort
        case "airp": self = .airPlay
        case "virt": self = .virtual
        default:     self = .unknown      // never fatal; unknown hardware still lists
        }
    }
}

/// An output device, modelled without importing CoreAudio so it stays testable.
/// `id` is an `AudioObjectID`.
public struct AudioOutputDevice: Equatable, Identifiable, Sendable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let transport: AudioTransport

    public init(id: UInt32, uid: String, name: String, transport: AudioTransport) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
    }
}

/// A snapshot of output routing.
public struct AudioOutputState: Equatable, Sendable {
    public let devices: [AudioOutputDevice]
    public let currentDeviceID: UInt32

    public init(devices: [AudioOutputDevice], currentDeviceID: UInt32) {
        self.devices = devices
        self.currentDeviceID = currentDeviceID
    }

    /// Resolves by id rather than trusting an index — unplugging an interface
    /// leaves a stale id, which must read as "unknown" instead of the wrong device.
    public var current: AudioOutputDevice? {
        devices.first { $0.id == currentDeviceID }
    }

    /// Whether offering a switch is meaningful at all.
    public var canSwitch: Bool { devices.count > 1 }
}
