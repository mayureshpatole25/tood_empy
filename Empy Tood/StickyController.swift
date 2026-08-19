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
    private var pendingCaretLocation: Int?
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

        // Persist on any model mutation. Checklist overflow is handled by
        // its own scroll view, so typing never changes the window's size.
        model.onChange = { [weak manager] in
            manager?.scheduleSave()
        }

        if model.isVisible { show() }

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

        // SwiftUI's TextField consumes Return/Delete for its own editing
        // before onKeyPress can reliably inspect the AppKit caret, so edits
        // that cross the title/item boundary are caught here.
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
                self.requestClose() // asks Archive/Delete/Cancel, same as the X button
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

            // When the sticky is active but no text field owns the caret,
            // Return resumes editing at the end of the last checklist item.
            // A collapsed caret is safer than selecting the row: the next
            // character appends instead of unexpectedly replacing its text.
            if (event.keyCode == 36 || event.keyCode == 76),
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               !(self.panel.firstResponder is NSTextView) {
                self.model.onRequestLastItemFocus?()
                return nil
            }

            // Cross the title/first-row boundary with left/right only when
            // the caret is already at the corresponding text boundary.
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               let editor = self.panel.firstResponder as? NSTextView,
               editor.selectedRange().length == 0 {
                let caret = editor.selectedRange().location
                let length = (editor.string as NSString).length

                // Treat the title like the first block in the checklist:
                // Return splits at the caret and moves the suffix into a row.
                if (event.keyCode == 36 || event.keyCode == 76), self.model.isTitleFocused {
                    self.model.onSplitTitle?(caret)
                    return nil
                }

                // At the start of a row, Backspace joins it to the preceding
                // row (or to the title when this is the first item).
                if event.keyCode == 51, let id = self.model.focusedItemID, caret == 0 {
                    self.model.onMergeItemBackward?(id)
                    return nil
                }

                if event.keyCode == 124, self.model.isTitleFocused, caret == length {
                    self.model.onRequestFirstItemFocus?()
                    return nil
                }
                if event.keyCode == 123,
                   self.model.focusedItemID == self.model.orderedItems.first?.id,
                   caret == 0 {
                    self.model.onRequestTitleFocus?()
                    return nil
                }
            }

            return event
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
                guard let self, let editor = note.object as? NSTextView,
                      editor.window === self.panel
                else { return }

                self.applySelectionStyle(to: editor)

                guard let requestedLocation = self.pendingCaretLocation else { return }
                self.pendingCaretLocation = nil
                let length = (editor.string as NSString).length
                let caret = NSRange(location: min(requestedLocation, length), length: 0)
                if editor.selectedRange() != caret { editor.setSelectedRange(caret) }
            }
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
        if let deminiaturizeObserver { NotificationCenter.default.removeObserver(deminiaturizeObserver) }
    }

    /// Call right before programmatically moving focus between fields. AppKit
    /// selects the destination text automatically; this replaces that with a
    /// caret at the semantic join/split point before it is drawn.
    func placeCaretOnNextFocus(atUTF16Offset offset: Int) {
        pendingCaretLocation = offset
    }

    /// Keeps text selection visually native to the sticky instead of using
    /// macOS's neutral grey/accent highlight. Blending toward black preserves
    /// the paper's hue; alpha keeps the selected text comfortably readable.
    private func applySelectionStyle(to editor: NSTextView) {
        let paper = NSColor(model.color.paper)
        let darkerPaper = paper.blended(withFraction: 0.30, of: .black) ?? paper
        let background = darkerPaper.withAlphaComponent(0.50)
        var attributes = editor.selectedTextAttributes
        guard attributes[.backgroundColor] as? NSColor != background else { return }
        attributes[.backgroundColor] = background
        editor.selectedTextAttributes = attributes
    }

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

    // MARK: - Actions surfaced to the SwiftUI content

    func requestNewSticky() { manager?.newSticky() }

    /// Genie-effect minimizes to the Dock, same as any other window —
    /// unlike closing, this doesn't delete the sticky.
    func minimizeSticky() { panel.miniaturize(nil) }

    /// Close only hides this window. The sticky and all of its contents stay
    /// in the manager and on disk, so it can be opened again from Home.
    func closeSticky() { hide() }

    /// Every way of closing a sticky (the X button, ⌘D, the context menu's
    /// "Delete Sticky") routes through here rather than deleting outright.
    /// Respects `AppSettings.closeBehavior` first, so someone who'd rather
    /// skip the dialog entirely (set from the status menu, or from the
    /// dialog's own "Don't ask me again" checkbox below) never sees it.
    /// Otherwise: same NSAlert pattern as the status menu's "Delete All",
    /// offering Archive (keeps a full copy as a browsable memory) or Delete
    /// (gone for good) instead of silently assuming which one you meant.
    func requestClose() {
        switch AppSettings.shared.closeBehavior {
        case .alwaysArchive: manager?.archive(model.id); return
        case .alwaysDelete: manager?.remove(model.id); return
        case .alwaysAsk: break
        }

        let alert = NSAlert()
        alert.messageText = "Archive or delete this sticky?"
        alert.informativeText = "Archiving keeps it as a memory you can look back on later. Deleting removes it for good, and can't be undone."
        alert.addButton(withTitle: "Archive")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].hasDestructiveAction = true
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask me again"

        let response = alert.runModal()
        let alwaysDoThis = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn:
            manager?.archive(model.id)
            if alwaysDoThis { AppSettings.shared.closeBehavior = .alwaysArchive }
        case .alertSecondButtonReturn:
            manager?.remove(model.id)
            if alwaysDoThis { AppSettings.shared.closeBehavior = .alwaysDelete }
        default: break // Cancel — leave closeBehavior alone either way
        }
    }

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
