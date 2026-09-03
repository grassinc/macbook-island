import EventKit
import Foundation
import PillCore

@MainActor
final class CalendarStore: ObservableObject {
    @Published fileprivate(set) var nextEvent: CalendarEvent?
    @Published fileprivate(set) var countdown: String = ""
    @Published fileprivate(set) var accessGranted = false
    @Published fileprivate(set) var accessDenied = false
}

/// Calendar peek with one-click join (brief feature 8).
///
/// EventKit posts `.EKEventStoreChanged` when anything changes, so the event
/// list is not polled. The countdown text does need to move, but only once a
/// minute and only while an event is pending — a single one-shot scheduled to
/// the next minute boundary, rescheduled each time, rather than a ticker.
@MainActor
final class CalendarModule: PillModule {
    static let identifier = "calendar"

    private let store: CalendarStore
    private let eventStore = EKEventStore()
    private var context: ModuleContext?
    private var changeObserver: NSObjectProtocol?
    private var refreshWork: DispatchWorkItem?

    /// Only look this far ahead; an event tomorrow is not a "peek".
    private let horizon: TimeInterval = 12 * 3600

    init(store: CalendarStore) { self.store = store }

    func activate(context: ModuleContext) {
        self.context = context

        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            store.accessGranted = true
            begin()
        case .denied, .restricted:
            store.accessDenied = true
            Log.permissions.notice("calendar access denied")
        default:
            // Not determined: stay quiet until the user asks for it from the panel.
            Log.permissions.notice("calendar access not determined")
        }
    }

    func deactivate() {
        refreshWork?.cancel()
        refreshWork = nil
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        context?.retract(id: Self.identifier)
    }

    /// Called from the panel, so the prompt appears because the user asked.
    func requestAccess() {
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.store.accessGranted = granted
                    self.store.accessDenied = !granted
                    Log.permissions.notice("calendar granted=\(granted, privacy: .public)")
                    if granted { self.begin() }
                    if let error { Log.permissions.error("calendar: \(error.localizedDescription, privacy: .public)") }
                }
            }
        }
    }

    private func begin() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let now = Date()
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(horizon),
            calendars: nil
        )
        let events = eventStore.events(matching: predicate).map {
            CalendarEvent(title: $0.title ?? "Untitled",
                          startsAt: $0.startDate,
                          isAllDay: $0.isAllDay,
                          durationMinutes: max(1, Int($0.endDate.timeIntervalSince($0.startDate) / 60)),
                          location: $0.location,
                          notes: $0.notes,
                          urlString: $0.url?.absoluteString)
        }

        let next = CalendarPeek.next(from: events, at: now)
        store.nextEvent = next
        store.countdown = next.map { CalendarPeek.countdown(to: $0.startsAt, from: now) } ?? ""

        // Published only while the event is near. The countdown goes in the
        // title because the collapsed pill renders the title alone -- putting it
        // in the subtitle meant the one number worth glancing at never showed.
        if let next, CalendarPeek.isImminent(next.startsAt, at: now) {
            context?.publish(Activity(
                id: Self.identifier,
                kind: .calendar,
                title: "\(next.title) · \(store.countdown)",
                subtitle: store.countdown,
                priority: .info,
                startedAt: now
            ))
        } else {
            context?.retract(id: Self.identifier)
        }

        scheduleNextMinuteRefresh(from: now, hasEvent: next != nil)
    }

    /// One wake-up at the next minute boundary, and only while something is
    /// pending. No ticker.
    private func scheduleNextMinuteRefresh(from now: Date, hasEvent: Bool) {
        refreshWork?.cancel()
        refreshWork = nil
        guard hasEvent else { return }

        let secondsToNextMinute = 60 - (Int(now.timeIntervalSince1970) % 60)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(secondsToNextMinute), execute: work)
    }
}
