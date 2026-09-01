import Foundation

/// A process that CoreAudio knows about, and whether it is making sound.
public struct AudioSource: Equatable, Sendable, Identifiable {
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public let isOutputting: Bool

    public var id: Int32 { pid }

    public init(pid: Int32, bundleID: String, name: String, isOutputting: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isOutputting = isOutputting
    }
}

/// Picks the app to describe as "what you are listening to".
///
/// Built on the public `kAudioHardwarePropertyProcessObjectList` rather than
/// MediaRemote. MediaRemote's now-playing dictionary comes back nil for a
/// third-party caller on this machine, and Apple gates it on code identity that
/// no third party can obtain. The CoreAudio route answers a slightly different
/// question — which app is producing sound, rather than what track is loaded —
/// but it is public, unpermissioned, and cannot be taken away in a point release.
public enum NowPlayingSelector {

    /// Audio plumbing that is permanently in the process list. Reporting
    /// "controlcenter is playing" would be nonsense, so these never win.
    private static let infrastructure: Set<String> = [
        "com.apple.audiomxd",
        "com.apple.mediaremoted",
        "com.apple.controlcenter",
        "com.apple.universalaccessd",
        "com.apple.cmio.ContinuityCaptureAgent",
        "com.apple.TelephonyUtilities",
        "com.apple.avconferenced",
        "com.apple.CoreSpeech",
        "com.apple.assistantd",
        "com.apple.loginwindow",
        "com.apple.PowerChime",
        "com.apple.SiriNCService",
        "com.apple.accessibility.heard",
        "com.pill.app",
    ]

    public static func isReportable(_ source: AudioSource) -> Bool {
        !source.bundleID.isEmpty && !infrastructure.contains(source.bundleID)
    }

    /// Lowest pid wins when several apps play at once: an arbitrary but *stable*
    /// rule, so the pill does not flicker between them as the list reorders.
    public static func primary(from sources: [AudioSource]) -> AudioSource? {
        sources
            .filter { $0.isOutputting && isReportable($0) }
            .min { $0.pid < $1.pid }
    }
}
