import Foundation

/// Holds the live activities and decides which one the collapsed pill shows.
///
/// Selection is a pure function of the current time, so behaviour around expiry
/// can be tested without waiting on real clocks.
///
/// Activities are keyed by id, which gives republish-replaces semantics: a
/// module refreshing its activity (volume changing again while the HUD is still
/// up) extends the existing one instead of stacking duplicates.
public final class ActivityCoordinator {
    private var activities: [String: Activity] = [:]

    /// Called whenever the set of activities changes. Expiry does NOT fire this
    /// — nothing changes in the set when time passes — so a presenter also needs
    /// `nextExpiry(after:)` to know when to re-evaluate.
    public var onChange: (() -> Void)?

    public init() {}

    public func publish(_ activity: Activity) {
        activities[activity.id] = activity
        onChange?()
    }

    public func retract(id: String) {
        guard activities.removeValue(forKey: id) != nil else { return }
        onChange?()
    }

    /// The earliest expiry still ahead of `now`, or nil if nothing will expire.
    ///
    /// This is what keeps the idle path free of polling: the presenter schedules
    /// exactly one wake-up for this instant rather than ticking to check.
    public func nextExpiry(after now: Date) -> Date? {
        activities.values
            .compactMap(\.expiresAt)
            .filter { $0 > now }
            .min()
    }

    public func liveActivities(at now: Date) -> [Activity] {
        activities.values.filter { $0.isLive(at: now) }
    }

    /// Highest priority wins; ties break toward the newest. Nothing is ever
    /// evicted by a higher-priority arrival — it is merely outranked while it
    /// lives, so when an interruptive activity expires whatever it covered
    /// becomes selectable again.
    ///
    /// The id is the final tiebreaker purely so the result is deterministic
    /// when two activities share both rank and timestamp.
    public func selection(at now: Date) -> Activity? {
        liveActivities(at: now).max {
            ($0.priority, $0.startedAt, $0.id) < ($1.priority, $1.startedAt, $1.id)
        }
    }
}
