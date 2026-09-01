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

    public init() {}

    public func publish(_ activity: Activity) {
        activities[activity.id] = activity
    }

    public func retract(id: String) {
        activities.removeValue(forKey: id)
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
