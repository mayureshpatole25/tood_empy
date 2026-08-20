import AppKit
import SwiftUI

enum StickyCaretEdge {
    case top
    case bottom
}

/// Owns one sticky: its window, its SwiftUI content, and the wiring that keeps
/// the model's frame in sync and persists changes.
@MainActor
final class StickyController: NSObject, NSWindowDelegate {
    let model: StickyModel
    let panel: StickyPanel
    private weak var manager: StickyManager?
    private let completionUndoManager = UndoManager()
    private var keyMonitor: Any?
    private var selectionObserver: NSObjectProtocol?
    private var deminiaturizeObserver: NSObjectProtocol?
    private enum PendingCaretPlacement {
        case offset(Int)
        case horizontal(screenX: CGFloat, edge: StickyCaretEdge)
    }

    private var pendingCaretPlacement: PendingCaretPlacement?
    private var hosting: NSHostingView<StickyRootView>!
    private var frameBeforeExpansion: NSRect?
    private var isRepairingFrame = false

    init(model: StickyModel, manager: StickyManager) {
        let persistedFrame = StickyWindowGeometry.persistedFrame(model.frame)
        // Both dimensions are now user-controlled, so an individually valid
        // width and height can still combine into an unsafe initial backing
        // allocation. Clamp to the owning display before NSWindow exists.
        let initialScreen = Self.bestScreen(for: persistedFrame)
        if let initialScreen {
            model.frame = StickyWindowGeometry.runtimeFrame(
                persistedFrame,
                visibleFrame: initialScreen.visibleFrame
            )
        } else {
            // A GUI session should always have a screen. Keep headless/test
            // launches bounded too instead of constructing a maximum-size
            // backing store when no trustworthy display geometry exists.
            model.frame = StickyWindowGeometry.runtimeFrame(
                persistedFrame,
                maximumSize: StickyWindowGeometry.defaultSize
            )
        }
        self.model = model
        self.manager = manager
        self.panel = StickyPanel(frameRect: model.frame)
        super.init()

        let root = StickyRootView(model: model, controller: self)
        hosting = NSHostingView(rootView: root)
        // The window owns both resizable dimensions. SwiftUI responds to the
        // available content size but never writes constraints back to AppKit.
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: panel.contentLayoutRect.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self
        panel.ensureTextFocus = { [weak self] in self?.ensureTextFocus() }
        updateWindowSizeLimits(for: panel.screen)

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
        // Also handles sticky-specific shortcuts here rather than relying
        // on the status-bar menu's key equivalent, which only fires while
        // that menu is open. These commands work whenever a sticky window
        // is focused without requiring Accessibility/Input Monitoring.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }

            let commandModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            let pressedKey = event.charactersIgnoringModifiers?.lowercased()
            if pressedKey == "z", commandModifiers == .command,
               self.completionUndoManager.canUndo {
                self.completionUndoManager.undo()
                return nil
            }
            if pressedKey == "z", commandModifiers == [.command, .shift],
               self.completionUndoManager.canRedo {
                self.completionUndoManager.redo()
                return nil
            }

            if pressedKey == "w", commandModifiers == .command {
                self.closeSticky()
                return nil
            }
            if (event.keyCode == 51 || event.keyCode == 117), commandModifiers == .command {
                self.requestClose()
                return nil
            }
            if event.keyCode == 126, commandModifiers == .command,
               let editor = self.panel.firstResponder as? NSTextView,
               editor.selectedRange().length == 0 {
                self.model.onMoveCaretToDocumentBoundary?(-1)
                return nil
            }
            if event.keyCode == 125, commandModifiers == .command,
               let editor = self.panel.firstResponder as? NSTextView,
               editor.selectedRange().length == 0 {
                self.model.onMoveCaretToDocumentBoundary?(1)
                return nil
            }

            if pressedKey == "n", commandModifiers == .command {
                self.manager?.newSticky()
                return nil
            }
            if pressedKey == "d", commandModifiers == .command {
                self.requestClose() // asks Archive/Delete/Cancel, same as the archive button
                return nil
            }
            if pressedKey == "v", commandModifiers == .command,
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

                // Let AppKit move naturally between wrapped visual lines.
                // At a field's top/bottom edge, continue into the adjacent
                // title/item while preserving the caret's screen-space x.
                if event.keyCode == 126, // up
                   self.isCaret(caret, on: .top, in: editor),
                   self.hasAdjacentTextField(direction: -1) {
                    let screenX = editor.firstRect(
                        forCharacterRange: NSRange(location: caret, length: 0),
                        actualRange: nil
                    ).minX
                    self.model.onMoveCaretVertically?(
                        self.model.isTitleFocused ? nil : self.model.focusedItemID,
                        -1,
                        screenX
                    )
                    return nil
                }
                if event.keyCode == 125, // down
                   self.isCaret(caret, on: .bottom, in: editor),
                   self.hasAdjacentTextField(direction: 1) {
                    let screenX = editor.firstRect(
                        forCharacterRange: NSRange(location: caret, length: 0),
                        actualRange: nil
                    ).minX
                    self.model.onMoveCaretVertically?(
                        self.model.isTitleFocused ? nil : self.model.focusedItemID,
                        1,
                        screenX
                    )
                    return nil
                }

                if event.keyCode == 124, caret == length,
                   self.hasAdjacentTextField(direction: 1) {
                    self.model.onMoveCaretHorizontally?(
                        self.model.isTitleFocused ? nil : self.model.focusedItemID,
                        1
                    )
                    return nil
                }
                if event.keyCode == 123, caret == 0,
                   self.hasAdjacentTextField(direction: -1) {
                    self.model.onMoveCaretHorizontally?(
                        self.model.isTitleFocused ? nil : self.model.focusedItemID,
                        -1
                    )
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

                guard let placement = self.pendingCaretPlacement else { return }
                self.pendingCaretPlacement = nil
                let caret = self.caretRange(for: placement, in: editor)
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
        pendingCaretPlacement = .offset(offset)
    }

    /// Places the caret on the first/last visual line of the next field at
    /// the x-position closest to where it was in the field being left.
    func placeCaretOnNextFocus(alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        pendingCaretPlacement = .horizontal(screenX: screenX, edge: edge)
    }

    private func caretRange(for placement: PendingCaretPlacement, in editor: NSTextView) -> NSRange {
        let length = (editor.string as NSString).length
        switch placement {
        case .offset(let requestedLocation):
            return NSRange(location: min(max(requestedLocation, 0), length), length: 0)

        case .horizontal(let screenX, let edge):
            let anchor = edge == .top ? 0 : length
            let anchorRect = editor.firstRect(
                forCharacterRange: NSRange(location: anchor, length: 0),
                actualRange: nil
            )
            let screenPoint = NSPoint(x: screenX, y: anchorRect.midY)
            guard let window = editor.window else {
                return NSRange(location: anchor, length: 0)
            }
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let editorPoint = editor.convert(windowPoint, from: nil)
            let location = min(editor.characterIndexForInsertion(at: editorPoint), length)
            return NSRange(location: location, length: 0)
        }
    }

    private func isCaret(_ location: Int, on edge: StickyCaretEdge, in editor: NSTextView) -> Bool {
        let length = (editor.string as NSString).length
        guard length > 0 else { return true }
        let caretRect = editor.firstRect(
            forCharacterRange: NSRange(location: min(location, length), length: 0),
            actualRange: nil
        )
        let boundary = edge == .top ? 0 : length
        let boundaryRect = editor.firstRect(
            forCharacterRange: NSRange(location: boundary, length: 0),
            actualRange: nil
        )
        let tolerance = max(caretRect.height, boundaryRect.height) * 0.5
        return abs(caretRect.midY - boundaryRect.midY) <= tolerance
    }

    private func hasAdjacentTextField(direction: Int) -> Bool {
        if model.isTitleFocused { return direction > 0 && !model.orderedItems.isEmpty }
        guard let id = model.focusedItemID,
              let index = model.orderedItems.firstIndex(where: { $0.id == id })
        else { return false }
        if direction < 0 { return true } // the title precedes the first item
        return index + 1 < model.orderedItems.count
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
        let screen = Self.bestScreen(for: model.frame)
        updateWindowSizeLimits(for: screen)
        let frame = StickyWindowGeometry.runtimeFrame(
            model.frame,
            visibleFrame: screen?.visibleFrame
        )
        setPanelFrame(frame, display: true)
        syncFrame(persist: frame != model.frame)
        panel.orderFront(nil) // normal ordering — other apps can cover it
    }

    /// Finds the display that owns the largest part of a frame. A completely
    /// off-screen frame (for example after disconnecting a monitor) heals onto
    /// the main display.
    private static func bestScreen(for frame: NSRect) -> NSScreen? {
        let candidates = NSScreen.screens.map { screen in
            (screen, frame.intersection(screen.visibleFrame).area)
        }
        if let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func updateWindowSizeLimits(for screen: NSScreen?) {
        let maximumSize = StickyWindowGeometry.effectiveMaximumSize(
            screen?.visibleFrame.size ?? StickyWindowGeometry.maximumSafeSize
        )
        // Frame-space constraints match the frame-space geometry persisted by
        // the model. The panel is borderless today, but the coordinate contract
        // remains explicit if its style changes later.
        panel.minSize = StickyWindowGeometry.minimumSize
        panel.maxSize = maximumSize
    }

    private func setPanelFrame(_ frame: NSRect, display: Bool) {
        guard panel.frame != frame else { return }
        isRepairingFrame = true
        panel.setFrame(frame, display: display)
        isRepairingFrame = false
    }

    /// Repairs every programmatic frame path too. `setFrame(_:display:)`,
    /// Accessibility window managers, and persisted initial frames bypass
    /// AppKit's min/max constraints and the resize delegate.
    private func repairCurrentFrame(keepFullyVisible: Bool, persist: Bool) {
        guard !isRepairingFrame else { return }
        let screen = panel.screen ?? Self.bestScreen(for: panel.frame)
        updateWindowSizeLimits(for: screen)

        let repaired: NSRect
        if keepFullyVisible {
            repaired = StickyWindowGeometry.runtimeFrame(
                panel.frame,
                visibleFrame: screen?.visibleFrame
            )
        } else {
            repaired = StickyWindowGeometry.runtimeFrame(
                panel.frame,
                maximumSize: screen?.visibleFrame.size
                    ?? StickyWindowGeometry.maximumSafeSize
            )
        }

        setPanelFrame(repaired, display: true)
        syncFrame(persist: persist)
    }

    func hide() {
        model.isVisible = false
        panel.orderOut(nil)
        manager?.scheduleSave()
    }

    func bringToFront() {
        if !model.isVisible { model.isVisible = true }
        repairCurrentFrame(keepFullyVisible: true, persist: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Fronts the window, activates the app, then moves focus to the end of
    /// the last visible checklist item so typing resumes where the list ends.
    func focusForTyping() {
        bringToFront()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in self?.model.onRequestLastItemFocus?() }
    }

    // MARK: - Actions surfaced to the SwiftUI content

    func requestNewSticky() { manager?.newSticky() }

    var isReplayingCompletionHistory: Bool {
        completionUndoManager.isUndoing || completionUndoManager.isRedoing
    }

    func toggleDone(_ id: UUID) {
        guard let item = model.items.first(where: { $0.id == id }) else { return }
        let isDone = !item.isDone
        setDone(id, isDone: isDone, completedAt: isDone ? Date() : nil)
    }

    private func setDone(_ id: UUID, isDone: Bool, completedAt: Date?) {
        guard let item = model.items.first(where: { $0.id == id }) else { return }
        let priorIsDone = item.isDone
        let priorCompletedAt = item.completedAt

        completionUndoManager.registerUndo(withTarget: self) { controller in
            controller.setDone(id, isDone: priorIsDone, completedAt: priorCompletedAt)
        }
        completionUndoManager.setActionName(isDone ? "Complete Task" : "Reopen Task")
        model.setDone(id, isDone: isDone, completedAt: completedAt)
    }

    /// Genie-effect minimizes to the Dock, same as any other window —
    /// unlike closing, this doesn't delete the sticky.
    func minimizeSticky() { panel.miniaturize(nil) }

    /// Close only hides this window. The sticky and all of its contents stay
    /// in the manager and on disk, so it can be opened again from Home.
    func closeSticky() { manager?.close(model.id) }

    /// The dedicated archive button is an explicit action, so it skips the
    /// close-behavior chooser and archives this sticky directly.
    func archiveSticky() { manager?.archive(model.id) }

    /// Every explicit archive/delete action (the archive button, ⌘D,
    /// Command-Delete, and the context menu) routes through here rather than
    /// deleting outright.
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

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        completionUndoManager
    }

    func windowDidMove(_ notification: Notification) {
        guard !isRepairingFrame else { return }
        syncFrame(persist: true)
    }

    func windowDidResize(_ notification: Notification) {
        guard !isRepairingFrame else { return }
        // Keep model geometry current for SwiftUI, but don't encode/write every
        // sticky while the mouse is still held in a live resize session. AX
        // and other programmatic resizes are not live sessions, so repair their
        // position immediately as well as their size.
        let isLiveResize = panel.inLiveResize
        repairCurrentFrame(keepFullyVisible: !isLiveResize, persist: !isLiveResize)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let screen = sender.screen ?? Self.bestScreen(for: sender.frame)
        updateWindowSizeLimits(for: screen)
        return StickyWindowGeometry.constrainedSize(
            frameSize,
            maximumSize: screen?.visibleFrame.size
                ?? StickyWindowGeometry.maximumSafeSize
        )
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        updateWindowSizeLimits(for: panel.screen ?? Self.bestScreen(for: panel.frame))
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        repairCurrentFrame(keepFullyVisible: true, persist: true)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        repairCurrentFrame(keepFullyVisible: true, persist: true)
    }

    /// Tracks "most recently active" from a plain click too, not just
    /// programmatic `bringToFront()` — so the global shortcut jumps to
    /// whichever sticky you actually used last either way.
    func windowDidBecomeKey(_ notification: Notification) {
        manager?.noteActive(model.id)
        DispatchQueue.main.async { [weak self] in self?.ensureTextFocus() }
    }

    /// A key sticky should always remain ready for typing, even after its
    /// background or a mouse-only control was clicked.
    private func ensureTextFocus() {
        guard panel.isKeyWindow, !(panel.firstResponder is NSTextView) else { return }
        model.onRequestLastItemFocus?()
    }

    private func syncFrame(persist: Bool) {
        model.frame = panel.frame
        if persist { manager?.scheduleSave() }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(width, 0) * max(height, 0)
    }
}
