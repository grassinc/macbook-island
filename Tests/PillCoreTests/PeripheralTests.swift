import Foundation
import PillCore

func runPeripheralTests(_ runner: TestRunner) {
    runner.test("BluetoothDeviceKind") { t in
        // Read off this machine's own paired AirPods.
        t.expectEqual(BluetoothDeviceKind.from(classOfDevice: 0x240418), .headphones,
                      "0x240418 is the AirPods on this Mac")
        t.expectEqual(BluetoothDeviceKind.from(classOfDevice: 0x200404), .headphones,
                      "major 4 minor 1 is a headset")
        t.expectEqual(BluetoothDeviceKind.from(classOfDevice: 0x240414), .speaker,
                      "major 4 minor 5 is a loudspeaker")
        t.expectEqual(BluetoothDeviceKind.from(classOfDevice: 0x000580), .mouse,
                      "major 5 with the pointing bit is a mouse")
        t.expectEqual(BluetoothDeviceKind.from(classOfDevice: 0x000540), .keyboard,
                      "major 5 with the keyboard bit")
        t.expectEqual(BluetoothDeviceKind.from(classOfDevice: 0x000200), .phone,
                      "major 2 is a phone")
        t.expectEqual(BluetoothDeviceKind.from(classOfDevice: 0x000000), .other,
                      "an unreported class is not guessed at")
    }

    runner.test("ChargeAdvice") { t in
        t.expect(ChargeAdvice.shouldSuggestUnplug(percent: 80, isCharging: true, alreadySuggested: false),
                 "nudges exactly at the ceiling")
        t.expect(ChargeAdvice.shouldSuggestUnplug(percent: 97, isCharging: true, alreadySuggested: false),
                 "still nudges above it, in case 80 was passed unobserved")
        t.expect(!ChargeAdvice.shouldSuggestUnplug(percent: 79, isCharging: true, alreadySuggested: false),
                 "silent below the ceiling")
        t.expect(!ChargeAdvice.shouldSuggestUnplug(percent: 90, isCharging: false, alreadySuggested: false),
                 "on battery there is nothing to unplug")
        // The nudge is once per charge session; repeating it is how an
        // indicator becomes furniture.
        t.expect(!ChargeAdvice.shouldSuggestUnplug(percent: 90, isCharging: true, alreadySuggested: true),
                 "said once, not on every battery notification")
        t.expect(ChargeAdvice.shouldResetAdvice(isCharging: false), "unplugging re-arms it")
        t.expect(!ChargeAdvice.shouldResetAdvice(isCharging: true), "staying plugged in does not")
    }
}
