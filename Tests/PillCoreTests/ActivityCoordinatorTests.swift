import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

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
}
