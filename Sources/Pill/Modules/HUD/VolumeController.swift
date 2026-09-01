import CoreAudio
import Foundation
import PillCore

/// Reads and writes the system output volume.
///
/// Devices differ in how they expose volume: the built-in speakers on this
/// machine publish `kAudioDevicePropertyVolumeScalar` on the main element and
/// no per-channel properties at all, while some interfaces do the opposite.
/// Both paths are handled, main element first.
enum VolumeController {

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    static func defaultOutputDevice() -> AudioObjectID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr else { return 0 }
        return id
    }

    /// Elements to try, in order: main, then the first two channels.
    private static func volumeElements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        [kAudioObjectPropertyElementMain, 1, 2]
    }

    static func volume(of device: AudioObjectID) -> Double? {
        for element in volumeElements(device) {
            var addr = address(kAudioDevicePropertyVolumeScalar, element)
            guard AudioObjectHasProperty(device, &addr) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
                return Double(value)
            }
        }
        return nil
    }

    @discardableResult
    static func setVolume(_ level: Double, on device: AudioObjectID) -> Bool {
        var value = Float32(min(max(level, 0), 1))
        var settable: DarwinBoolean = false
        for element in volumeElements(device) {
            var addr = address(kAudioDevicePropertyVolumeScalar, element)
            guard AudioObjectHasProperty(device, &addr),
                  AudioObjectIsPropertySettable(device, &addr, &settable) == noErr,
                  settable.boolValue else { continue }
            if AudioObjectSetPropertyData(device, &addr, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size), &value) == noErr {
                return true
            }
        }
        return false
    }

    static func isMuted(_ device: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool, on device: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &addr, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// Observes volume and mute on a specific device. Returns a teardown closure.
    static func observe(device: AudioObjectID,
                        queue: DispatchQueue,
                        handler: @escaping () -> Void) -> () -> Void {
        var teardowns: [() -> Void] = []
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in volumeElements(device) {
                var addr = address(selector, element)
                guard AudioObjectHasProperty(device, &addr) else { continue }
                let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
                guard AudioObjectAddPropertyListenerBlock(device, &addr, queue, block) == noErr else { continue }
                teardowns.append {
                    var addr = address(selector, element)
                    AudioObjectRemovePropertyListenerBlock(device, &addr, queue, block)
                }
            }
        }
        return { for teardown in teardowns { teardown() } }
    }
}
