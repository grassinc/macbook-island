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

    /// Set by the app so the view can act without knowing about modules.
    var selectDevice: ((AudioOutputDevice) -> Void)?
    var requestAccessibility: (() -> Void)?
    var addFiles: (([URL]) -> Void)?
    var runTransform: ((TransformAction, ShelfItem) -> Void)?
    var removeShelfItem: ((ShelfItem) -> Void)?
    var clearShelf: (() -> Void)?
    var beginShelfDrag: (() -> Void)?
    /// Called when the panel expands, so permission state can be re-checked
    /// without polling for it.
    var onExpand: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var collapseWork: DispatchWorkItem?
    private static let collapsedSize = CGSize(width: 190, height: 30)

    init(audio: AudioOutputStore, hud: HUDStore, shelf: ShelfObservable) {
        self.audio = audio
        self.hud = hud
        self.shelf = shelf
        self.size = Self.collapsedSize

        // The expanded panel fits whatever is actually in it: the real device
        // count, plus the permission row only while it is relevant.
        Publishers.CombineLatest3($presentation, audio.$state, hud.$isReplacingSystemHUD)
            .map { presentation, state, replacing -> CGSize in
                guard presentation == .expanded else { return Self.collapsedSize }
                let rows = max(state.devices.count, 1)
                let permissionRow: CGFloat = replacing ? 0 : 34
                // 122 covers padding, both section labels, and the 50pt shelf strip.
                return CGSize(width: 360, height: 122 + CGFloat(rows) * 30 + permissionRow)
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
        // Debug level: this fires constantly, so it must not spam the log.
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
