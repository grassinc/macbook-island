import AppKit
import Foundation

/// Fallback suppression of Apple's on-screen display.
///
/// The clean path is the event tap: consume the volume key and the OSD is never
/// triggered at all. This exists for the degraded case where Accessibility has
/// not been granted, and it is genuinely second-best — `OSDUIHelper` is launched
/// on demand and draws immediately, so killing it after the fact can leave a
/// brief flash. It is not a substitute for the tap.
///
/// SIP blocks the tidier options: `launchctl bootout com.apple.OSDUIHelper`
/// fails with error 150.
enum OSDSuppressor {

    private static let bundleID = "com.apple.OSDUIHelper"

    /// Whether the helper is currently alive (it is launched on demand).
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Terminates the helper so its window disappears. launchd relaunches it on
    /// the next system OSD request, so this is not a persistent system change —
    /// nothing to undo when Pill quits.
    @discardableResult
    static func dismiss() -> Bool {
        let helpers = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !helpers.isEmpty else { return false }
        for helper in helpers { helper.forceTerminate() }
        return true
    }
}
