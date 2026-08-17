import AppKit

/// A borderless, rounded sticky window. It sits at the normal window level so
/// clicking another app covers it (not always-on-top), but it's available on
/// every Space. Resizing from any edge/corner is handled here so it's smooth
/// and never jumps. No shadow — the sticky is flat, edge-to-edge paper.
final class StickyPanel: NSWindow {

    /// Required for a borderless window to accept text input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Shared with `StickyHostingView`'s cursor rects so the visible resize
    /// cursor and the actual draggable zone never drift apart.
    static let resizeEdge: CGFloat = 16
    private let edge: CGFloat = StickyPanel.resizeEdge
    private let resizeMin = NSSize(width: 220, height: 300)
    private var resizeSession: ResizeSession?

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        level = .normal
        // .canJoinAllSpaces alone was still showing up over another app's
        // full-screen Space (e.g. full-screen YouTube) — .fullScreenNone
        // explicitly opts the window out of full-screen Spaces entirely.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]

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

    private struct ResizeSession {
        let zone: Zone
        let frame: NSRect
        let mouse: NSPoint
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let point = contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            if let zone = resizeZone(at: point) {
                resizeSession = ResizeSession(zone: zone, frame: frame, mouse: NSEvent.mouseLocation)
                return // don't let the resize gesture become a background drag
            }
        case .leftMouseDragged:
            if let session = resizeSession {
                updateResize(session, mouse: NSEvent.mouseLocation)
                return
            }
        case .leftMouseUp:
            if let session = resizeSession {
                updateResize(session, mouse: NSEvent.mouseLocation)
                resizeSession = nil
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func resizeZone(at p: NSPoint) -> Zone? {
        guard let cv = contentView else { return nil }
        let b = cv.bounds
        var z: Zone = []
        if p.x <= b.minX + edge { z.insert(.left) }
        if p.x >= b.maxX - edge { z.insert(.right) }
        if p.y <= b.minY + edge { z.insert(.bottom) }
        if p.y >= b.maxY - edge { z.insert(.top) }
        return z.isEmpty ? nil : z
    }

    private func updateResize(_ session: ResizeSession, mouse: NSPoint) {
        let dx = mouse.x - session.mouse.x
        let dy = mouse.y - session.mouse.y
        let start = session.frame
        var next = start

        if session.zone.contains(.right) {
            next.size.width = max(resizeMin.width, start.width + dx)
        }
        if session.zone.contains(.left) {
            let width = max(resizeMin.width, start.width - dx)
            next.origin.x = start.maxX - width
            next.size.width = width
        }
        if session.zone.contains(.top) {
            next.size.height = max(resizeMin.height, start.height + dy)
        }
        if session.zone.contains(.bottom) {
            let height = max(resizeMin.height, start.height - dy)
            next.origin.y = start.maxY - height
            next.size.height = height
        }

        setFrame(next, display: true, animate: false)
    }
}
