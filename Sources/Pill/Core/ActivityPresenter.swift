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
    private let privacy: PrivacyStore
    private var expiryWork: DispatchWorkItem?

    init(coordinator: ActivityCoordinator, model: PillViewModel, privacy: PrivacyStore) {
        self.coordinator = coordinator
        self.model = model
        self.privacy = privacy

        coordinator.onChange = { [weak self] in
            // Modules may notify from a CoreAudio or FSEvents queue.
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        let now = Date()
        // Redact at the display boundary so no module has to remember to.
        let selected = coordinator.selection(at: now).map { privacy.mode.redact($0) }
        model.setActivity(selected)
        Log.activity.notice("showing=\(selected?.id ?? "nothing", privacy: .public)")

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
