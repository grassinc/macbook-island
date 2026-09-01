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
        let initial = NSRect(origin: .zero, size: model.size)
        self.panel = PillPanel(contentRect: initial)

        let host = PillHostingView(rootView: PillRootView(model: model, audio: model.audio, hud: model.hud, shelf: model.shelf))
        host.frame = initial
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        observeSize()
        observeScreenChanges()
    }

    func show() {
        setFrame(size: model.size, animated: false)
        panel.orderFrontRegardless()
    }

    // MARK: - Reacting to state

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
    private func applySize(_ target: CGSize) {
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
        let origin = PillGeometry.origin(forSize: size, onScreen: screen.frame, topInset: topInset)
        let frame = NSRect(origin: origin, size: size)

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
