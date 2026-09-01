import AppKit
import Foundation
import PillCore

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published fileprivate(set) var source: AudioSource?
    /// "Artist — Title" when the player is scriptable, otherwise nil.
    @Published fileprivate(set) var track: String?
    var isPlaying: Bool { source != nil }
}

/// Shows what is currently making sound (brief feature 2, by another route).
///
/// MediaRemote is not used. Its now-playing dictionary comes back nil for a
/// third-party caller on this machine, and Apple gates it on a code identity no
/// third party can obtain. The public CoreAudio process API answers a slightly
/// narrower question — which app is producing audio, not which track is queued —
/// but it needs no permission and cannot be withdrawn in a point release.
///
/// Track titles are layered on top for the two players that expose them through
/// AppleScript. When they are unavailable the app name alone is still useful and
/// still correct.
@MainActor
final class NowPlayingModule: PillModule {
    static let identifier = "nowplaying"

    private let store: NowPlayingStore
    private let monitor = AudioProcessMonitor()
    private var context: ModuleContext?

    /// Players whose current track can be read without private API.
    private static let scriptablePlayers: [String: String] = [
        "com.apple.Music": "Music",
        "com.spotify.client": "Spotify",
    ]

    init(store: NowPlayingStore) { self.store = store }

    func activate(context: ModuleContext) {
        self.context = context
        monitor.onChange = { [weak self] sources in self?.update(sources) }
        monitor.start()
    }

    func deactivate() {
        monitor.stop()
        context?.retract(id: Self.identifier)
    }

    private func update(_ sources: [AudioSource]) {
        let primary = NowPlayingSelector.primary(from: sources)

        // Nothing changed: avoid republishing on every CoreAudio notification.
        guard primary?.pid != store.source?.pid else { return }
        store.source = primary

        guard let primary else {
            store.track = nil
            context?.retract(id: Self.identifier)
            Log.activity.notice("audio stopped")
            return
        }

        Log.activity.notice("audio from \(primary.name, privacy: .public) [\(primary.bundleID, privacy: .public)]")
        publish(app: primary.name, track: nil)
        fetchTrack(for: primary)
    }

    private func publish(app: String, track: String?) {
        // Ambient: knowing what is playing is not worth interrupting for, and it
        // persists rather than expiring, so the pill can fall back to it when
        // louder activities finish.
        context?.publish(Activity(
            id: Self.identifier,
            kind: .nowPlaying,
            title: track ?? app,
            subtitle: track == nil ? "Playing" : app,
            priority: .ambient,
            startedAt: Date()
        ))
    }

    /// AppleScript is blocking and prompts for Automation consent the first
    /// time, so it runs off the main thread and failure is silent — the app name
    /// is already on screen and remains correct.
    private func fetchTrack(for source: AudioSource) {
        guard let player = Self.scriptablePlayers[source.bundleID] else { return }
        let script = """
        tell application "\(player)"
            if player state is playing then
                return (name of current track) & " — " & (artist of current track)
            end if
        end tell
        """
        Task.detached(priority: .utility) {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            guard let text = result?.stringValue, !text.isEmpty else { return }
            await MainActor.run {
                guard self.store.source?.pid == source.pid else { return }
                self.store.track = text
                self.publish(app: source.name, track: text)
            }
        }
    }
}
