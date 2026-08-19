import Foundation
import Observation

/// Plain `Codable` snapshot written to disk. Kept separate from the runtime
/// `@Observable` model because the Observation macro doesn't encode cleanly.
struct StickyData: Codable, Identifiable {
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

    /// Mirrors the SwiftUI `@FocusState` so AppKit-level key handling (which
    /// can't see FocusState) knows which row is focused. Not persisted.
    @ObservationIgnored var focusedItemID: UUID?
    @ObservationIgnored var isTitleFocused = false

    /// Set by the view; invoked by the window's key monitor for editing that
    /// crosses TextField boundaries. SwiftUI's TextField consumes Return and
    /// Delete before `onKeyPress` can reliably inspect the AppKit caret.
    @ObservationIgnored var onSplitTitle: ((Int) -> Void)?
    @ObservationIgnored var onMergeItemBackward: ((UUID) -> Void)?

    /// Set by the view; invoked by `StickyController.focusForTyping()` (the
    /// global "show active sticky" shortcut) to move keyboard focus onto the
    /// first thing worth typing into — SwiftUI's `@FocusState` isn't visible
    /// from the AppKit-level controller, so this is the same bridge pattern.
    @ObservationIgnored var onRequestFocus: (() -> Void)?
    @ObservationIgnored var onRequestTitleFocus: (() -> Void)?
    @ObservationIgnored var onRequestFirstItemFocus: (() -> Void)?
    @ObservationIgnored var onRequestLastItemFocus: (() -> Void)?

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
        self.frame = data.frame
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
                   colorID: colorID, fontID: fontID, frame: frame, isVisible: isVisible)
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
        items[idx].isDone.toggle()
        items[idx].completedAt = items[idx].isDone ? Date() : nil
        onChange?()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
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
            frame: CGRect(x: origin.x, y: origin.y, width: 378, height: 490),
            isVisible: true
        )
        return StickyModel(data: data)
    }
}
