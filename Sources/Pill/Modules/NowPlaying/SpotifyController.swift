import AppKit
import Foundation
import PillCore

/// Talks to Spotify over AppleScript.
///
/// Every call is blocking and prompts for Automation consent the first time, so
/// callers run these off the main thread. Nothing here launches Spotify: each
/// entry point checks that it is already running, because `tell application` on
/// a stopped app would start it — surprising the user with a launch they never
/// asked for.
enum SpotifyController {

    static let bundleID = "com.spotify.client"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: - Reading

    /// Position is rounded to whole milliseconds *inside* AppleScript. Coercing
    /// a real to text would format it with the user's decimal separator — this
    /// machine returns "161,876998901367" — and an integer sidesteps that.
    private static let readScript = """
    tell application "Spotify"
        if player state is stopped then return "stopped"
        set t to current track
        return (name of t) & "\\t" & (artist of t) & "\\t" & (album of t) & "\\t" ¬
            & (artwork url of t) & "\\t" & (duration of t) & "\\t" ¬
            & (round ((player position) * 1000)) & "\\t" & (player state as text)
    end tell
    """

    static func playback() -> MediaPlayback? {
        guard isRunning, let raw = run(readScript), raw != "stopped" else { return nil }
        let fields = raw.components(separatedBy: "\t")
        guard fields.count >= 7 else { return nil }

        return MediaPlayback(
            title: fields[0],
            artist: fields[1],
            album: fields[2],
            artworkURL: URL(string: fields[3]),
            durationMilliseconds: Int(AppleScriptNumber.parse(fields[4]) ?? 0),
            positionMilliseconds: Int(AppleScriptNumber.parse(fields[5]) ?? 0),
            isPlaying: fields[6].lowercased().contains("playing")
        )
    }

    // MARK: - Transport

    static func playPause() { perform("playpause") }
    static func next()      { perform("next track") }
    static func previous()  { perform("previous track") }

    private static func perform(_ command: String) {
        guard isRunning else { return }
        _ = run("tell application \"Spotify\" to \(command)")
    }

    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.activity.error("spotify applescript: \(error.description, privacy: .public)")
            return nil
        }
        return result?.stringValue
    }
}

/// Downloads and caches album art.
@MainActor
final class ArtworkLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private var loadedURL: URL?

    func load(_ url: URL?) {
        guard url != loadedURL else { return }
        loadedURL = url
        guard let url else { image = nil; return }

        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let downloaded = NSImage(data: data) else { return }
            await MainActor.run {
                // A later track may have won the race while this was in flight.
                guard self?.loadedURL == url else { return }
                self?.image = downloaded
            }
        }
    }
}
