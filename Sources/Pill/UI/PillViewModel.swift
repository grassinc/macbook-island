import SwiftUI
import PillCore

/// What the pill is currently showing, and how big it therefore needs to be.
enum PillPresentation: Equatable {
    case collapsed
    case expanded

    var size: CGSize {
        switch self {
        case .collapsed: CGSize(width: 190, height: 30)
        case .expanded:  CGSize(width: 340, height: 96)
        }
    }
}

@MainActor
final class PillViewModel: ObservableObject {
    @Published private(set) var presentation: PillPresentation = .collapsed
    @Published private(set) var activity: Activity?

    /// Set by the window controller when the pointer enters or leaves the panel.
    func setHovered(_ hovered: Bool) {
        presentation = hovered ? .expanded : .collapsed
    }

    func setActivity(_ activity: Activity?) {
        self.activity = activity
    }
}
