import Foundation

/// A feature that can put something in the pill.
///
/// A module receives only a `ModuleContext` — it cannot reach the panel, the
/// coordinator, or another module. That boundary is what lets a module be
/// exercised in tests with no window on screen.
@MainActor
public protocol PillModule: AnyObject {
    static var identifier: String { get }

    /// Start event sources. Called once at launch.
    func activate(context: ModuleContext)

    /// Tear down every event source. Must return the module to zero scheduled work.
    func deactivate()
}

/// The only surface a module has on the rest of the app.
@MainActor
public final class ModuleContext {
    private let coordinator: ActivityCoordinator

    public init(coordinator: ActivityCoordinator) {
        self.coordinator = coordinator
    }

    public func publish(_ activity: Activity) { coordinator.publish(activity) }
    public func retract(id: String) { coordinator.retract(id: id) }
}

/// Owns the modules and their lifecycle.
///
/// Registration is static and in-process for v0.1. A plugin API is a public
/// contract, and freezing one before the first three modules exist would design
/// it against zero real users. `PillModule` is shaped so a future bundle loader
/// can implement the same protocol without module code changing.
@MainActor
public final class ModuleRegistry {
    private let coordinator: ActivityCoordinator
    private var modules: [any PillModule] = []

    public init(coordinator: ActivityCoordinator) {
        self.coordinator = coordinator
    }

    public func register(_ module: any PillModule) {
        modules.append(module)
    }

    public func activateAll() {
        for module in modules {
            // Each module gets its own context so they never share a handle.
            module.activate(context: ModuleContext(coordinator: coordinator))
        }
    }

    public func deactivateAll() {
        for module in modules { module.deactivate() }
    }
}
