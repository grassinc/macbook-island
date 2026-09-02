import AppKit
import Foundation
import PillCore

@MainActor
final class QuickActionsStore: ObservableObject {
    @Published fileprivate(set) var isRecording = false
    @Published fileprivate(set) var isDark = QuickActionsModule.systemIsDark()
    @Published fileprivate(set) var lastError: String?
}

/// Screenshot, screen recording and appearance, one click from the panel.
///
/// Capture goes through `/usr/sbin/screencapture` rather than
/// `CGWindowListCreateImage`, for two reasons: the region selector is Apple's
/// own UI, which is the interaction people already know; and the file lands on
/// the Desktop, where the shelf's screenshot watcher picks it up as a draggable
/// tile with no extra plumbing.
@MainActor
final class QuickActionsModule: PillModule {
    static let identifier = "quickactions"

    private let store: QuickActionsStore
    private var context: ModuleContext?
    private var recorder: Process?
    private var appearanceObserver: NSObjectProtocol?

    init(store: QuickActionsStore) { self.store = store }

    func activate(context: ModuleContext) {
        self.context = context
        // Appearance can change from System Settings or on a schedule, so the
        // toggle reflects the system rather than remembering its own last click.
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.isDark = Self.systemIsDark() }
        }
    }

    func deactivate() {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
        appearanceObserver = nil
        stopRecording()
        context?.retract(id: Self.identifier)
    }

    // MARK: - Screenshot

    /// Interactive region select, saved to the Desktop so the shelf catches it.
    func captureRegion() {
        store.lastError = nil
        let destination = desktop()
            .appendingPathComponent("Screenshot \(Self.stamp()).png")
        run(["-i", destination.path]) { [weak self] status in
            // Cancelling the selection with Escape is a normal outcome, not a
            // failure, and leaves no file behind. Only say something if the tool
            // itself failed.
            guard status != 0, status != 1 else { return }
            self?.store.lastError = "Screenshot failed — Screen Recording may be off"
            Log.activity.error("screencapture exited \(status, privacy: .public)")
        }
    }

    // MARK: - Recording

    func toggleRecording() { store.isRecording ? stopRecording() : startRecording() }

    private func startRecording() {
        let destination = desktop().appendingPathComponent("Recording \(Self.stamp()).mov")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -v records video, -V caps the duration as a backstop so a forgotten
        // recording cannot fill the disk overnight.
        process.arguments = ["-v", "-V", "3600", destination.path]
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.recorder = nil
                    self.store.isRecording = false
                    self.context?.retract(id: Self.identifier)
                    Log.activity.notice("recording stopped")
                }
            }
        }
        do {
            try process.run()
        } catch {
            store.lastError = "Could not start recording"
            Log.activity.error("recording failed to start: \(error.localizedDescription, privacy: .public)")
            return
        }
        recorder = process
        store.isRecording = true
        Log.activity.notice("recording to \(destination.lastPathComponent, privacy: .public)")

        // Interruptive and non-expiring: a recording the user has forgotten
        // about is exactly the thing the pill should keep saying out loud.
        context?.publish(Activity(
            id: Self.identifier,
            kind: .screenRecording,
            title: "Recording",
            subtitle: "Click to stop",
            priority: .interruptive,
            startedAt: Date()
        ))
    }

    private func stopRecording() {
        guard let recorder, recorder.isRunning else { return }
        // screencapture finalises the movie on SIGINT. Killing it outright
        // leaves an unplayable file.
        recorder.interrupt()
    }

    // MARK: - Appearance

    static func systemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Appearance has no public write API, so this goes through System Events —
    /// the same Automation permission the media player already uses.
    func toggleDarkMode() {
        let script = """
        tell application "System Events"
            tell appearance preferences to set dark mode to not dark mode
        end tell
        """
        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let failed = error != nil
            if let error { Log.activity.error("dark mode: \(error.description, privacy: .public)") }
            await MainActor.run {
                if failed { self.store.lastError = "Appearance needs Automation permission" }
                self.store.isDark = Self.systemIsDark()
            }
        }
    }

    // MARK: - Plumbing

    private func desktop() -> URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    private func run(_ arguments: [String], completion: @escaping @MainActor @Sendable (Int32) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.terminationHandler = { finished in
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(finished.terminationStatus) } }
        }
        do { try process.run() } catch {
            Log.activity.error("screencapture failed to launch: \(error.localizedDescription, privacy: .public)")
            completion(-1)
        }
    }
}
