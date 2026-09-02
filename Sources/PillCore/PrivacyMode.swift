import Foundation

/// Screen-share mode (brief feature 14).
///
/// Redaction is by activity *kind*, not by scanning text for secrets. Guessing
/// which words are sensitive fails in both directions; knowing that calendar
/// titles and screenshot filenames are personal, while a volume level is not,
/// does not.
public enum PrivacyMode: Equatable, Sendable {
    case normal
    case screenShare

    /// Kinds whose title can expose something the user would not want on a
    /// projector or in a recording.
    private static let sensitiveKinds: Set<ActivityKind> = [.calendar, .screenshot]

    public func redact(_ activity: Activity) -> Activity {
        guard self == .screenShare, Self.sensitiveKinds.contains(activity.kind) else { return activity }

        return Activity(
            id: activity.id,
            kind: activity.kind,
            title: Self.neutralTitle(for: activity.kind),
            // Timing and counts stay: "in 10m" is useful and gives nothing away.
            subtitle: activity.subtitle,
            priority: activity.priority,
            startedAt: activity.startedAt,
            expiresAt: activity.expiresAt,
            progress: activity.progress
        )
    }

    private static func neutralTitle(for kind: ActivityKind) -> String {
        switch kind {
        case .calendar:   "Event"
        case .screenshot: "Screenshot"
        default:          ""
        }
    }
}
