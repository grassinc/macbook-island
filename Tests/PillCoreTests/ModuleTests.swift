import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

@MainActor
private final class FakeModule: PillModule {
    static let identifier = "fake"
    var activateCount = 0
    var deactivateCount = 0
    var context: ModuleContext?

    func activate(context: ModuleContext) {
        activateCount += 1
        self.context = context
    }
    func deactivate() { deactivateCount += 1 }
}

@MainActor
func runModuleTests(_ r: TestRunner) {

    r.test("registry activates every registered module once") { r in
        let coordinator = ActivityCoordinator()
        let registry = ModuleRegistry(coordinator: coordinator)
        let a = FakeModule(), b = FakeModule()
        registry.register(a)
        registry.register(b)

        registry.activateAll()

        r.expectEqual(a.activateCount, 1, "module a activated once")
        r.expectEqual(b.activateCount, 1, "module b activated once")
    }

    r.test("registry deactivates every module") { r in
        let registry = ModuleRegistry(coordinator: ActivityCoordinator())
        let m = FakeModule()
        registry.register(m)
        registry.activateAll()
        registry.deactivateAll()

        r.expectEqual(m.deactivateCount, 1, "module deactivated once")
    }

    r.test("a module publishes through its context into the coordinator") { r in
        let coordinator = ActivityCoordinator()
        let registry = ModuleRegistry(coordinator: coordinator)
        let m = FakeModule()
        registry.register(m)
        registry.activateAll()

        m.context?.publish(Activity(id: "fake.thing", priority: .info, startedAt: t0))

        r.expectEqual(coordinator.selection(at: t0)?.id, "fake.thing",
                      "context publish should reach the coordinator")
    }

    r.test("a module retracts through its context") { r in
        let coordinator = ActivityCoordinator()
        let registry = ModuleRegistry(coordinator: coordinator)
        let m = FakeModule()
        registry.register(m)
        registry.activateAll()
        m.context?.publish(Activity(id: "fake.thing", priority: .info, startedAt: t0))
        m.context?.retract(id: "fake.thing")

        r.expect(coordinator.selection(at: t0) == nil, "context retract should reach the coordinator")
    }
}
