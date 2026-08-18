import Carbon.HIToolbox
import AppKit

/// Registers the two configurable global shortcuts (show active sticky, new
/// sticky) using the Carbon Event Manager's hotkey APIs — still the standard
/// way to get a system-wide shortcut in an AppKit app, works while sandboxed,
/// and (unlike an `NSEvent` global monitor) needs no Accessibility/Input
/// Monitoring permission, since it's registering the app's own response to a
/// key combo rather than observing other apps' keystrokes.
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    var onShowSticky: (() -> Void)?
    var onNewSticky: (() -> Void)?

    private var showRef: EventHotKeyRef?
    private var newRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let signature: OSType = 0x546f_6479 // 'Tody'
    private let showID = EventHotKeyID(signature: GlobalHotKeyManager.signature, id: 1)
    private let newID = EventHotKeyID(signature: GlobalHotKeyManager.signature, id: 2)

    private init() {
        installEventHandler()
    }

    /// Re-reads the current shortcuts from `AppSettings` and re-registers.
    /// Call after either shortcut is changed, and once at launch.
    func reregister() {
        unregisterAll()
        register(AppSettings.shared.showStickyShortcut, id: showID, into: &showRef)
        register(AppSettings.shared.newStickyShortcut, id: newID, into: &newRef)
    }

    private func register(_ combo: KeyCombo, id: EventHotKeyID, into ref: inout EventHotKeyRef?) {
        RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    private func unregisterAll() {
        if let showRef { UnregisterEventHotKey(showRef) }
        if let newRef { UnregisterEventHotKey(newRef) }
        showRef = nil
        newRef = nil
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hkID.id
            Task { @MainActor in
                if id == 1 { manager.onShowSticky?() }
                else if id == 2 { manager.onNewSticky?() }
            }
            return noErr
        }, 1, &spec, selfPtr, &eventHandlerRef)
    }
}
