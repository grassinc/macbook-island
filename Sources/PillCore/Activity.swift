import Foundation

/// Rank of an activity competing for the collapsed pill.
///
/// The collapsed pill is roughly 200pt wide, which fits one thing legibly.
/// Rotating between several is unreadable, so contention is resolved by rank
/// rather than by taking turns.
public enum ActivityPriority: Int, Comparable, Sendable {
    /// Steady background state: battery, thermal.
    case ambient = 0
    /// Something worth knowing, not worth interrupting for: an unread count.
    case info = 10
    /// Short-lived and self-expiring: a screenshot landed, output device changed.
    case transient = 20
    /// The user is acting right now and needs feedback: volume, brightness.
    case interruptive = 30

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What sort of thing an activity is. The app layer maps this to a view, which
/// is how PillCore avoids importing SwiftUI.
public enum ActivityKind: Sendable, Equatable, Hashable {
    case generic
    case audioOutput
    case hud
    case brightness
    case nowPlaying
    case screenshot
    case calendar
    case timer
    case thermal
    case battery
    case email
}

/// One thing the pill can show. Modules publish these; they never touch the window.
public struct Activity: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ActivityKind
    public let title: String
    public let subtitle: String?
    public let priority: ActivityPriority
    public let startedAt: Date
    /// When this stops being shown. `nil` means it stays until retracted.
    public let expiresAt: Date?
    /// Meter fill for HUD-style activities, always within 0...1. `nil` means
    /// this activity draws no meter.
    public let progress: Double?

    public init(id: String,
                kind: ActivityKind = .generic,
                title: String = "",
                subtitle: String? = nil,
                priority: ActivityPriority,
                startedAt: Date,
                expiresAt: Date? = nil,
                progress: Double? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.priority = priority
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        // Clamped on the way in: a device can report slightly outside the range
        // and an unclamped meter overflows its track.
        self.progress = progress.map { Swift.min(Swift.max($0, 0), 1) }
    }

    public func isLive(at now: Date) -> Bool {
        guard let expiresAt else { return true }
        return now < expiresAt
    }
}
