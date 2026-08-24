import Carbon.HIToolbox
import AppKit

/// Registers the configurable global shortcuts (quick capture, show active
/// sticky, new sticky) and five fixed arrangement shortcuts using the Carbon Event
/// Manager's hotkey APIs — still the standard
/// way to get a system-wide shortcut in an AppKit app, works while sandboxed,
/// and (unlike an `NSEvent` global monitor) needs no Accessibility/Input
/// Monitoring permission, since it's registering the app's own response to a
/// key combo rather than observing other apps' keystrokes.
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    var onShowSticky: (() -> Void)?
    var onNewSticky: (() -> Void)?
    var onQuickCapture: (() -> Void)?
    var onOpenStickyPicker: (() -> Void)?
    var onArrange: ((StickyArrangement) -> Void)?
    var onSelectSticky: ((Int) -> Void)?

    private var showRef: EventHotKeyRef?
    private var newRef: EventHotKeyRef?
    private var quickCaptureRef: EventHotKeyRef?
    private var openStickyPickerRef: EventHotKeyRef?
    private var arrangementRefs: [StickyArrangement: EventHotKeyRef] = [:]
    private var stickySelectionRefs: [Int: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private static let signature: OSType = 0x546f_6479 // 'Tody'
    private let showID = EventHotKeyID(signature: GlobalHotKeyManager.signature, id: 1)
    private let newID = EventHotKeyID(signature: GlobalHotKeyManager.signature, id: 2)
    private let quickCaptureID = EventHotKeyID(signature: GlobalHotKeyManager.signature, id: 3)
    private let openStickyPickerID = EventHotKeyID(signature: GlobalHotKeyManager.signature, id: 4)
    private static let arrangementIDBase: UInt32 = 10
    private static let stickySelectionIDBase: UInt32 = 30

    private init() {
        installEventHandler()
    }

    /// Re-reads the current shortcuts from `AppSettings` and re-registers.
    /// Call after either shortcut is changed, and once at launch.
    func reregister() {
        unregisterAll()
        register(AppSettings.shared.showStickyShortcut, id: showID, into: &showRef)
        register(AppSettings.shared.newStickyShortcut, id: newID, into: &newRef)
        register(AppSettings.shared.quickCaptureShortcut, id: quickCaptureID, into: &quickCaptureRef)
        register(
            KeyCombo(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(controlKey)),
            id: openStickyPickerID,
            into: &openStickyPickerRef
        )
        registerArrangementShortcuts()
        registerStickySelectionShortcuts()
    }

    private func register(_ combo: KeyCombo, id: EventHotKeyID, into ref: inout EventHotKeyRef?) {
        RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    private func unregisterAll() {
        if let showRef { UnregisterEventHotKey(showRef) }
        if let newRef { UnregisterEventHotKey(newRef) }
        if let quickCaptureRef { UnregisterEventHotKey(quickCaptureRef) }
        if let openStickyPickerRef { UnregisterEventHotKey(openStickyPickerRef) }
        showRef = nil
        newRef = nil
        quickCaptureRef = nil
        openStickyPickerRef = nil
        for ref in arrangementRefs.values { UnregisterEventHotKey(ref) }
        arrangementRefs.removeAll()
        for ref in stickySelectionRefs.values { UnregisterEventHotKey(ref) }
        stickySelectionRefs.removeAll()
    }

    private func registerArrangementShortcuts() {
        let modifiers = UInt32(cmdKey | controlKey | optionKey)
        for (index, arrangement) in StickyArrangement.allCases.enumerated() {
            let id = EventHotKeyID(
                signature: Self.signature,
                id: Self.arrangementIDBase + UInt32(index)
            )
            var ref: EventHotKeyRef?
            RegisterEventHotKey(
                Self.keyCode(for: arrangement),
                modifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if let ref { arrangementRefs[arrangement] = ref }
        }
    }

    private func registerStickySelectionShortcuts() {
        let modifiers = UInt32(controlKey)
        for index in 0..<StickySelectionShortcut.maximumStickyCount {
            let id = EventHotKeyID(
                signature: Self.signature,
                id: Self.stickySelectionIDBase + UInt32(index)
            )
            var ref: EventHotKeyRef?
            RegisterEventHotKey(
                Self.keyCode(forStickyIndex: index),
                modifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if let ref { stickySelectionRefs[index] = ref }
        }
    }

    private static func keyCode(forStickyIndex index: Int) -> UInt32 {
        switch index {
        case 0: return UInt32(kVK_ANSI_1)
        case 1: return UInt32(kVK_ANSI_2)
        case 2: return UInt32(kVK_ANSI_3)
        case 3: return UInt32(kVK_ANSI_4)
        case 4: return UInt32(kVK_ANSI_5)
        case 5: return UInt32(kVK_ANSI_6)
        case 6: return UInt32(kVK_ANSI_7)
        case 7: return UInt32(kVK_ANSI_8)
        case 8: return UInt32(kVK_ANSI_9)
        default: return UInt32(kVK_ANSI_0)
        }
    }

    private static func keyCode(for arrangement: StickyArrangement) -> UInt32 {
        switch arrangement {
        case .grid: return UInt32(kVK_ANSI_G)
        case .horizontal: return UInt32(kVK_ANSI_H)
        case .vertical: return UInt32(kVK_ANSI_J)
        case .pile: return UInt32(kVK_ANSI_K)
        case .scatter: return UInt32(kVK_ANSI_L)
        }
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
                else if id == 3 { manager.onQuickCapture?() }
                else if id == 4 { manager.onOpenStickyPicker?() }
                else if id >= GlobalHotKeyManager.stickySelectionIDBase {
                    let index = Int(id - GlobalHotKeyManager.stickySelectionIDBase)
                    if (0..<StickySelectionShortcut.maximumStickyCount).contains(index) {
                        manager.onSelectSticky?(index)
                    }
                }
                else if id >= GlobalHotKeyManager.arrangementIDBase {
                    let index = Int(id - GlobalHotKeyManager.arrangementIDBase)
                    let arrangements = StickyArrangement.allCases
                    if arrangements.indices.contains(index) {
                        manager.onArrange?(arrangements[index])
                    }
                }
            }
            return noErr
        }, 1, &spec, selfPtr, &eventHandlerRef)
    }
}
