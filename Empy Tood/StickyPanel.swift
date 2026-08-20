import AppKit

/// A borderless, rounded sticky window. It sits at the normal window level so
/// clicking another app covers it (not always-on-top), and it stays in the
/// Space where the user placed it. Width is fixed at the default while AppKit
/// retains native vertical resizing. The SwiftUI paper is the only corner
/// mask, so all four corners stay identical. No shadow — the sticky is flat,
/// edge-to-edge paper.
final class StickyPanel: NSWindow {

    private static let panelStyleMask: NSWindow.StyleMask = [
        .borderless, .resizable, .miniaturizable,
    ]

    /// Supplied by StickyController to restore a blinking text caret after a
    /// click leaves the key sticky without a text field as first responder.
    var ensureTextFocus: (() -> Void)?

    /// Required for a borderless window to accept text input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Covers the calm header through the date's baseline, stopping before
    /// the editable title. AppKit coordinates are measured from the bottom,
    /// so `isWindowDragRegion` converts this to a distance from the top.
    private let windowDragRegionDepth: CGFloat = 70

    static let defaultSize = StickyWindowGeometry.defaultSize
    static let minimumSize = StickyWindowGeometry.minimumSize

    init(frameRect: NSRect) {
        // Persistence stores frame coordinates. Converting explicitly keeps
        // that contract correct if the window style ever gains decorations;
        // for today's borderless panel this conversion is an identity.
        let contentRect = NSWindow.contentRect(
            forFrameRect: frameRect,
            styleMask: Self.panelStyleMask
        )
        super.init(
            contentRect: contentRect,
            styleMask: Self.panelStyleMask,
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
        minSize = Self.minimumSize
        maxSize = NSSize(
            width: StickyWindowGeometry.fixedWidth,
            height: StickyWindowGeometry.maximumSafeHeight
        )

        // Window movement is routed explicitly in `sendEvent`. Letting
        // AppKit treat the whole paper as movable steals drag gestures from
        // checklist controls before SwiftUI can recognize them.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let contentPoint = contentView?.convert(event.locationInWindow, from: nil)
                ?? event.locationInWindow
            if isWindowDragRegion(contentPoint) {
                performDrag(with: event)
                restoreTextFocusAfterMouseEvent()
                return
            }
        }

        super.sendEvent(event)
        if event.type == .leftMouseDown { restoreTextFocusAfterMouseEvent() }
    }

    private func restoreTextFocusAfterMouseEvent() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isKeyWindow, !(self.firstResponder is NSTextView) else { return }
            self.ensureTextFocus?()
        }
    }

    private func isWindowDragRegion(_ point: NSPoint) -> Bool {
        guard let contentView else { return false }
        guard contentView.bounds.contains(point) else { return false }
        // Let AppKit own its resize perimeter. Without this guard the custom
        // header drag swallows top-edge and top-corner resize mouse-downs and
        // moves the sticky instead.
        guard !StickyWindowGeometry.isInNativeResizePerimeter(
            point,
            bounds: contentView.bounds
        ) else { return false }

        // NSHostingView uses a flipped coordinate system (y grows downward),
        // unlike a traditional AppKit content view. Normalize the point to a
        // visual distance from the top so the bottom toolbar can never be
        // mistaken for the draggable header.
        let distanceFromTop = contentView.isFlipped
            ? point.y - contentView.bounds.minY
            : contentView.bounds.maxY - point.y
        guard distanceFromTop <= windowDragRegionDepth else { return false }

        // Keep the close/minimize controls interactive inside the otherwise
        // draggable header. Their visual centers live 24pt from the top and
        // start at the shared 24pt content inset.
        let isOverTrafficLights = (20...72).contains(point.x)
            && (16...44).contains(distanceFromTop)
        return !isOverTrafficLights
    }

}
