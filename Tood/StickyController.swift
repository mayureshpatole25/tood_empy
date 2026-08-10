import AppKit
import SwiftUI

/// Owns one sticky: its window, its SwiftUI content, and the wiring that keeps
/// the model's frame in sync and persists changes.
@MainActor
final class StickyController: NSObject, NSWindowDelegate {
    let model: StickyModel
    let panel: StickyPanel
    private weak var manager: StickyManager?
    private var keyMonitor: Any?
    private var selectionObserver: NSObjectProtocol?
    private var deminiaturizeObserver: NSObjectProtocol?
    private var suppressNextAutoSelect = false
    private var hosting: StickyHostingView!

    init(model: StickyModel, manager: StickyManager) {
        self.model = model
        self.manager = manager
        self.panel = StickyPanel(frame: model.frame)
        super.init()

        let root = StickyRootView(model: model, controller: self)
        hosting = StickyHostingView(rootView: root)
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self

        // Persist on any model mutation (debounced by the manager), and
        // re-check whether the content now needs a taller window. Deferred a
        // tick so SwiftUI has actually re-laid-out the new content first.
        model.onChange = { [weak self, weak manager] in
            manager?.scheduleSave()
            DispatchQueue.main.async { self?.growToFitCurrentContent() }
        }

        if model.isVisible { show() }
        growToFitCurrentContent() // in case a restored sticky already overflows

        // Same NSHostingView restore glitch as the main window (see
        // HostedWindowController) — force a layout pass after the genie
        // effect brings the sticky back from the Dock.
        deminiaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification, object: panel, queue: .main
        ) { [weak hosting] _ in
            guard let hosting else { return }
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
            hosting.needsDisplay = true
        }

        // SwiftUI's TextField consumes the delete key for its own editing
        // before onKeyPress(.delete) ever sees it — even when the field is
        // empty — so backspace-deletes-empty-row has to be caught here.
        //
        // Also handles ⌘N and ⌘D here rather than relying on the status-bar
        // menu's key equivalent: this app has no main menu bar (it's
        // .accessory), so a menu item's key equivalent only ever fires
        // while the status menu is literally open — it's not a real global
        // shortcut. This makes ⌘N/⌘D work whenever a sticky window is
        // focused, which isn't fully global either, but doesn't require
        // Accessibility/Input Monitoring permission the way a true
        // system-wide hotkey would.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }

            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "n" {
                self.manager?.newSticky()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "d" {
                self.closeSticky() // deletes it — closing a sticky is always a delete in this app
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v",
               let focusedID = self.model.focusedItemID,
               let clipboard = NSPasteboard.general.string(forType: .string) {
                let lines = clipboard
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                // A single line is just a normal paste — only intercept
                // when there's actually something to split across rows.
                if lines.count > 1 {
                    self.model.onMultilinePaste?(lines, focusedID)
                    return nil
                }
            }

            guard event.keyCode == 51 /* delete */,
                  let id = self.model.focusedItemID,
                  let item = self.model.items.first(where: { $0.id == id }),
                  item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return event }
            self.model.onBackspaceEmptyRow?(id)
            return nil
        }

        // AppKit select-alls a field's text the instant it becomes first
        // responder. Correcting that a runloop tick later (e.g. via
        // DispatchQueue.main.async) still shows one flashed frame of the
        // selection first; catching the selection-change notification
        // itself lets us collapse it before anything is ever drawn.
        selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: nil, queue: nil
        ) { [weak self] note in
            // queue: nil guarantees synchronous delivery on the posting
            // thread, which for NSTextView selection changes is always main.
            MainActor.assumeIsolated {
                guard let self, self.suppressNextAutoSelect,
                      let editor = note.object as? NSTextView, editor.window === self.panel
                else { return }
                self.suppressNextAutoSelect = false
                let end = NSRange(location: (editor.string as NSString).length, length: 0)
                if editor.selectedRange() != end { editor.setSelectedRange(end) }
            }
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
        if let deminiaturizeObserver { NotificationCenter.default.removeObserver(deminiaturizeObserver) }
    }

    /// Call right before programmatically moving focus to a row, so the
    /// automatic select-all that follows gets collapsed to a plain caret.
    func armSelectionSuppression() { suppressNextAutoSelect = true }

    // MARK: - Window lifecycle

    func show() {
        model.isVisible = true
        panel.setFrame(model.frame, display: true)
        clampToScreen() // heals any off-screen frame from a past bug, or a screen that's since shrunk/disconnected
        panel.orderFront(nil) // normal ordering — other apps can cover it
    }

    /// Ensures the whole window frame sits within the visible screen area.
    private func clampToScreen() {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = panel.frame
        f.size.width = min(f.width, visible.width)
        f.size.height = min(f.height, visible.height)
        f.origin.x = min(max(f.origin.x, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.origin.y, visible.minY), visible.maxY - f.height)
        guard f != panel.frame else { return }
        panel.setFrame(f, display: true)
    }

    func hide() {
        model.isVisible = false
        panel.orderOut(nil)
        manager?.scheduleSave()
    }

    func bringToFront() {
        if !model.isVisible { model.isVisible = true }
        panel.makeKeyAndOrderFront(nil)
    }

    /// The global "show active sticky" shortcut: front the window, activate
    /// the app (it's `.accessory` — just ordering the window front doesn't
    /// steal keyboard focus from whatever app was frontmost), then move
    /// focus into the first unfinished row so typing works immediately.
    func focusForTyping() {
        bringToFront()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in self?.model.onRequestFocus?() }
    }

    /// Applies a new height, keeping the whole window on-screen: grows
    /// downward from the current top edge like before, but if that would
    /// run off the bottom of the screen, pins the bottom to the screen's
    /// bottom edge and grows upward instead — the sticky should never end
    /// up somewhere off-screen you can't get back to.
    private func applyHeight(_ height: CGFloat) {
        var f = panel.frame
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else {
            f.origin.y -= (height - f.height)
            f.size.height = height
            panel.setFrame(f, display: true)
            return
        }
        let clampedHeight = min(height, visible.height)
        var newOriginY = f.maxY - clampedHeight
        newOriginY = max(newOriginY, visible.minY)
        newOriginY = min(newOriginY, visible.maxY - clampedHeight)
        f.origin.y = newOriginY
        f.size.height = clampedHeight
        panel.setFrame(f, display: true)
    }

    /// Resizes the window to fit the checklist content. Uses
    /// NSHostingView.fittingSize (an AppKit-native "what height does this
    /// content actually need at its current width" query) rather than
    /// SwiftUI PreferenceKey plumbing, which turned out to under-report:
    /// content was measured after being silently compressed to whatever the
    /// window's current bounds already were.
    private func resizeToFitContent(allowShrink: Bool) {
        let needed = ceil(hosting.fittingSize.height)
        let delta = needed - panel.frame.height
        guard allowShrink ? abs(delta) > 0.5 : delta > 0.5 else { return }
        applyHeight(needed)
    }

    /// As items are added, so it never needs an internal scroll. Grow-only —
    /// never auto-shrinks, so removing items or a manual resize don't fight
    /// this.
    private func growToFitCurrentContent() { resizeToFitContent(allowShrink: false) }

    /// Collapsing/expanding the checklist (see StickyRootView) explicitly
    /// wants a shrink too, unlike the passive grow-as-you-type behavior.
    func recheckContentSize() {
        DispatchQueue.main.async { [weak self] in self?.resizeToFitContent(allowShrink: true) }
    }

    /// Grows by an estimated number of rows — used to reveal rows hidden
    /// behind "N more", or a row a keystroke just created past the current
    /// fit. The estimate needn't be exact: revealing more rows changes what
    /// SwiftUI renders, so the follow-up `recheckContentSize()` snaps the
    /// window to the precise fit once that's rendered.
    func growBy(rows: Int, estimatedRowHeight: CGFloat) {
        guard rows > 0 else { return }
        applyHeight(panel.frame.height + CGFloat(rows) * estimatedRowHeight)
        recheckContentSize()
    }

    /// Shrinks back to a compact height fitting `rows` rows — the
    /// checklist's "Show less" toggle. Same estimate-then-snap pattern as
    /// `growBy`: the rough analytical target can undershoot (which clipped
    /// the bottom toolbar), so `recheckContentSize()` corrects it against
    /// the real fitting size right after.
    func collapse(toRows rows: Int, rowHeight: CGFloat, chromeHeight: CGFloat) {
        applyHeight(ceil(chromeHeight + CGFloat(rows) * rowHeight))
        recheckContentSize()
    }

    // MARK: - Actions surfaced to the SwiftUI content

    func requestNewSticky() { manager?.newSticky() }

    /// Genie-effect minimizes to the Dock, same as any other window —
    /// unlike closing, this doesn't delete the sticky.
    func minimizeSticky() { panel.miniaturize(nil) }

    func deleteSticky() { manager?.remove(model.id) }

    /// Closing a sticky deletes it (it won't come back on reopen).
    func closeSticky() { manager?.remove(model.id) }

    // MARK: - NSWindowDelegate (frame sync)

    func windowDidMove(_ notification: Notification) { syncFrame() }
    func windowDidResize(_ notification: Notification) { syncFrame() }

    /// Tracks "most recently active" from a plain click too, not just
    /// programmatic `bringToFront()` — so the global shortcut jumps to
    /// whichever sticky you actually used last either way.
    func windowDidBecomeKey(_ notification: Notification) { manager?.noteActive(model.id) }

    private func syncFrame() {
        model.frame = panel.frame
        manager?.scheduleSave()
    }
}

/// Adds a resize cursor along the sticky's draggable edges. Plain
/// `NSHostingView` doesn't manage cursor rects at all, and AppKit only
/// recomputes them when it feels like it — after a *programmatic* resize
/// (`growBy`/`collapse`, not a live mouse drag) the old rects, sized for
/// the sticky's previous bounds, were left standing: the resize cursor
/// silently stopped appearing past wherever the sticky's height last
/// changed by hand, even though `StickyPanel`'s own hit-testing (computed
/// fresh on every click) kept resizing just fine. Forcing an invalidation
/// on every layout pass keeps the two in sync.
final class StickyHostingView: NSHostingView<StickyRootView> {
    override func resetCursorRects() {
        super.resetCursorRects()
        let edge = StickyPanel.resizeEdge
        let b = bounds
        addCursorRect(NSRect(x: 0, y: 0, width: edge, height: b.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.width - edge, y: 0, width: edge, height: b.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: 0, width: b.width, height: edge), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: b.height - edge, width: b.width, height: edge), cursor: .resizeUpDown)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }
}
