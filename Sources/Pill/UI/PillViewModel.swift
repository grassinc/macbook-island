import SwiftUI
import Combine
import PillCore

enum PillPresentation: Equatable {
    case collapsed
    case expanded
}

@MainActor
final class PillViewModel: ObservableObject {
    @Published private(set) var presentation: PillPresentation = .collapsed
    @Published private(set) var activity: Activity?
    @Published private(set) var size: CGSize = .zero

    let audio: AudioOutputStore
    let hud: HUDStore
    let shelf: ShelfObservable
    let thermal: ThermalStore
    let battery: BatteryStore
    let timer: TimerStore
    let calendar: CalendarStore
    let privacy: PrivacyStore
    let email: EmailStore
    let nowPlaying: NowPlayingStore
    let network: NetworkStore

    // Actions, so the views never reach into modules.
    var selectDevice: ((AudioOutputDevice) -> Void)?
    var requestAccessibility: (() -> Void)?
    var onExpand: (() -> Void)?
    var addFiles: (([URL]) -> Void)?
    var runTransform: ((TransformAction, ShelfItem) -> Void)?
    var removeShelfItem: ((ShelfItem) -> Void)?
    var clearShelf: (() -> Void)?
    var beginShelfDrag: (() -> Void)?
    var startTimer: ((TimeInterval) -> Void)?
    var startPomodoro: (() -> Void)?
    var toggleTimerPause: (() -> Void)?
    var cancelTimer: (() -> Void)?
    var requestCalendarAccess: (() -> Void)?
    var toggleScreenShare: (() -> Void)?
    /// Supplied by the window controller. SwiftUI reports a hover as the panel
    /// animates under the cursor; without this the pill re-opens mid-close and
    /// visibly jitters sideways.
    var pointerIsOverPanel: (() -> Bool)?
    var connectEmail: (() -> Void)?
    var mediaPlayPause: (() -> Void)?
    var mediaNext: (() -> Void)?
    var mediaPrevious: (() -> Void)?
    /// Fires when the panel opens or closes, so work that only matters while
    /// the user is looking (the scrubber) can be started and stopped.
    var onPanelOpenChanged: ((Bool) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var collapseWork: DispatchWorkItem?

    static let collapsedSize = CGSize(width: 260, height: 38)
    private static let expandedWidth: CGFloat = 440

    init(audio: AudioOutputStore, hud: HUDStore, shelf: ShelfObservable,
         thermal: ThermalStore, battery: BatteryStore, timer: TimerStore,
         calendar: CalendarStore, privacy: PrivacyStore, email: EmailStore,
         nowPlaying: NowPlayingStore, network: NetworkStore) {
        self.audio = audio
        self.hud = hud
        self.shelf = shelf
        self.thermal = thermal
        self.battery = battery
        self.timer = timer
        self.calendar = calendar
        self.privacy = privacy
        self.email = email
        self.nowPlaying = nowPlaying
        self.network = network
        self.size = Self.collapsedSize

        // Width is ours to choose; HEIGHT IS MEASURED, never computed.
        // Hand-adding section heights silently forgot the VStack spacing and
        // clipped the bottom of the panel, and any such formula rots the moment
        // a section is added. The view reports what it actually needs.
        $presentation
            .map { $0 == .collapsed ? Self.collapsedSize.width : Self.expandedWidth }
            .removeDuplicates()
            .sink { [weak self] width in
                guard let self else { return }
                self.size = CGSize(width: width, height: self.size.height)
            }
            .store(in: &cancellables)
    }

    /// Reported by the view once SwiftUI has laid the content out.
    func setMeasuredHeight(_ height: CGFloat) {
        let rounded = height.rounded(.up)
        guard rounded > 0, abs(rounded - size.height) > 0.5 else { return }
        size = CGSize(width: size.width, height: rounded)
    }

    /// Collapse is delayed; expand is immediate.
    ///
    /// Resizing the panel makes AppKit rebuild the hosting view's tracking area,
    /// which emits a spurious exit-then-enter pair. Acting on that exit directly
    /// made the pill oscillate between sizes on every hover. A short grace
    /// period absorbs it, and doubles as forgiveness for the pointer clipping a
    /// corner on its way to a control.
    private static let collapseGrace: TimeInterval = 0.18

    func setHovered(_ hovered: Bool) {
        Log.activity.debug("hover=\(hovered, privacy: .public)")
        collapseWork?.cancel()
        collapseWork = nil

        guard hovered else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // Dragging a file out means the pointer leaves the pill by
                // definition. Collapsing then would destroy the drag source
                // mid-flight, so stay open until the drag finishes.
                guard !self.shelf.isDraggingOut else {
                    Log.activity.debug("collapse deferred: drag in flight")
                    return
                }
                // SwiftUI also reports un-hover when the view rebuilds after a
                // resize. With a stationary pointer no corrective event ever
                // follows, so the panel closed under the user's cursor. The
                // pointer is the authority in both directions; a genuine exit
                // is caught by the window controller's pointer monitor.
                if let inside = self.pointerIsOverPanel, inside() {
                    Log.activity.debug("collapse ignored: pointer is still inside")
                    return
                }
                Log.activity.debug("collapse committed")
                // The tiles go away without reporting an exit.
                self.shelf.hoveredTileID = nil
                self.presentation = .collapsed
                self.onPanelOpenChanged?(false)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseGrace, execute: work)
            return
        }

        // Trust the pointer, not the hover event.
        if let pointerIsOverPanel, !pointerIsOverPanel() {
            Log.activity.debug("ignoring hover: pointer is not over the panel")
            return
        }
        let wasCollapsed = presentation == .collapsed
        presentation = .expanded
        onExpand?()
        if wasCollapsed { onPanelOpenChanged?(true) }
    }

    /// After a drag-out ends, re-evaluate whether to close. If the pointer came
    /// back over the pill, the resulting hover cancels this.
    func endShelfDrag() {
        setHovered(false)
    }

    /// Dragging files over the collapsed pill opens it, so there is somewhere to
    /// drop them without having to hover first and drag second.
    func setDragTargeted(_ targeted: Bool) {
        if targeted { presentation = .expanded }
    }

    func setActivity(_ activity: Activity?) {
        self.activity = activity
    }
}
