import AppKit
import Carbon.HIToolbox
import SwiftUI
import Combine
import PillCore

/// Owns the panel and keeps its frame in step with what the pill is showing.
///
/// The panel is deliberately sized to the *current* presentation rather than
/// left at maximum size. A permanently expanded transparent window would
/// swallow menu-bar clicks around the pill, which is the fastest way to make a
/// utility like this infuriating.
@MainActor
final class PillWindowController {

    private let panel: PillPanel
    private let model: PillViewModel
    private var cancellables = Set<AnyCancellable>()
    private var shrinkWork: DispatchWorkItem?
    private var applyWork: DispatchWorkItem?
    private var pointerMonitor: Any?
    private var moveObserver: NSObjectProtocol?
    private var resetHotKey: GlobalHotKey?
    /// The last frame WE set. Compared against, rather than using a flag with
    /// async clearing: the move notification races the flag, and our own
    /// repositioning was being recorded as a user drag.
    private var lastProgrammaticFrame: NSRect = .zero
    private var placement: PillPlacement?

    /// Gap between the top of the screen and the pill.
    private let topInset: CGFloat = 2
    /// A few points of slack so the pill does not snap shut when the pointer
    /// grazes the very edge on its way to a control.
    private let exitSlack: CGFloat = 6

    init(model: PillViewModel) {
        self.model = model
        let initial = NSRect(origin: .zero, size: model.size)
        self.panel = PillPanel(contentRect: initial)

        let host = PillHostingView(rootView: PillRootView(model: model, audio: model.audio, hud: model.hud,
                                     shelf: model.shelf, battery: model.battery,
                                     thermal: model.thermal, timer: model.timer,
                                     calendar: model.calendar, privacy: model.privacy,
                                     nowPlaying: model.nowPlaying,
                                     network: model.network,
                                     bluetooth: model.bluetooth,
                                     actions: model.actions))
        host.frame = initial
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        placement = PlacementStore.load()

        observeSize()
        observeShelfHover()
        observeScreenChanges()
        observePresentationForPointerTracking()
        observeUserDrags()
        installResetHotKey()
        model.pointerIsOverPanel = { [weak self] in
            guard let self else { return false }
            return self.panel.frame
                .insetBy(dx: -self.exitSlack, dy: -self.exitSlack)
                .contains(NSEvent.mouseLocation)
        }
    }

    func show() {
        setFrame(size: model.size, animated: false)
        panel.orderFrontRegardless()
        // The panel is created at the origin and then moved into place. If the
        // pointer happened to be where it was born, SwiftUI reports a hover that
        // never gets a matching exit, leaving the pill stuck open until the
        // mouse next moves. Settle the state explicitly instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.collapseIfPointerLeft()
        }
    }

    // MARK: - Reacting to state

    /// A drag that starts on a shelf tile must drag the file, not the island.
    ///
    /// `isMovableByWindowBackground` is handled by AppKit before the event
    /// reaches any subview, so it has to be switched off in advance — by the
    /// time the drag begins it is already too late to decide.
    private func observeShelfHover() {
        model.shelf.$hoveredTileID
            .map { $0 == nil }
            .removeDuplicates()
            .sink { [weak self] movable in
                self?.panel.isMovableByWindowBackground = movable
                Log.activity.debug("window drag \(movable ? "enabled" : "disabled", privacy: .public)")
            }
            .store(in: &cancellables)
    }

    private func observeSize() {
        model.$size
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] size in self?.applySize(size) }
            .store(in: &cancellables)
    }

    /// Growing happens immediately so expanding content is never clipped by a
    /// too-small window. Shrinking waits for the collapse animation to finish,
    /// for the same reason in reverse. Both are one-shot work items, so the idle
    /// path schedules nothing.
    /// Size arrives in two parts — the width when the presentation flips, then
    /// the measured height once SwiftUI has laid out. Applying each separately
    /// animated the panel twice, which reads as a stutter. Coalescing within a
    /// single run-loop turn makes it one movement.
    private func applySize(_ target: CGSize) {
        applyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitSize(target) }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
    }

    private func commitSize(_ target: CGSize) {
        shrinkWork?.cancel()
        shrinkWork = nil

        let current = panel.frame.size
        if target.width >= current.width && target.height >= current.height {
            setFrame(size: target, animated: true)
        } else {
            let work = DispatchWorkItem { [weak self] in self?.setFrame(size: target, animated: true) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: work)
        }
    }

    private func setFrame(size: CGSize, animated: Bool) {
        guard let screen = targetScreen() else { return }

        // A user-chosen placement wins; otherwise fall back to top centre so the
        // pill keeps following display changes until it is deliberately moved.
        let origin: CGPoint
        if let placement {
            let safe = PillGeometry.clamp(placement, forSize: size, onScreen: screen.frame)
            origin = PillGeometry.origin(forSize: size, onScreen: screen.frame, placement: safe)
        } else {
            origin = PillGeometry.origin(forSize: size, onScreen: screen.frame, topInset: topInset)
        }
        let frame = NSRect(origin: origin, size: size)

        lastProgrammaticFrame = frame

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - Pointer tracking

    /// Closing is driven by where the pointer actually is, not by SwiftUI's
    /// hover events.
    ///
    /// `.onHover` is reliable enough for opening, but not for closing: the panel
    /// resizes underneath the pointer, and when the window shrinks away from the
    /// cursor AppKit may deliver no exit event at all — leaving the pill stuck
    /// open. Watching the real pointer position removes the guesswork.
    ///
    /// The monitor is installed only while the panel is open, so nothing is
    /// observed at idle. Mouse events need no Accessibility permission.
    private func observePresentationForPointerTracking() {
        model.$presentation
            .removeDuplicates()
            .sink { [weak self] presentation in
                guard let self else { return }
                presentation == .expanded ? self.startPointerTracking() : self.stopPointerTracking()
            }
            .store(in: &cancellables)
    }

    private func startPointerTracking() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapseIfPointerLeft() }
        }
    }

    private func stopPointerTracking() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
    }


    private func collapseIfPointerLeft() {
        let generous = panel.frame.insetBy(dx: -exitSlack, dy: -exitSlack)
        guard !generous.contains(NSEvent.mouseLocation) else { return }
        model.setHovered(false)
    }

    // MARK: - User dragging and reset

    private func observeUserDrags() {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordUserPlacement() }
        }
    }

    private func recordUserPlacement() {
        // A user drag means the primary button is down. Our own repositioning
        // animates, and every intermediate frame fires didMove too — comparing
        // frames alone is not enough, because intermediate frames match nothing.
        // Button state is the one signal only a real drag produces.
        guard NSEvent.pressedMouseButtons & 1 == 1 else { return }
        guard let screen = targetScreen() else { return }
        let frame = panel.frame
        guard !frame.equalTo(lastProgrammaticFrame) else { return }
        let moved = PillPlacement(centerX: frame.midX,
                                  topInset: screen.frame.maxY - frame.maxY)
        placement = PillGeometry.clamp(moved, forSize: frame.size, onScreen: screen.frame)
        PlacementStore.save(placement!)
        Log.activity.notice("pill moved to centerX=\(self.placement!.centerX, privacy: .public) topInset=\(self.placement!.topInset, privacy: .public)")
    }

    /// Cmd-/ returns the pill to its default spot. Registered through Carbon so
    /// it needs no Accessibility permission.
    private func installResetHotKey() {
        resetHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_Slash), modifiers: UInt32(cmdKey)) { [weak self] in
            self?.resetPlacement()
        }
    }

    func resetPlacement() {
        placement = nil
        PlacementStore.reset()
        setFrame(size: model.size, animated: true)
        Log.activity.notice("pill placement reset to default")
    }

    // MARK: - Screen changes

    private func observeScreenChanges() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.setFrame(size: self.model.size, animated: false)
            }
            .store(in: &cancellables)
    }

    /// The screen that owns the menu bar: the one containing the origin.
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }
}
