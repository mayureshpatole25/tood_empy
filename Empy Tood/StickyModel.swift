import Foundation
import Observation

/// Plain `Codable` snapshot written to disk. Kept separate from the runtime
/// `@Observable` model because the Observation macro doesn't encode cleanly.
struct StickyData: Codable, Identifiable {
    static let defaultSize = StickyWindowGeometry.defaultSize

    var id: UUID
    var title: String
    /// Leftover from a short-lived separate icon field — some stickies were
    /// saved with the emoji split out into this key instead of being the
    /// title's first character. Never written anymore (`StickyModel.init`
    /// merges it straight back into `title` on load and drops it), kept
    /// here only so those already-split saves decode losslessly instead of
    /// silently dropping their icon.
    var emoji: String?
    var day: Date
    var items: [TodoItem]
    var colorID: StickyColor
    var fontID: StickyFont
    var frame: CGRect
    var isVisible: Bool
}

/// Runtime model for a single sticky. SwiftUI observes it directly.
@MainActor
@Observable
final class StickyModel: Identifiable {
    let id: UUID
    var title: String
    var day: Date
    var items: [TodoItem]
    var colorID: StickyColor
    var fontID: StickyFont
    var frame: CGRect
    var isVisible: Bool

    /// Called on any change that should be persisted (routed to the manager).
    @ObservationIgnored var onChange: (() -> Void)?

    /// Gives the view a chance to stage completion visibility before the
    /// persisted values change. The Bool is the exact incoming done state.
    @ObservationIgnored var onWillSetDone: ((UUID, Bool) -> Void)?

    /// Mirrors the SwiftUI `@FocusState` so AppKit-level key handling (which
    /// can't see FocusState) knows which row is focused. Not persisted.
    @ObservationIgnored var focusedItemID: UUID?
    @ObservationIgnored var isTitleFocused = false

    /// Set by the view; invoked by the window's key monitor for editing that
    /// crosses TextField boundaries. SwiftUI's TextField consumes Return and
    /// Delete before `onKeyPress` can reliably inspect the AppKit caret.
    @ObservationIgnored var onSplitTitle: ((Int) -> Void)?
    @ObservationIgnored var onSplitItem: ((UUID, Int) -> Void)?
    @ObservationIgnored var onMergeItemBackward: ((UUID) -> Void)?
    @ObservationIgnored var onMergeItemForward: ((UUID) -> Void)?

    /// Set by the view; invoked by `StickyController.focusForTyping()` (the
    /// global "show active sticky" shortcut) to move keyboard focus onto the
    /// first thing worth typing into — SwiftUI's `@FocusState` isn't visible
    /// from the AppKit-level controller, so this is the same bridge pattern.
    @ObservationIgnored var onRequestFocus: (() -> Void)?
    @ObservationIgnored var onRequestLastItemFocus: (() -> Void)?
    /// Toggles whether completed rows are visible in this sticky. Bridged to
    /// the view so the AppKit key monitor can handle Command-S reliably.
    @ObservationIgnored var onToggleDoneVisibility: (() -> Void)?
    /// Moves the caret to the start of the title (-1) or the end of the
    /// final visible checklist item (+1) for Command-Up/Command-Down.
    @ObservationIgnored var onMoveCaretToDocumentBoundary: ((Int) -> Void)?
    @ObservationIgnored var onMoveCaretHorizontally: ((UUID?, Int) -> Void)?
    @ObservationIgnored var onMoveCaretVertically: ((UUID?, Int, CGFloat) -> Void)?

    /// Set by the view; invoked by the window's key monitor when ⌘V pastes
    /// multi-line text — same bridge pattern, since focusing the resulting
    /// last row needs SwiftUI's `@FocusState`, not visible from here either.
    @ObservationIgnored var onMultilinePaste: (([String], UUID) -> Void)?

    init(data: StickyData) {
        self.id = data.id
        self.day = data.day
        self.items = data.items
        self.colorID = data.colorID
        self.fontID = data.fontID
        // Persisted window geometry is untrusted input. AppKit can construct a
        // 0×0 window from negative dimensions and can throw while constructing
        // an absurdly large one, so repair it before StickyController creates
        // the panel. Valid user-selected heights are preserved.
        self.frame = StickyWindowGeometry.persistedFrame(data.frame)
        self.isVisible = data.isVisible

        // Merge a split-out icon straight back into the title, exactly as
        // if it had never left — see the `emoji` doc comment on StickyData.
        if let emoji = data.emoji, !emoji.isEmpty {
            self.title = "\(emoji) \(data.title)"
        } else {
            self.title = data.title
        }
    }

    var color: StickyColor { colorID }
    var font: StickyFont { fontID }

    func snapshot() -> StickyData {
        StickyData(id: id, title: title, emoji: nil, day: day, items: items,
                   colorID: colorID, fontID: fontID,
                   frame: StickyWindowGeometry.runtimeFrame(frame),
                   isVisible: isVisible)
    }

    // MARK: - Ordering
    // Whatever order `items` is actually in — checking a row off no longer
    // moves it; it just strikes through in place. The only thing that
    // changes order is dragging a row (handled directly in
    // StickyRootView's drag gesture, which mutates `items` itself).
    var orderedItems: [TodoItem] { items }

    // MARK: - Mutations (each notifies the manager to persist)

    @discardableResult
    func addItem(after item: TodoItem? = nil) -> UUID {
        let new = TodoItem()
        if let item, let idx = items.firstIndex(where: { $0.id == item.id }) {
            items.insert(new, at: idx + 1)
        } else {
            items.append(new)
        }
        onChange?()
        return new.id
    }

    /// Splits a checklist row at an AppKit UTF-16 caret offset. At column
    /// zero, preserve the existing item intact and insert the blank row before
    /// it; elsewhere the prefix stays in the existing item and the suffix
    /// becomes the following item. Returns the new row to focus.
    @discardableResult
    func splitItem(_ id: UUID, atUTF16Offset offset: Int) -> UUID? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        let text = items[idx].text as NSString
        let split = min(max(offset, 0), text.length)
        let new: TodoItem

        if split == 0 {
            new = TodoItem()
            items.insert(new, at: idx)
        } else {
            items[idx].text = text.substring(to: split)
            new = TodoItem(text: text.substring(from: split))
            items.insert(new, at: idx + 1)
        }

        onChange?()
        return new.id
    }

    /// Joins the following visible row into `id`, preserving the current row
    /// and returning the UTF-16 offset where the caret should remain.
    @discardableResult
    func mergeItemForward(_ id: UUID, with nextID: UUID) -> Int? {
        guard id != nextID,
              let idx = items.firstIndex(where: { $0.id == id }),
              let nextIndex = items.firstIndex(where: { $0.id == nextID })
        else { return nil }

        let join = (items[idx].text as NSString).length
        items[idx].text += items[nextIndex].text
        items.remove(at: nextIndex)
        onChange?()
        return join
    }

    func setText(_ id: UUID, _ text: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].text = text
        onChange?()
    }

    /// Splits a multi-line paste into one item per line. If the target row
    /// is still empty, the first line fills it and the rest become new
    /// items after it; otherwise the whole paste becomes new items after
    /// the target, leaving what's already typed there alone. Returns the
    /// last inserted item's id, to focus.
    @discardableResult
    func pasteLines(_ lines: [String], after targetID: UUID) -> UUID? {
        guard let idx = items.firstIndex(where: { $0.id == targetID }) else { return nil }
        var remaining = lines
        var insertAt = idx + 1
        if items[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !remaining.isEmpty {
            items[idx].text = remaining.removeFirst()
        }
        var lastID: UUID?
        for line in remaining {
            let newItem = TodoItem(text: line)
            items.insert(newItem, at: insertAt)
            insertAt += 1
            lastID = newItem.id
        }
        onChange?()
        return lastID ?? targetID
    }

    func toggle(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let isDone = !items[idx].isDone
        setDone(id, isDone: isDone, completedAt: isDone ? Date() : nil)
    }

    func setDone(_ id: UUID, isDone: Bool, completedAt: Date?) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        onWillSetDone?(id, isDone)
        items[idx].isDone = isDone
        items[idx].completedAt = completedAt
        onChange?()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        onChange?()
    }

    /// Moves one row through the source-of-truth array. Reordering relative
    /// to an item (rather than a visible index) keeps the operation correct
    /// when completed rows are currently hidden from the checklist.
    func moveItem(_ id: UUID, relativeTo targetID: UUID) {
        guard id != targetID,
              let sourceIndex = items.firstIndex(where: { $0.id == id }),
              let targetIndex = items.firstIndex(where: { $0.id == targetID })
        else { return }

        let item = items.remove(at: sourceIndex)
        items.insert(item, at: min(targetIndex, items.endIndex))
        onChange?()
    }


    func setColor(_ c: StickyColor) { colorID = c; onChange?() }
    func setFont(_ f: StickyFont) { fontID = f; onChange?() }
    func setTitle(_ t: String) { title = t; onChange?() }

    // MARK: - Factory

    static func makeNew(
        at origin: CGPoint,
        color: StickyColor = .nextNewStickyColor(),
        font: StickyFont = .defaultFont
    ) -> StickyModel {
        let data = StickyData(
            id: UUID(),
            title: "To Do",
            emoji: nil,
            day: Date(),
            items: [TodoItem()], // start with one empty line, ready to type
            colorID: color,
            fontID: font,
            frame: CGRect(origin: origin, size: StickyData.defaultSize),
            isVisible: true
        )
        return StickyModel(data: data)
    }
}
