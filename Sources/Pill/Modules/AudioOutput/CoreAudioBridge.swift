import CoreAudio
import Foundation
import PillCore

/// Thin, blocking wrappers over the CoreAudio property API.
///
/// Kept separate from the module so the module's logic stays readable and the
/// unsafe pointer work lives in one auditable place.
enum CoreAudioBridge {

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// CoreAudio hands back a +1 retained CFString for these properties, so the
    /// value must be consumed with `takeRetainedValue` or it leaks.
    private static func stringProperty(_ id: AudioObjectID,
                                       _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func fourCCProperty(_ id: AudioObjectID,
                                       _ selector: AudioObjectPropertySelector) -> String {
        var addr = address(selector)
        var raw: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &raw) == noErr else { return "" }
        let bytes = [UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff),
                     UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    /// Output channel count. Zero means it is an input-only device, which is how
    /// microphones are filtered out of the switcher.
    private static func outputChannelCount(_ id: AudioObjectID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buffer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func outputDevices() -> [AudioOutputDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard outputChannelCount(id) > 0 else { return nil }
            return AudioOutputDevice(
                id: UInt32(id),
                uid: stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "unknown-\(id)",
                name: stringProperty(id, kAudioObjectPropertyName) ?? "Unknown Device",
                transport: AudioTransport(fourCC: fourCCProperty(id, kAudioDevicePropertyTransportType))
            )
        }
    }

    static func defaultOutputDeviceID() -> UInt32 {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr else { return 0 }
        return UInt32(id)
    }

    @discardableResult
    static func setDefaultOutputDevice(_ deviceID: UInt32) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(deviceID)
        let status = AudioObjectSetPropertyData(system, &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &id)
        return status == noErr
    }

    /// Registers a listener and returns a closure that removes it. CoreAudio
    /// calls the block; there is no polling anywhere in this path.
    static func addSystemListener(_ selector: AudioObjectPropertySelector,
                                  queue: DispatchQueue,
                                  handler: @escaping () -> Void) -> () -> Void {
        var addr = address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(system, &addr, queue, block)
        return {
            var addr = address(selector)
            AudioObjectRemovePropertyListenerBlock(system, &addr, queue, block)
        }
    }
}
