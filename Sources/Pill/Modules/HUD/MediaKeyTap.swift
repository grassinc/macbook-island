import AppKit
import ApplicationServices
@preconcurrency import CoreGraphics
import PillCore

/// Intercepts the hardware media keys.
///
/// This is the only way to genuinely *replace* Apple's overlay. SIP prevents
/// unloading `com.apple.OSDUIHelper` (`launchctl bootout` fails with error 150),
/// so the OSD cannot be disabled — it can only be prevented from being
/// triggered, by consuming the key event before the system handles it.
///
/// That requires Accessibility. Without it the tap is simply not created and the
/// HUD degrades to mirroring volume alongside Apple's own overlay.
@MainActor
final class MediaKeyTap {

    /// Return `true` from this to consume the key; `false` passes it through.
    var onKey: ((MediaKey) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true]   // kAXTrustedCheckOptionPrompt
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted else { return false }

        // NSEventTypeSystemDefined is 14; the media keys arrive as its
        // aux-control subtype.
        let mask = CGEventMask(1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // Attached to the main run loop, so the callback runs on the main thread.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that takes too long; re-arm it rather than
        // silently losing the keys for the rest of the session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {          // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = Int32((data1 & 0xFFFF_0000) >> 16)
        let keyIsDown = ((data1 & 0x0000_FF00) >> 8) == 0x0A

        // Only keys we actually handle are consumed. Play/pause and track skip
        // map to nil and pass straight through, so media controls keep working.
        guard keyIsDown, let key = MediaKey(keyCode: keyCode) else {
            return Unmanaged.passUnretained(event)
        }
        guard onKey?(key) == true else { return Unmanaged.passUnretained(event) }
        return nil   // consumed: the system never sees it, so no OSD appears
    }
}

private func mediaKeyTapCallback(proxy: CGEventTapProxy,
                                 type: CGEventType,
                                 event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    // The source is attached to the main run loop, so this is the main thread.
    return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
}
