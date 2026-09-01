import AppKit
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

    /// Gap between the top of the screen and the pill.
    private let topInset: CGFloat = 2

    init(model: PillViewModel) {
        self.model = model
        let initial = NSRect(origin: .zero, size: model.presentation.size)
        self.panel = PillPanel(contentRect: initial)

        let host = NSHostingView(rootView: PillRootView(model: model))
        host.frame = initial
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        observePresentation()
        observeScreenChanges()
    }

    func show() {
        reposition(animated: false)
        panel.orderFrontRegardless()
    }

    // MARK: - Reacting to state

    private func observePresentation() {
        model.$presentation
            .removeDuplicates()
            .sink { [weak self] presentation in
                self?.applyPresentation(presentation)
            }
            .store(in: &cancellables)
    }

    /// Growing happens immediately so the expanding content is never clipped by
    /// a too-small window. Shrinking waits for the collapse animation to finish,
    /// for the same reason in reverse. The delay is a single one-shot work item,
    /// not a repeating timer — the idle path stays at zero scheduled work.
    private func applyPresentation(_ presentation: PillPresentation) {
        shrinkWork?.cancel()
        shrinkWork = nil

        let target = presentation.size
        let current = panel.frame.size

        if target.width >= current.width && target.height >= current.height {
            setFrame(size: target, animated: true)
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.setFrame(size: target, animated: true)
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: work)
        }
    }

    private func setFrame(size: CGSize, animated: Bool) {
        guard let screen = targetScreen() else { return }
        let origin = PillGeometry.origin(forSize: size,
                                         onScreen: screen.frame,
                                         topInset: topInset)
        let frame = NSRect(origin: origin, size: size)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func reposition(animated: Bool) {
        setFrame(size: model.presentation.size, animated: animated)
    }

    // MARK: - Screen changes

    private func observeScreenChanges() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition(animated: false) }
            .store(in: &cancellables)
    }

    /// The screen that owns the menu bar. `NSScreen.screens.first` is the
    /// display containing the origin, which is where the menu bar lives.
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }
}
