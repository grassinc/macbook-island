import CoreAudio
import Foundation
import PillCore

/// Observable snapshot of audio routing for the expanded panel.
@MainActor
final class AudioOutputStore: ObservableObject {
    @Published fileprivate(set) var state = AudioOutputState(devices: [], currentDeviceID: 0)
}

/// Switches system audio output, and announces changes in the pill.
///
/// Entirely public CoreAudio, so it needs no permissions at all. Both event
/// sources are property listeners — there is no polling.
@MainActor
final class AudioOutputModule: PillModule {
    static let identifier = "audio.output"

    private let store: AudioOutputStore
    private var context: ModuleContext?
    private var teardowns: [() -> Void] = []

    init(store: AudioOutputStore) {
        self.store = store
    }

    func activate(context: ModuleContext) {
        self.context = context
        refresh(announce: false)

        // Devices appearing or disappearing (AirPods connecting, USB unplugged).
        teardowns.append(CoreAudioBridge.addSystemListener(kAudioHardwarePropertyDevices, queue: .main) { [weak self] in
            DispatchQueue.main.async { self?.refresh(announce: true) }
        })
        // The default output being changed, by us or by anything else.
        teardowns.append(CoreAudioBridge.addSystemListener(kAudioHardwarePropertyDefaultOutputDevice, queue: .main) { [weak self] in
            DispatchQueue.main.async { self?.refresh(announce: true) }
        })
    }

    func deactivate() {
        for teardown in teardowns { teardown() }
        teardowns.removeAll()
        context?.retract(id: Self.identifier)
    }

    /// Switch output. Safe to call with a device that has since vanished —
    /// CoreAudio simply reports failure and the next refresh corrects the state.
    func select(_ device: AudioOutputDevice) {
        CoreAudioBridge.setDefaultOutputDevice(device.id)
    }

    private func refresh(announce: Bool) {
        let updated = AudioOutputState(devices: CoreAudioBridge.outputDevices(),
                                       currentDeviceID: CoreAudioBridge.defaultOutputDeviceID())
        let previousID = store.state.current?.id
        store.state = updated

        // Only announce a genuine route change, not every device-list churn.
        guard announce, let current = updated.current, current.id != previousID else { return }
        let now = Date()
        context?.publish(Activity(
            id: Self.identifier,
            kind: .audioOutput,
            title: current.name,
            subtitle: "Output",
            priority: .transient,
            startedAt: now,
            expiresAt: now.addingTimeInterval(2.2)
        ))
    }
}
