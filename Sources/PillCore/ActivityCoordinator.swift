import Foundation

/// Holds the set of live activities and decides which one the collapsed pill shows.
///
/// Selection is a pure function of the current time, so it can be tested without
/// waiting on real clocks.
public final class ActivityCoordinator {
    private var activities: [Activity] = []

    public init() {}

    public func publish(_ activity: Activity) {
        activities.append(activity)
    }

    public func selection(at now: Date) -> Activity? {
        activities.last
    }
}
