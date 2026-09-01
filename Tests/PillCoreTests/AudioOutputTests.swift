import Foundation
@testable import PillCore

func runAudioOutputTests(_ r: TestRunner) {

    // CoreAudio reports transport as a four-char code. Verified on this machine:
    // the built-in speakers report 'bltn'.
    r.test("known CoreAudio transport codes map to their kind") { r in
        r.expectEqual(AudioTransport(fourCC: "bltn"), .builtIn, "bltn is the built-in speakers")
        r.expectEqual(AudioTransport(fourCC: "blue"), .bluetooth, "blue is Bluetooth")
        r.expectEqual(AudioTransport(fourCC: "usb "), .usb, "usb has a trailing space in the code")
        r.expectEqual(AudioTransport(fourCC: "hdmi"), .hdmi, "hdmi")
        r.expectEqual(AudioTransport(fourCC: "airp"), .airPlay, "airp is AirPlay")
    }

    r.test("an unrecognised transport code is not fatal") { r in
        r.expectEqual(AudioTransport(fourCC: "zzzz"), .unknown, "unknown codes degrade rather than crash")
    }

    r.test("the current device is identified within the device list") { r in
        let devices = [
            AudioOutputDevice(id: 72, uid: "BuiltInSpeaker", name: "MacBook Air Speakers", transport: .builtIn),
            AudioOutputDevice(id: 91, uid: "AirPods-x", name: "AirPods Pro", transport: .bluetooth),
        ]
        let state = AudioOutputState(devices: devices, currentDeviceID: 91)
        r.expectEqual(state.current?.name, "AirPods Pro", "current device resolved by id")
    }

    r.test("a current id that is no longer present resolves to nothing") { r in
        // Yanking a USB interface leaves a stale id; this must not crash or
        // report the wrong device.
        let devices = [
            AudioOutputDevice(id: 72, uid: "BuiltInSpeaker", name: "MacBook Air Speakers", transport: .builtIn)
        ]
        let state = AudioOutputState(devices: devices, currentDeviceID: 91)
        r.expect(state.current == nil, "stale current id resolves to nil")
    }

    r.test("with one device there is nothing to switch to") { r in
        // True on this machine right now: only the built-in speakers exist.
        let state = AudioOutputState(
            devices: [AudioOutputDevice(id: 72, uid: "BuiltInSpeaker", name: "MacBook Air Speakers", transport: .builtIn)],
            currentDeviceID: 72)
        r.expect(state.canSwitch == false, "a single device offers no alternative")
    }

    r.test("with two devices switching is offered") { r in
        let state = AudioOutputState(
            devices: [
                AudioOutputDevice(id: 72, uid: "BuiltInSpeaker", name: "MacBook Air Speakers", transport: .builtIn),
                AudioOutputDevice(id: 91, uid: "AirPods-x", name: "AirPods Pro", transport: .bluetooth),
            ],
            currentDeviceID: 72)
        r.expect(state.canSwitch == true, "two devices means switching is meaningful")
    }
}
