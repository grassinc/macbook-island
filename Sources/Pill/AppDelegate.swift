import AppKit
import PillCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let coordinator = ActivityCoordinator()

    // Observable stores, each owned by its module and read by the UI.
    private let audioStore = AudioOutputStore()
    private let hudStore = HUDStore()
    private let shelfStore = ShelfObservable()
    private let thermalStore = ThermalStore()
    private let batteryStore = BatteryStore()
    private let timerStore = TimerStore()
    private let calendarStore = CalendarStore()
    private let privacyStore = PrivacyStore()
    private let nowPlayingStore = NowPlayingStore()
    private let networkStore = NetworkStore()

    private var model: PillViewModel!
    private var registry: ModuleRegistry!
    private var presenter: ActivityPresenter!
    private var controller: PillWindowController!

    private var audioModule: AudioOutputModule!
    private var hudModule: HUDModule!
    private var shelfModule: ShelfModule!
    private var thermalModule: ThermalModule!
    private var batteryModule: BatteryModule!
    private var timerModule: TimerModule!
    private var calendarModule: CalendarModule!
    private var privacyModule: PrivacyModule!
    private var nowPlayingModule: NowPlayingModule!
    private var networkModule: NetworkModule!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = PillViewModel(audio: audioStore, hud: hudStore, shelf: shelfStore,
                              thermal: thermalStore, battery: batteryStore,
                              timer: timerStore, calendar: calendarStore, privacy: privacyStore,
                              nowPlaying: nowPlayingStore,
                              network: networkStore)
        presenter = ActivityPresenter(coordinator: coordinator, model: model, privacy: privacyStore)

        audioModule = AudioOutputModule(store: audioStore)
        hudModule = HUDModule(store: hudStore)
        shelfModule = ShelfModule(observable: shelfStore)
        thermalModule = ThermalModule(store: thermalStore)
        batteryModule = BatteryModule(store: batteryStore)
        timerModule = TimerModule(store: timerStore)
        calendarModule = CalendarModule(store: calendarStore)
        privacyModule = PrivacyModule(store: privacyStore)
        nowPlayingModule = NowPlayingModule(store: nowPlayingStore)
        networkModule = NetworkModule(store: networkStore)

        wireActions()

        registry = ModuleRegistry(coordinator: coordinator)
        for module in [audioModule, hudModule, shelfModule, thermalModule,
                       batteryModule, timerModule, calendarModule, privacyModule,
                       nowPlayingModule, networkModule] as [any PillModule] {
            registry.register(module)
        }
        registry.activateAll()

        controller = PillWindowController(model: model)
        controller.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry?.deactivateAll()
    }

    private func wireActions() {
        model.selectDevice = { [weak self] device in self?.audioModule.select(device) }

        model.requestAccessibility = {
            // The prompt only appears once; opening the pane too means the
            // button always does something visible.
            MediaKeyTap.requestTrust()
            AccessibilityMonitor.openSettings()
            Log.permissions.notice("accessibility prompt requested")
        }
        model.onExpand = { [weak self] in
            guard let self else { return }
            self.shelfModule.pruneMissing()
            guard !self.hudStore.isReplacingSystemHUD else { return }
            if self.hudModule.retryKeyTap() {
                Log.permissions.notice("key tap started after grant")
            }
        }

        model.addFiles = { [weak self] urls in self?.shelfModule.addDropped(urls) }
        model.runTransform = { [weak self] action, item in self?.shelfModule.runTransform(action, on: item) }
        model.removeShelfItem = { [weak self] item in self?.shelfModule.remove(item) }
        model.clearShelf = { [weak self] in self?.shelfModule.clear() }
        model.beginShelfDrag = { [weak self] in self?.shelfModule.beginDrag() }
        shelfModule.onDragEnded = { [weak self] in self?.model.endShelfDrag() }

        model.startTimer = { [weak self] duration in self?.timerModule.start(duration: duration) }
        model.startPomodoro = { [weak self] in self?.timerModule.startPomodoro() }
        model.toggleTimerPause = { [weak self] in self?.timerModule.togglePause() }
        model.cancelTimer = { [weak self] in self?.timerModule.cancel() }

        model.requestCalendarAccess = { [weak self] in self?.calendarModule.requestAccess() }
        model.toggleScreenShare = { [weak self] in self?.privacyModule.toggle() }
        model.mediaPlayPause = { [weak self] in self?.nowPlayingModule.playPause() }
        model.mediaNext = { [weak self] in self?.nowPlayingModule.next() }
        model.mediaPrevious = { [weak self] in self?.nowPlayingModule.previous() }
        // The scrubber only needs to move while someone can see it.
        model.onPanelOpenChanged = { [weak self] open in self?.nowPlayingModule.setPanelOpen(open) }
    }
}
