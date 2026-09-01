import AppKit
import PillCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let coordinator = ActivityCoordinator()
    private let audioStore = AudioOutputStore()
    private let hudStore = HUDStore()

    private var model: PillViewModel!
    private var registry: ModuleRegistry!
    private var presenter: ActivityPresenter!
    private var controller: PillWindowController!
    private var audioModule: AudioOutputModule!
    private var hudModule: HUDModule!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = PillViewModel(audio: audioStore, hud: hudStore)
        presenter = ActivityPresenter(coordinator: coordinator, model: model)

        audioModule = AudioOutputModule(store: audioStore)
        model.selectDevice = { [weak self] device in self?.audioModule.select(device) }

        hudModule = HUDModule(store: hudStore)

        registry = ModuleRegistry(coordinator: coordinator)
        registry.register(audioModule)
        registry.register(hudModule)
        registry.activateAll()

        model.requestAccessibility = {
            MediaKeyTap.requestTrust()
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
