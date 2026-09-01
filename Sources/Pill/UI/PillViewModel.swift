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

    /// Set by the app so the view can act without knowing about modules.
    var selectDevice: ((AudioOutputDevice) -> Void)?
    var requestAccessibility: (() -> Void)?
    /// Called when the panel expands, so permission state can be re-checked
    /// without polling for it.
    var onExpand: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private static let collapsedSize = CGSize(width: 190, height: 30)

    init(audio: AudioOutputStore, hud: HUDStore) {
        self.audio = audio
        self.hud = hud
        self.size = Self.collapsedSize

        // The expanded panel fits whatever is actually in it: the real device
        // count, plus the permission row only while it is relevant.
        Publishers.CombineLatest3($presentation, audio.$state, hud.$isReplacingSystemHUD)
            .map { presentation, state, replacing -> CGSize in
                guard presentation == .expanded else { return Self.collapsedSize }
                let rows = max(state.devices.count, 1)
                let permissionRow: CGFloat = replacing ? 0 : 34
                return CGSize(width: 320, height: 52 + CGFloat(rows) * 30 + permissionRow)
            }
            .removeDuplicates()
            .assign(to: \.size, on: self)
            .store(in: &cancellables)
    }

    func setHovered(_ hovered: Bool) {
        presentation = hovered ? .expanded : .collapsed
        if hovered { onExpand?() }
    }

    func setActivity(_ activity: Activity?) {
        self.activity = activity
    }
}
