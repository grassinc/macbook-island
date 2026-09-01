import Foundation
import PillCore

/// Bridges the pure coordinator to the view model.
///
/// Two things change what should be on screen: a module publishing or
/// retracting (a callback), and an activity expiring (the passage of time).
/// The second is handled by scheduling exactly one wake-up at the next expiry
/// instant, so the idle path never polls.
@MainActor
final class ActivityPresenter {
    private let coordinator: ActivityCoordinator
    private let model: PillViewModel
    private var expiryWork: DispatchWorkItem?

    init(coordinator: ActivityCoordinator, model: PillViewModel) {
        self.coordinator = coordinator
        self.model = model

        coordinator.onChange = { [weak self] in
            // Modules may notify from a CoreAudio or FSEvents queue.
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        let now = Date()
        model.setActivity(coordinator.selection(at: now))

        expiryWork?.cancel()
        expiryWork = nil

        guard let next = coordinator.nextExpiry(after: now) else { return }
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        expiryWork = work
        // A hair past the expiry so the comparison is unambiguously past it.
        DispatchQueue.main.asyncAfter(deadline: .now() + next.timeIntervalSince(now) + 0.02,
                                      execute: work)
    }
}
