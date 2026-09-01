import Foundation
import PillCore

@MainActor
final class TimerStore: ObservableObject {
    @Published fileprivate(set) var timer: CountdownTimer?
    @Published fileprivate(set) var phase: PomodoroPhase?
    @Published fileprivate(set) var remaining: TimeInterval = 0

    var isRunning: Bool { timer != nil }
}

/// Pomodoro and countdown timers (brief feature 12).
///
/// This is the one place in Pill with a repeating timer, and it is deliberate: a
/// countdown has to count. The project's "no polling" rule is about idle cost,
/// and a running countdown is not idle. The ticker exists only while a timer is
/// active and is torn down the moment it finishes, so the idle path still
/// schedules nothing.
@MainActor
final class TimerModule: PillModule {
    static let identifier = "timer"

    private let store: TimerStore
    private var context: ModuleContext?
    private var ticker: DispatchSourceTimer?
    private var completedPhases = 0

    init(store: TimerStore) { self.store = store }

    func activate(context: ModuleContext) {
        self.context = context
    }

    func deactivate() {
        stopTicker()
        context?.retract(id: Self.identifier)
    }

    // MARK: - Controls

    func start(duration: TimeInterval, phase: PomodoroPhase? = nil) {
        store.timer = CountdownTimer(duration: duration, startedAt: Date())
        store.phase = phase
        startTicker()
        tick()
        Log.activity.notice("timer started \(duration, privacy: .public)s")
    }

    func startPomodoro() {
        let phase = PomodoroCycle.phase(afterCompleted: completedPhases)
        start(duration: phase.duration, phase: phase)
    }

    func togglePause() {
        guard var timer = store.timer else { return }
        let now = Date()
        if timer.isPaused {
            timer.resume(at: now)
            startTicker()
        } else {
            timer.pause(at: now)
            stopTicker()
        }
        store.timer = timer
        tick()
    }

    func cancel() {
        stopTicker()
        store.timer = nil
        store.phase = nil
        store.remaining = 0
        context?.retract(id: Self.identifier)
        Log.activity.notice("timer cancelled")
    }

    // MARK: - Ticking

    private func startTicker() {
        stopTicker()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        source.resume()
        ticker = source
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard let timer = store.timer else { return }
        let now = Date()
        store.remaining = timer.remaining(at: now)

        if timer.isFinished(at: now) {
            finish()
            return
        }

        context?.publish(Activity(
            id: Self.identifier,
            kind: .timer,
            title: CountdownTimer.format(store.remaining),
            subtitle: store.phase?.label ?? "Timer",
            priority: .info,
            startedAt: timer.startedAt,
            progress: 1 - (store.remaining / timer.duration)
        ))
    }

    private func finish() {
        stopTicker()
        completedPhases += 1
        let finishedPhase = store.phase
        store.timer = nil
        store.remaining = 0

        let now = Date()
        context?.publish(Activity(
            id: Self.identifier,
            kind: .timer,
            title: "Time's up",
            subtitle: finishedPhase?.label,
            priority: .interruptive,
            startedAt: now,
            expiresAt: now.addingTimeInterval(8)
        ))
        Log.activity.notice("timer finished")
    }
}
