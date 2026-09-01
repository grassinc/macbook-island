import AppKit
import CoreAudio
import Foundation
import PillCore

/// Watches which processes are producing audio.
///
/// Uses `kAudioHardwarePropertyProcessObjectList` (macOS 14.4+) plus per-process
/// listeners. Both are public CoreAudio and need no permission, and both are
/// notification-driven — nothing here polls.
///
/// Per-process listeners are re-registered whenever the process list changes,
/// because a newly launched app arrives as a brand new audio object.
///
/// The transition is watched on `kAudioProcessPropertyIsRunning`, not on
/// `kAudioProcessPropertyIsRunningOutput`, even though the latter is the value
/// actually read. Measured on macOS 26.6: a listener on `IsRunningOutput`
/// attaches without error and then never fires — the property flips false to
/// true with no notification. `IsRunning` fires reliably on both edges. That is
/// why quitting and reopening Spotify used to leave the pill blank: the new
/// process object was created before playback began, its listener attached to
/// a property that never notifies, and nothing noticed until some unrelated app
/// changed the process list and forced a rescan. `IsRunning` is also true for
/// input-only work, so it is the trigger and `IsRunningOutput` remains the test.
@MainActor
final class AudioProcessMonitor {

    var onChange: (([AudioSource]) -> Void)?

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listRemoval: (() -> Void)?
    private var processRemovals: [() -> Void] = []
    /// When each pid last STARTED producing audio. CoreAudio reports only the
    /// current boolean, so the transition has to be observed and remembered —
    /// it is what distinguishes a track just started from a browser stream that
    /// has been open since this morning.
    private var startedOutputting: [pid_t: Date] = [:]

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    var isSupported: Bool {
        var a = address(kAudioHardwarePropertyProcessObjectList)
        return AudioObjectHasProperty(system, &a)
    }

    func start() {
        guard isSupported else {
            Log.activity.notice("audio process list unavailable on this system")
            return
        }
        listRemoval = addListener(on: system, selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.rebindProcesses()
        }
        rebindProcesses()
    }

    func stop() {
        listRemoval?()
        listRemoval = nil
        clearProcessListeners()
    }

    // MARK: - Listener plumbing

    private func addListener(on object: AudioObjectID,
                             selector: AudioObjectPropertySelector,
                             handler: @escaping () -> Void) -> (() -> Void)? {
        var a = address(selector)
        guard AudioObjectHasProperty(object, &a) else { return nil }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { handler() } }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &a, DispatchQueue.main, block) == noErr else {
            return nil
        }
        return { [weak self] in
            guard let self else { return }
            var a = self.address(selector)
            AudioObjectRemovePropertyListenerBlock(object, &a, DispatchQueue.main, block)
        }
    }

    private func clearProcessListeners() {
        for removal in processRemovals { removal() }
        processRemovals.removeAll()
    }

    /// The set of audio processes changed, so re-attach per-process listeners.
    private func rebindProcesses() {
        clearProcessListeners()
        for object in processObjects() {
            // Both are attached: `IsRunning` is the one that actually notifies
            // here, and keeping `IsRunningOutput` costs a listener per process
            // and means a system where only it works is still covered.
            for selector in [kAudioProcessPropertyIsRunning,
                             kAudioProcessPropertyIsRunningOutput] {
                if let removal = addListener(on: object, selector: selector,
                                             handler: { [weak self] in self?.emit() }) {
                    processRemovals.append(removal)
                }
            }
        }
        emit()
    }

    private func emit() {
        onChange?(currentSources())
    }

    // MARK: - Reading

    private func processObjects() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectHasProperty(system, &a),
              AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    func currentSources() -> [AudioSource] {
        let now = Date()
        var live: Set<pid_t> = []

        let sources: [AudioSource] = processObjects().compactMap { object in
            guard let pid = pid(of: object) else { return nil }
            live.insert(pid)

            let bundleID = string(object, kAudioProcessPropertyBundleID) ?? ""
            let running = bool(object, kAudioProcessPropertyIsRunningOutput) ?? false

            if running {
                // Record the moment it started; leave it alone while it continues.
                if startedOutputting[pid] == nil { startedOutputting[pid] = now }
            } else {
                startedOutputting[pid] = nil
            }

            let name = NSRunningApplication(processIdentifier: pid)?.localizedName
                ?? bundleID.components(separatedBy: ".").last
                ?? bundleID
            return AudioSource(pid: pid, bundleID: bundleID, name: name,
                               isOutputting: running,
                               startedOutputtingAt: startedOutputting[pid] ?? now)
        }

        // Forget processes that have gone away, so the map cannot grow forever.
        startedOutputting = startedOutputting.filter { live.contains($0.key) }
        return sources
    }

    private func pid(of object: AudioObjectID) -> pid_t? {
        var a = address(kAudioProcessPropertyPID)
        guard AudioObjectHasProperty(object, &a) else { return nil }
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = address(selector)
        guard AudioObjectHasProperty(object, &a) else { return nil }
        var out: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &out) == noErr, let out else { return nil }
        return out.takeRetainedValue() as String
    }

    private func bool(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool? {
        var a = address(selector)
        guard AudioObjectHasProperty(object, &a) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
}
