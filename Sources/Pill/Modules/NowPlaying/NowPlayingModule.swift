import AppKit
import Foundation
import PillCore

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published fileprivate(set) var source: AudioSource?
    /// "Artist — Title" when the player is scriptable, otherwise nil.
    @Published fileprivate(set) var track: String?
    /// Full transport state, available only for players we can script.
    @Published fileprivate(set) var playback: MediaPlayback?
    var isPlaying: Bool { source != nil }
    /// Whether the expanded panel should offer real controls.
    var hasTransport: Bool { playback != nil }
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
    private var positionTicker: DispatchSourceTimer?
    private var panelIsOpen = false
    private var lastFetchAt: Date?
    /// AppleScript round-trips are expensive — polling Spotify once a second
    /// cost about 2.3% CPU with the panel open. The track only actually changes
    /// every few minutes, so metadata is re-read every few seconds and the
    /// position is advanced locally in between.
    private let fetchInterval: TimeInterval = 3

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
        stopTicker()
        monitor.stop()
        context?.retract(id: Self.identifier)
    }

    // MARK: - Transport

    func playPause() { transport(SpotifyController.playPause) }
    func next()      { transport(SpotifyController.next) }
    func previous()  { transport(SpotifyController.previous) }

    /// AppleScript blocks, so transport runs off the main thread and the state
    /// is re-read once the player has had a moment to act on it.
    private func transport(_ action: @escaping @Sendable () -> Void) {
        Task.detached(priority: .userInitiated) {
            action()
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run { self.refreshPlayback() }
        }
    }

    /// The panel opening is what justifies polling the player at all: a scrubber
    /// nobody can see does not need to move. Told by the window controller.
    func setPanelOpen(_ open: Bool) {
        panelIsOpen = open
        open ? refreshPlayback() : stopTicker()
    }

    /// Runs only while the panel is open and something is actually playing.
    ///
    /// This used to be started right after kicking off a refresh, and guarded on
    /// `store.playback` — which the refresh had not written yet, because it is
    /// asynchronous. The guard therefore read the *previous* track's state, so
    /// on the first open after a track started the ticker never began and the
    /// scrubber sat frozen. It is now started from the refresh's completion,
    /// where the value it depends on actually exists.
    private func startTickerIfNeeded() {
        guard panelIsOpen, store.playback?.isPlaying == true else { stopTicker(); return }
        guard positionTicker == nil else { return }
        let ticker = DispatchSource.makeTimerSource(queue: .main)
        ticker.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(200))
        ticker.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker.resume()
        positionTicker = ticker
    }

    private func stopTicker() {
        positionTicker?.cancel()
        positionTicker = nil
    }

    /// Advances the scrubber cheaply, re-reading from Spotify only occasionally.
    private func tick() {
        let now = Date()
        if let last = lastFetchAt, now.timeIntervalSince(last) < fetchInterval,
           let current = store.playback, current.isPlaying {
            store.playback = MediaPlayback(
                title: current.title, artist: current.artist, album: current.album,
                artworkURL: current.artworkURL,
                durationMilliseconds: current.durationMilliseconds,
                positionMilliseconds: min(current.positionMilliseconds + 1000,
                                          current.durationMilliseconds),
                isPlaying: true)
            return
        }
        refreshPlayback()
    }

    /// Reads the player, retrying a few times if it has nothing to say yet.
    ///
    /// A relaunched Spotify starts answering Apple events before it has a track
    /// loaded, so the read triggered by CoreAudio noticing its output lands too
    /// early and comes back empty. That was the only read taken: nothing retried
    /// it, and nothing logged it, so after quitting and reopening Spotify the
    /// pill sat on the plain app-name row with no player until the process id
    /// changed again.
    private func refreshPlayback(retriesLeft: Int = 4) {
        lastFetchAt = Date()
        guard store.source?.bundleID == SpotifyController.bundleID else {
            store.playback = nil
            stopTicker()
            return
        }
        let expected = store.source?.pid
        Task.detached(priority: .utility) {
            let playback = SpotifyController.playback()
            await MainActor.run {
                // Another app may have taken the output while this was in flight.
                guard self.store.source?.pid == expected else { return }

                guard let playback else {
                    Log.activity.notice("spotify has no track yet, retries left \(retriesLeft, privacy: .public)")
                    guard retriesLeft > 0 else {
                        self.store.playback = nil
                        self.stopTicker()
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        MainActor.assumeIsolated { self.refreshPlayback(retriesLeft: retriesLeft - 1) }
                    }
                    return
                }

                self.store.playback = playback
                Log.activity.notice("playback \(playback.title, privacy: .public) pos=\(playback.positionText, privacy: .public)/\(playback.durationText, privacy: .public) playing=\(playback.isPlaying, privacy: .public) art=\(playback.artworkURL != nil, privacy: .public)")
                self.store.track = "\(playback.title) — \(playback.artist)"
                // A paused track is not an activity. Holding the collapsed pill
                // while nothing plays is the same mistake as latching on a
                // silent browser.
                if playback.isPlaying {
                    self.publish(app: self.store.source?.name ?? "Spotify",
                                 track: self.store.track, verified: true)
                } else {
                    self.context?.retract(id: Self.identifier)
                }
                self.startTickerIfNeeded()
            }
        }
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
        publish(app: primary.name, track: nil,
                verified: Self.scriptablePlayers[primary.bundleID] != nil)

        if primary.bundleID == SpotifyController.bundleID {
            refreshPlayback()
        } else {
            store.playback = nil
            fetchTrack(for: primary)
        }
    }

    /// Ambient: knowing what is playing is not worth interrupting for.
    ///
    /// `verified` decides whether it also *stays*. CoreAudio can say that a
    /// process holds a running output unit; it cannot say whether any sound is
    /// coming out of it. A browser keeps that unit open for as long as a tab
    /// that once played audio is alive — measured here, Zen held it open
    /// indefinitely — so treating that as "now playing" would nail the collapsed
    /// pill to "Zen" forever and the resting line would never be seen again.
    /// An unverified source therefore announces itself and steps aside; only a
    /// player that reports its own transport state earns the pill until it stops.
    private func publish(app: String, track: String?, verified: Bool) {
        let now = Date()
        context?.publish(Activity(
            id: Self.identifier,
            kind: .nowPlaying,
            title: track ?? app,
            subtitle: track == nil ? "Playing" : app,
            priority: .ambient,
            startedAt: now,
            expiresAt: verified ? nil : now.addingTimeInterval(5)
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
                self.publish(app: source.name, track: text, verified: true)
            }
        }
    }
}
