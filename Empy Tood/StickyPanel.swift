import AppKit

/// A borderless, rounded sticky window. It sits at the normal window level so
/// clicking another app covers it (not always-on-top), and it stays in the
/// Space where the user placed it. Resizing from any edge/corner is handled
/// here so it's smooth and never jumps. No shadow — the sticky is flat,
/// edge-to-edge paper.
final class StickyPanel: NSWindow {

    /// Required for a borderless window to accept text input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Shared with `StickyHostingView`'s cursor rects so the visible resize
    /// cursor and the actual draggable zone never drift apart.
    // A borderless window has no native frame to grab. Eight points was
    // technically hittable but too easy to miss horizontally, especially
    // beside editable SwiftUI content. Use a forgiving invisible gutter.
    static let resizeEdge: CGFloat = 14
    private let edge: CGFloat = StickyPanel.resizeEdge
    private let resizeMin = NSSize(width: 220, height: 300)

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        level = .normal
        // Keep each sticky assigned to its current Space. `.canJoinAllSpaces`
        // made every sticky follow the user across desktops; `.managed` uses
        // the normal macOS window/Spaces behavior instead.
        collectionBehavior = [.managed, .fullScreenNone]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    // MARK: - Edge / corner resize

    private struct Zone: OptionSet {
        let rawValue: Int
        static let left = Zone(rawValue: 1)
        static let right = Zone(rawValue: 2)
        static let bottom = Zone(rawValue: 4)
        static let top = Zone(rawValue: 8)
    }

    override func sendEvent(_ event: NSEvent) {
        let point = contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        if event.type == .leftMouseDown, let zone = resizeZone(at: point) {
            performResize(zone: zone)
            return // consume — don't let it start a background drag or hit a control
        }
        super.sendEvent(event)
    }

    private func resizeZone(at p: NSPoint) -> Zone? {
        guard let cv = contentView else { return nil }
        let b = cv.bounds
        var z: Zone = []
        if p.x <= edge { z.insert(.left) }
        if p.x >= b.width - edge { z.insert(.right) }
        if p.y <= edge { z.insert(.bottom) }       // window coords: y=0 at bottom
        if p.y >= b.height - edge { z.insert(.top) }
        return z.isEmpty ? nil : z
    }

    private func performResize(zone: Zone) {
        let startFrame = frame
        let startMouse = NSEvent.mouseLocation
        while let e = nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if e.type == .leftMouseUp { break }
            let cur = NSEvent.mouseLocation
            let dx = cur.x - startMouse.x
            let dy = cur.y - startMouse.y
            var f = startFrame

            if zone.contains(.right) {
                f.size.width = max(resizeMin.width, startFrame.width + dx)
            }
            if zone.contains(.left) {
                let newW = max(resizeMin.width, startFrame.width - dx)
                f.origin.x = startFrame.maxX - newW
                f.size.width = newW
            }
            if zone.contains(.top) {
                f.size.height = max(resizeMin.height, startFrame.height + dy)
            }
            if zone.contains(.bottom) {
                let newH = max(resizeMin.height, startFrame.height - dy)
                f.origin.y = startFrame.maxY - newH
                f.size.height = newH
            }
            // Keep the opposite edge anchored and repaint during the drag;
            // this makes left/right resizing track the pointer continuously.
            setFrame(f, display: true, animate: false)
        }
    }
}
