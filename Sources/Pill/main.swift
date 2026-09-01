import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Agent app: no Dock tile, no Cmd-Tab entry. Paired with LSUIElement in
// Info.plist so the behaviour holds however the binary is launched.
app.setActivationPolicy(.accessory)
app.run()
