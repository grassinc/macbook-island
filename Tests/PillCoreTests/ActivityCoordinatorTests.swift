import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

func runActivityCoordinatorTests(_ r: TestRunner) {

    r.test("with nothing published, nothing is selected") { r in
        let coordinator = ActivityCoordinator()
        r.expect(coordinator.selection(at: t0) == nil, "empty coordinator should select nothing")
    }

    r.test("a single published activity becomes the selection") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "battery", priority: .ambient, startedAt: t0))
        r.expectEqual(coordinator.selection(at: t0)?.id, "battery", "single activity should be selected")
    }

    r.test("higher priority wins regardless of publish order") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "volume", priority: .interruptive, startedAt: t0))
        coordinator.publish(Activity(id: "battery", priority: .ambient, startedAt: at(1)))
        r.expectEqual(coordinator.selection(at: at(1))?.id, "volume",
                      "interruptive should outrank a newer ambient activity")
    }

    r.test("among equal priorities the newest wins") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "shot-1", priority: .transient, startedAt: t0))
        coordinator.publish(Activity(id: "shot-2", priority: .transient, startedAt: at(5)))
        r.expectEqual(coordinator.selection(at: at(5))?.id, "shot-2",
                      "newer activity should break the priority tie")
    }

    r.test("an expired activity is no longer selected") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "shot", priority: .transient, startedAt: t0, expiresAt: at(4)))
        r.expect(coordinator.selection(at: at(3))?.id == "shot", "should be live before expiry")
        r.expect(coordinator.selection(at: at(5)) == nil, "should be gone after expiry")
    }

    r.test("a retracted activity is no longer selected") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "mic", priority: .info, startedAt: t0))
        coordinator.retract(id: "mic")
        r.expect(coordinator.selection(at: t0) == nil, "retracted activity should be gone")
    }

    // The rule that makes preemption feel right. A volume HUD appearing over a
    // screenshot thumbnail must COVER it, not evict it — when the HUD expires
    // the thumbnail has to come back. Dropping it would lose the user's
    // screenshot, which is a data-loss bug wearing a UI costume.
    r.test("an interruptive activity covers rather than evicts, and restores on expiry") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "screenshot", priority: .transient, startedAt: t0, expiresAt: at(30)))
        coordinator.publish(Activity(id: "volume", priority: .interruptive, startedAt: at(1), expiresAt: at(2.5)))

        r.expectEqual(coordinator.selection(at: at(2))?.id, "volume", "HUD should cover the thumbnail")
        r.expectEqual(coordinator.selection(at: at(3))?.id, "screenshot", "thumbnail must return after the HUD expires")
    }

    r.test("republishing the same id replaces rather than duplicates") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "volume", priority: .interruptive, startedAt: t0, expiresAt: at(2)))
        coordinator.publish(Activity(id: "volume", priority: .interruptive, startedAt: at(1), expiresAt: at(3)))

        r.expectEqual(coordinator.liveActivities(at: at(2.5)).count, 1, "same id should not accumulate")
        r.expect(coordinator.selection(at: at(2.5))?.id == "volume", "refreshed activity should extend its life")
    }

    r.test("publishing notifies an observer") { r in
        let coordinator = ActivityCoordinator()
        var notifications = 0
        coordinator.onChange = { notifications += 1 }
        coordinator.publish(Activity(id: "a", priority: .info, startedAt: t0))
        r.expectEqual(notifications, 1, "publish should notify once")
    }

    r.test("retracting notifies an observer") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "a", priority: .info, startedAt: t0))
        var notifications = 0
        coordinator.onChange = { notifications += 1 }
        coordinator.retract(id: "a")
        r.expectEqual(notifications, 1, "retract should notify once")
    }

    // Expiry changes what is on screen without any publish or retract, so the
    // presenter needs to know when to look again. Returning the earliest future
    // expiry lets it schedule exactly one wake-up instead of polling.
    r.test("next expiry is the earliest one still in the future") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "long", priority: .transient, startedAt: t0, expiresAt: at(30)))
        coordinator.publish(Activity(id: "short", priority: .interruptive, startedAt: t0, expiresAt: at(2)))
        r.expectEqual(coordinator.nextExpiry(after: t0), at(2), "earliest future expiry wins")
    }

    r.test("expiries already in the past are not scheduled again") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "gone", priority: .transient, startedAt: t0, expiresAt: at(2)))
        coordinator.publish(Activity(id: "later", priority: .transient, startedAt: t0, expiresAt: at(30)))
        r.expectEqual(coordinator.nextExpiry(after: at(10)), at(30), "past expiries are skipped")
    }

    r.test("with nothing expiring there is no wake-up to schedule") { r in
        let coordinator = ActivityCoordinator()
        coordinator.publish(Activity(id: "forever", priority: .ambient, startedAt: t0))
        r.expect(coordinator.nextExpiry(after: t0) == nil, "a permanent activity schedules nothing")
    }

    // The pill has to render something. Activities carry semantic display data
    // and a kind; mapping kind to an actual view stays in the app layer so
    // PillCore never imports SwiftUI.
    r.test("an activity carries a title and a kind for rendering") { r in
        let a = Activity(id: "audio.output", kind: .audioOutput, title: "AirPods Pro",
                         subtitle: "Output", priority: .transient, startedAt: t0)
        r.expectEqual(a.title, "AirPods Pro", "title is carried")
        r.expectEqual(a.subtitle, "Output", "subtitle is carried")
        r.expect(a.kind == .audioOutput, "kind is carried")
    }

    r.test("kind and title default so simple activities stay terse") { r in
        let a = Activity(id: "x", priority: .info, startedAt: t0)
        r.expect(a.kind == .generic, "kind defaults to generic")
        r.expectEqual(a.title, "", "title defaults to empty")
    }
}
