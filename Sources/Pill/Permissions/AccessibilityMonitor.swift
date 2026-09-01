import AppKit
import ApplicationServices
import Foundation

/// Notices when Accessibility is granted or revoked, without polling.
///
/// macOS posts `com.apple.accessibility.api` on the distributed notification
/// centre whenever the trust list changes. Watching it means the media-key tap
/// starts the instant the user flips the switch, instead of the user having to
/// relaunch or hover the pill to trigger a re-check.
@MainActor
final class AccessibilityMonitor {

    var onTrustChanged: ((Bool) -> Void)?

    private var observer: NSObjectProtocol?
    private var lastKnown = AXIsProcessTrusted()

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification lands marginally before AXIsProcessTrusted flips,
            // so re-read on the next turn rather than immediately.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { self?.reportIfChanged() }
            }
        }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    /// Re-reads trust and reports only on an actual change.
    func reportIfChanged() {
        let trusted = AXIsProcessTrusted()
        guard trusted != lastKnown else { return }
        lastKnown = trusted
        onTrustChanged?(trusted)
    }

    /// Opens System Settings directly at the Accessibility list, so the user is
    /// not left hunting through panes.
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
