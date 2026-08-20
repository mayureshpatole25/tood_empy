import AppKit
import SwiftUI

/// A titled, resizable window hosting a SwiftUI view — used for Home,
/// Settings, and Onboarding, which (unlike the borderless sticky panels)
/// are regular app windows.
@MainActor
final class HostedWindowController<Content: View>: NSWindowController, NSWindowDelegate {
    private var keyMonitor: Any?
    private var deminiaturizeObserver: NSObjectProtocol?
    private var minimumFrameSize: NSSize?
    private var maximumFrameSize: NSSize?
    private var isRepairingFrame = false

    /// `hidesTitleBar`: no title-bar chrome at all — no strip, no title
    /// text, no traffic lights. Keeps `.titled` under the hood (just
    /// visually suppressed) rather than going `.borderless`, so native
    /// drag-to-move and edge/corner resize both keep working for free —
    /// a truly borderless window loses that and needs the sticky panels'
    /// custom resize logic to get it back, which isn't worth it here.
    convenience init(
        title: String,
        size: NSSize,
        minimumSize: NSSize? = nil,
        resizable: Bool = true,
        hidesTitleBar: Bool = false,
        content: Content
    ) {
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
        let hosting = NSHostingView(rootView: content)
        // By default NSHostingView writes its measured SwiftUI min/max back to
        // the containing window. That created a second sizing owner and could
        // silently replace the explicit AppKit limits below.
        hosting.sizingOptions = []
        hosting.frame = window.contentView?.bounds
            ?? NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        let effectiveMinimumContentSize = minimumSize ?? (resizable ? nil : size)
        if let effectiveMinimumContentSize {
            window.contentMinSize = effectiveMinimumContentSize
        }
        if !resizable {
            window.contentMaxSize = size
        }
        window.center()
        window.isReleasedWhenClosed = false // we reuse/reshow the same controller rather than recreating it
        self.init(window: window)

        if let effectiveMinimumContentSize {
            minimumFrameSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: effectiveMinimumContentSize)
            ).size
        }
        if !resizable {
            maximumFrameSize = window.frame.size
        }
        window.delegate = self

        // NSHostingView doesn't always repaint its full bounds after the
        // genie-effect restore from the Dock — it can come back visually
        // clipped to a smaller size until something else forces a layout
        // pass. Nudging the content view here (rather than the window
        // itself, which is already the right size) fixes that without a
        // visible resize flicker.
        deminiaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main
        ) { [weak window] _ in
            guard let contentView = window?.contentView else { return }
            contentView.needsLayout = true
            contentView.layoutSubtreeIfNeeded()
            contentView.needsDisplay = true
        }

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
        if let deminiaturizeObserver { NotificationCenter.default.removeObserver(deminiaturizeObserver) }
    }

    func present() {
        repairFrameIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        constrainedFrameSize(frameSize)
    }

    func windowDidResize(_ notification: Notification) {
        repairFrameIfNeeded()
    }

    private func constrainedFrameSize(_ proposed: NSSize) -> NSSize {
        var result = proposed
        if let minimumFrameSize {
            result.width = max(result.width, minimumFrameSize.width)
            result.height = max(result.height, minimumFrameSize.height)
        }
        if let maximumFrameSize {
            result.width = min(result.width, maximumFrameSize.width)
            result.height = min(result.height, maximumFrameSize.height)
        }
        return result
    }

    /// Accessibility APIs and `setFrame(_:display:)` bypass AppKit's declared
    /// min/max sizes, just like they do for the sticky panels. Repair those
    /// paths after the notification while preserving the window's top edge.
    private func repairFrameIfNeeded() {
        guard !isRepairingFrame, let window else { return }
        let current = window.frame
        let constrainedSize = constrainedFrameSize(current.size)
        guard constrainedSize != current.size else { return }

        var repaired = current
        repaired.size = constrainedSize
        repaired.origin.y = current.maxY - constrainedSize.height
        isRepairingFrame = true
        window.setFrame(repaired, display: true)
        isRepairingFrame = false
    }
}
