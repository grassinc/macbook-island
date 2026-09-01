import Foundation

/// A countdown that can be paused.
///
/// Pausing is modelled by accumulating elapsed time rather than by mutating the
/// start date, so `remaining(at:)` stays a pure function of the current instant
/// and can be tested without waiting on real clocks.
public struct CountdownTimer: Equatable, Sendable {
    public let duration: TimeInterval
    public private(set) var startedAt: Date
    /// Time already consumed before the current run segment.
    public private(set) var accumulated: TimeInterval
    public private(set) var isPaused: Bool

    public init(duration: TimeInterval, startedAt: Date) {
        self.duration = duration
        self.startedAt = startedAt
        self.accumulated = 0
        self.isPaused = false
    }

    public func elapsed(at now: Date) -> TimeInterval {
        isPaused ? accumulated : accumulated + now.timeIntervalSince(startedAt)
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, duration - elapsed(at: now))
    }

    public func isFinished(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }

    public mutating func pause(at now: Date) {
        guard !isPaused else { return }
        accumulated += now.timeIntervalSince(startedAt)
        isPaused = true
    }

    public mutating func resume(at now: Date) {
        guard isPaused else { return }
        startedAt = now
        isPaused = false
    }

    /// `m:ss`, staying in minutes past an hour — a 90 minute timer reads 90:00,
    /// which is easier to parse at a glance than 1:30:00 in a strip this small.
    public static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

public enum PomodoroPhase: Equatable, Sendable {
    case work, shortBreak, longBreak

    public var duration: TimeInterval {
        switch self {
        case .work:       25 * 60
        case .shortBreak:  5 * 60
        case .longBreak:  15 * 60
        }
    }

    public var label: String {
        switch self {
        case .work:       "Focus"
        case .shortBreak: "Break"
        case .longBreak:  "Long break"
        }
    }
}

public enum PomodoroCycle {
    /// Work and break alternate; every fourth work block earns a long break.
    public static func phase(afterCompleted completed: Int) -> PomodoroPhase {
        guard completed % 2 == 1 else { return .work }
        let workBlocksDone = completed / 2 + 1
        return workBlocksDone % 4 == 0 ? .longBreak : .shortBreak
    }
}
