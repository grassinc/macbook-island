import Foundation

/// The currently loaded track and where we are in it.
public struct MediaPlayback: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let artworkURL: URL?
    public let durationMilliseconds: Int
    public let positionMilliseconds: Int
    public let isPlaying: Bool

    public init(title: String, artist: String, album: String, artworkURL: URL?,
                durationMilliseconds: Int, positionMilliseconds: Int, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.durationMilliseconds = max(0, durationMilliseconds)
        self.positionMilliseconds = max(0, positionMilliseconds)
        self.isPlaying = isPlaying
    }

    /// Guarded against a duration of zero, which a track reports briefly while
    /// loading — dividing by it yields NaN and destroys the scrubber's layout.
    public var progress: Double {
        guard durationMilliseconds > 0 else { return 0 }
        return min(1, Double(positionMilliseconds) / Double(durationMilliseconds))
    }

    public var positionText: String { Self.clock(positionMilliseconds) }
    public var durationText: String { Self.clock(durationMilliseconds) }

    private static func clock(_ milliseconds: Int) -> String {
        let total = milliseconds / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Parses numbers that came back through AppleScript.
///
/// AppleScript formats numbers using the user's locale when they are coerced to
/// text. On this machine a track position arrives as "161,876998901367" — a
/// comma decimal separator — so `Double(string)` returns nil and the scrubber
/// silently sits at zero. Both separators are accepted.
public enum AppleScriptNumber {
    public static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) { return value }
        // Only a decimal comma is substituted; anything else stays invalid.
        let normalised = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalised)
    }
}
