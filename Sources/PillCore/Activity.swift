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

/// One thing the pill can show. Modules publish these; they never touch the window.
public struct Activity: Sendable, Equatable, Identifiable {
    public let id: String
    public let priority: ActivityPriority
    public let startedAt: Date
    /// When this stops being shown. `nil` means it stays until retracted.
    public let expiresAt: Date?

    public init(id: String, priority: ActivityPriority, startedAt: Date, expiresAt: Date? = nil) {
        self.id = id
        self.priority = priority
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    public func isLive(at now: Date) -> Bool {
        guard let expiresAt else { return true }
        return now < expiresAt
    }
}
