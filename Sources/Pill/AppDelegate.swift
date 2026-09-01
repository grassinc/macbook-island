import AppKit
import PillCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PillWindowController?
    private let model = PillViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PillWindowController(model: model)
        controller.show()
        self.controller = controller
    }
}
