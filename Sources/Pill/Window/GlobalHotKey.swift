import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey.
///
/// Carbon's `RegisterEventHotKey` is used rather than a `CGEventTap` because it
/// needs **no Accessibility permission** — the user should be able to recentre
/// the pill without granting anything. It is old API, but it is the only
/// permission-free route to a global shortcut and Apple still ships it.
@MainActor
final class GlobalHotKey {

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(cmdKey)`.
    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.id = Self.nextID
        Self.nextID += 1
        Self.registry[id] = self
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Carbon delivers this on the main thread.
            MainActor.assumeIsolated { GlobalHotKey.registry[hotKeyID.id]?.action() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x50494C4C), id: id)   // 'PILL'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    /// Explicit rather than `deinit`: Swift 6 will not let a nonisolated deinit
    /// touch main-actor state, and these Carbon handles are main-actor bound.
    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        Self.registry[id] = nil
    }
}
