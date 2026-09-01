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

    private var cancellables = Set<AnyCancellable>()
    private var collapseWork: DispatchWorkItem?

    private static let collapsedSize = CGSize(width: 190, height: 30)
    private static let expandedWidth: CGFloat = 360

    init(audio: AudioOutputStore, hud: HUDStore, shelf: ShelfObservable,
         thermal: ThermalStore, battery: BatteryStore, timer: TimerStore,
         calendar: CalendarStore, privacy: PrivacyStore) {
        self.audio = audio
        self.hud = hud
        self.shelf = shelf
        self.thermal = thermal
        self.battery = battery
        self.timer = timer
        self.calendar = calendar
        self.privacy = privacy
        self.size = Self.collapsedSize

        // The panel is sized from what is actually in it. Anything conditional
        // contributes only while it is on screen, so the pill never reserves
        // space for a section the user cannot see.
        let inputs = Publishers.CombineLatest4(
            $presentation,
            audio.$state,
            hud.$isReplacingSystemHUD,
            Publishers.CombineLatest3(calendar.$nextEvent, timer.$timer, shelf.$items)
        )

        inputs
            .map { presentation, audioState, replacing, rest -> CGSize in
                guard presentation == .expanded else { return Self.collapsedSize }
                let (event, runningTimer, _) = rest

                var height: CGFloat = 24        // padding
                height += 22                    // status row: battery, thermal, share toggle
                height += 14                    // OUTPUT label
                height += CGFloat(max(audioState.devices.count, 1)) * 30
                height += 14 + 50               // SHELF label + strip
                height += 30                    // timer controls
                if event != nil { height += 26 }
                if runningTimer != nil { height += 4 }
                if !replacing { height += 34 }   // permission row
                return CGSize(width: Self.expandedWidth, height: height)
            }
            .removeDuplicates()
            .assign(to: \.size, on: self)
            .store(in: &cancellables)
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
                Log.activity.debug("collapse committed")
                self.presentation = .collapsed
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseGrace, execute: work)
            return
        }

        presentation = .expanded
        onExpand?()
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
