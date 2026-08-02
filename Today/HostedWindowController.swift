import AppKit
import SwiftUI

/// A titled, resizable window hosting a SwiftUI view — used for Home,
/// Settings, and Onboarding, which (unlike the borderless sticky panels)
/// are regular app windows.
@MainActor
final class HostedWindowController<Content: View>: NSWindowController {
    private var keyMonitor: Any?

    /// `hidesTitleBar`: no title-bar chrome at all — no strip, no title
    /// text, no traffic lights. Keeps `.titled` under the hood (just
    /// visually suppressed) rather than going `.borderless`, so native
    /// drag-to-move and edge/corner resize both keep working for free —
    /// a truly borderless window loses that and needs the sticky panels'
    /// custom resize logic to get it back, which isn't worth it here.
    convenience init(title: String, size: NSSize, resizable: Bool = true, hidesTitleBar: Bool = false, content: Content) {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { styleMask.insert(.resizable) }
        if hidesTitleBar { styleMask.insert(.fullSizeContentView) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false // we reuse/reshow the same controller rather than recreating it
        window.contentView = NSHostingView(rootView: content)
        self.init(window: window)

        if hidesTitleBar {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true // no title-bar strip left to drag from
            // Traffic lights stay visible (just floating over the content,
            // no bar behind them — the standard pattern for chrome-free
            // windows) so there's always an obvious, discoverable way to
            // close the window, not just ⌘W.

            // This app has no main menu bar (it's .accessory) to route ⌘W
            // automatically, so it's handled here too, same reasoning as
            // the stickies' own ⌘N/⌘D — belt and suspenders with the
            // now-visible close button.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window,
                      event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w"
                else { return event }
                self.window?.orderOut(nil)
                return nil
            }
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
