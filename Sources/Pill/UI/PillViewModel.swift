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

    /// Set by the app so the view can act without knowing about modules.
    var selectDevice: ((AudioOutputDevice) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    private static let collapsedSize = CGSize(width: 190, height: 30)

    init(audio: AudioOutputStore) {
        self.audio = audio
        self.size = Self.collapsedSize

        // The expanded panel has to fit however many outputs exist right now,
        // so its height is derived rather than hard-coded.
        Publishers.CombineLatest($presentation, audio.$state)
            .map { presentation, state -> CGSize in
                switch presentation {
                case .collapsed:
                    return Self.collapsedSize
                case .expanded:
                    let rows = max(state.devices.count, 1)
                    return CGSize(width: 320, height: 52 + CGFloat(rows) * 30)
                }
            }
            .removeDuplicates()
            .assign(to: \.size, on: self)
            .store(in: &cancellables)
    }

    func setHovered(_ hovered: Bool) {
        presentation = hovered ? .expanded : .collapsed
    }

    func setActivity(_ activity: Activity?) {
        self.activity = activity
    }
}
