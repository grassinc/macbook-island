import AppKit
import Foundation
import PillCore

@MainActor
final class PrivacyStore: ObservableObject {
    @Published fileprivate(set) var mode: PrivacyMode = .normal
    /// True when a known conferencing app is running, used to suggest the mode
    /// rather than to silently enable it.
    @Published fileprivate(set) var conferencingAppDetected = false

    var isScreenSharing: Bool { mode == .screenShare }
}

/// Screen-share mode (brief feature 14).
///
/// The honest position on detection: macOS has no public API that reliably says
/// "your screen is being shared right now". ScreenCaptureKit would need Screen
/// Recording permission and still reports what *can* be captured, not what is.
/// So the switch is manual and explicit — the user knows they are about to
/// present, and a toggle they control beats a heuristic that fails silently in
/// exactly the moment it matters.
///
/// Detecting a running conferencing app is used only to surface the toggle more
/// prominently, never to flip it. Auto-enabling would be wrong when someone
/// simply has Zoom open all day; auto-disabling would be far worse.
@MainActor
final class PrivacyModule: PillModule {
    static let identifier = "privacy"

    private let store: PrivacyStore
    private var observer: NSObjectProtocol?

    private static let conferencingBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams", "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",   // Meet PWA
        "com.apple.ScreenSharing",
        "com.tinyspeck.slackmacgap",
    ]

    init(store: PrivacyStore) { self.store = store }

    func activate(context: ModuleContext) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDetection() }
        }
        refreshDetection()
    }

    func deactivate() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    /// Set explicitly, for network profiles. `toggle()` cannot express "on".
    func setScreenShare(_ on: Bool) {
        guard store.isScreenSharing != on else { return }
        store.mode = on ? .screenShare : .normal
        Log.activity.notice("screen-share mode = \(on, privacy: .public) (profile)")
    }

    func toggle() {
        store.mode = store.isScreenSharing ? .normal : .screenShare
        Log.activity.notice("screen-share mode = \(self.store.isScreenSharing, privacy: .public)")
    }

    private func refreshDetection() {
        let running = NSWorkspace.shared.runningApplications.contains {
            guard let id = $0.bundleIdentifier else { return false }
            return Self.conferencingBundleIDs.contains(id)
        }
        store.conferencingAppDetected = running
    }
}
