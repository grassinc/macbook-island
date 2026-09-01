import AppKit
import PillCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let coordinator = ActivityCoordinator()
    private let audioStore = AudioOutputStore()
    private let hudStore = HUDStore()
    private let shelfStore = ShelfObservable()

    private var model: PillViewModel!
    private var registry: ModuleRegistry!
    private var presenter: ActivityPresenter!
    private var controller: PillWindowController!
    private var audioModule: AudioOutputModule!
    private var hudModule: HUDModule!
    private var shelfModule: ShelfModule!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = PillViewModel(audio: audioStore, hud: hudStore, shelf: shelfStore)
        presenter = ActivityPresenter(coordinator: coordinator, model: model)

        audioModule = AudioOutputModule(store: audioStore)
        model.selectDevice = { [weak self] device in self?.audioModule.select(device) }

        hudModule = HUDModule(store: hudStore)
        shelfModule = ShelfModule(observable: shelfStore)

        model.addFiles = { [weak self] urls in self?.shelfModule.addDropped(urls) }
        model.runTransform = { [weak self] action, item in self?.shelfModule.runTransform(action, on: item) }
        model.removeShelfItem = { [weak self] item in self?.shelfModule.remove(item) }
        model.clearShelf = { [weak self] in self?.shelfModule.clear() }

        registry = ModuleRegistry(coordinator: coordinator)
        registry.register(audioModule)
        registry.register(hudModule)
        registry.register(shelfModule)
        registry.activateAll()

        model.requestAccessibility = {
            // The prompt only appears the first time; opening the pane as well
            // means the button always does something visible.
            MediaKeyTap.requestTrust()
            AccessibilityMonitor.openSettings()
            Log.permissions.notice("accessibility prompt requested")
        }
        // Re-check on expand rather than polling for the grant.
        model.onExpand = { [weak self] in
            guard let self, !self.hudStore.isReplacingSystemHUD else { return }
            if self.hudModule.retryKeyTap() {
                Log.permissions.notice("key tap started after grant")
            }
        }

        controller = PillWindowController(model: model)
        controller.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry?.deactivateAll()
    }
}
