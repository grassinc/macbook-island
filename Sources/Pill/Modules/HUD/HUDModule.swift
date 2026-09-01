import CoreAudio
import Foundation
import PillCore

@MainActor
final class HUDStore: ObservableObject {
    /// True when the media-key tap is live, meaning Apple's overlay is actually
    /// being replaced rather than merely duplicated.
    @Published fileprivate(set) var isReplacingSystemHUD = false
}

/// Volume HUD.
///
/// Two independent paths feed it:
///  1. The media-key tap (needs Accessibility). Consuming the key stops the
///     system OSD from ever being triggered, which is the only way to replace
///     it — SIP blocks unloading OSDUIHelper.
///  2. A CoreAudio listener (no permission), so volume changed from Control
///     Centre or another app still shows in the pill.
///
/// Without Accessibility only path 2 runs and both HUDs appear. That is stated
/// plainly in onboarding rather than failing silently.
@MainActor
final class HUDModule: PillModule {
    static let identifier = "hud"

    private let store: HUDStore
    private let keyTap = MediaKeyTap()
    private let accessibility = AccessibilityMonitor()
    private var context: ModuleContext?

    private var device: AudioObjectID = 0
    /// Last values actually shown, so a redundant notification is dropped.
    private var lastPublished: (level: Double, muted: Bool)?
    private var volumeTeardown: (() -> Void)?
    private var defaultDeviceTeardown: (() -> Void)?

    /// Long enough to read, short enough not to linger over the menu bar.
    private let visibleFor: TimeInterval = 1.6

    init(store: HUDStore) {
        self.store = store
    }

    func activate(context: ModuleContext) {
        self.context = context
        bindToDefaultDevice()

        // Volume lives on the device, so re-bind whenever the default changes.
        defaultDeviceTeardown = CoreAudioBridge.addSystemListener(
            kAudioHardwarePropertyDefaultOutputDevice, queue: .main
        ) { [weak self] in
            DispatchQueue.main.async { self?.bindToDefaultDevice() }
        }

        keyTap.onKey = { [weak self] key in self?.handle(key) ?? false }
        store.isReplacingSystemHUD = keyTap.start()

        // Start the tap the moment the user flips the switch in System Settings,
        // with no relaunch and no polling.
        accessibility.onTrustChanged = { [weak self] trusted in
            guard let self else { return }
            Log.permissions.notice("accessibility changed to \(trusted, privacy: .public)")
            if trusted {
                self.store.isReplacingSystemHUD = self.keyTap.start()
            } else {
                self.keyTap.stop()
                self.store.isReplacingSystemHUD = false
            }
        }
        accessibility.start()
        Log.permissions.notice("accessibility=\(MediaKeyTap.isTrusted, privacy: .public) keyTap=\(self.store.isReplacingSystemHUD, privacy: .public)")
    }

    func deactivate() {
        accessibility.stop()
        keyTap.stop()
        volumeTeardown?()
        volumeTeardown = nil
        defaultDeviceTeardown?()
        defaultDeviceTeardown = nil
        context?.retract(id: Self.identifier)
    }

    /// Called after the user grants Accessibility, so the tap starts without a relaunch.
    @discardableResult
    func retryKeyTap() -> Bool {
        let started = keyTap.start()
        store.isReplacingSystemHUD = started
        return started
    }

    // MARK: - Key handling

    /// Returns true only for keys actually handled. Returning true for a key we
    /// do not implement would consume it and silently break that hardware key,
    /// so brightness and keyboard backlight deliberately pass through until
    /// they are implemented.
    private func handle(_ key: MediaKey) -> Bool {
        switch key {
        case .volumeUp:   adjustVolume(.up);   return true
        case .volumeDown: adjustVolume(.down); return true
        case .mute:       toggleMute();        return true
        case .brightnessUp, .brightnessDown, .keyboardBacklightUp, .keyboardBacklightDown:
            return false
        }
    }

    private func adjustVolume(_ direction: VolumeStepper.Direction) {
        guard device != 0, let level = VolumeController.volume(of: device) else { return }

        // Nudging volume while muted should unmute, which is what the system does.
        if VolumeController.isMuted(device) {
            VolumeController.setMuted(false, on: device)
        }
        let next = VolumeStepper.step(from: level, direction: direction)
        VolumeController.setVolume(next, on: device)
        publish(level: next, muted: false)
    }

    private func toggleMute() {
        guard device != 0 else { return }
        let muted = !VolumeController.isMuted(device)
        VolumeController.setMuted(muted, on: device)
        publish(level: VolumeController.volume(of: device) ?? 0, muted: muted)
    }

    // MARK: - Device binding

    private func bindToDefaultDevice() {
        volumeTeardown?()
        volumeTeardown = nil

        device = VolumeController.defaultOutputDevice()
        guard device != 0 else { return }

        volumeTeardown = VolumeController.observe(device: device, queue: .main) { [weak self] in
            DispatchQueue.main.async { self?.publishCurrent() }
        }
    }

    /// Reflects a change made elsewhere (Control Centre, another app).
    ///
    /// CoreAudio notifies the volume and mute listeners for a single volume
    /// change, so this arrives twice per keypress. Publishing both times is
    /// harmless for the pill (same activity id) but doubles the OSD-dismissal
    /// work, so identical values are dropped.
    private func publishCurrent() {
        guard device != 0, let level = VolumeController.volume(of: device) else { return }
        let muted = VolumeController.isMuted(device)
        if let last = lastPublished, last.level == level, last.muted == muted { return }
        publish(level: level, muted: muted)

        // Without the tap the key reached the system, so Apple's OSD is on its
        // way. Best-effort dismissal only: OSDUIHelper is launched on demand and
        // draws almost immediately, so this can still flash. Retried briefly
        // because the helper may not have appeared yet on the first attempt.
        guard !keyTap.isRunning else { return }
        suppressSystemOSD()
    }

    private func suppressSystemOSD() {
        OSDSuppressor.dismiss()
        for delay in [0.05, 0.12, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                OSDSuppressor.dismiss()
            }
        }
    }

    private func publish(level: Double, muted: Bool) {
        let now = Date()
        context?.publish(Activity(
            id: Self.identifier,
            kind: .hud,
            title: muted ? "Muted" : "Volume",
            priority: .interruptive,
            startedAt: now,
            expiresAt: now.addingTimeInterval(visibleFor),
            progress: muted ? 0 : level
        ))
        lastPublished = (level, muted)
        Log.hud.notice("volume level=\(level, privacy: .public) muted=\(muted, privacy: .public)")
    }
}
