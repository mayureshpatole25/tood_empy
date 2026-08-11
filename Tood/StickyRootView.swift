import AppKit
import SwiftUI

/// The visible sticky: flat, edge-to-edge paper with a big two-line "To Do"
/// title, a date, and an editable checklist. Hosted in a borderless window.
struct StickyRootView: View {
    let model: StickyModel
    unowned let controller: StickyController

    @FocusState private var focusedID: UUID?
    @FocusState private var emojiFieldFocused: Bool
    @State private var hovering = false
    @State private var showColors = false
    @State private var showFonts = false
    @State private var paywallPack: ColorPack?
    private var packStore: ColorPackStore { ColorPackStore.shared }
    /// The window's current available height, tracked live so the collapse
    /// threshold below stays in sync as the sticky is dragged bigger/smaller.
    @State private var availableHeight: CGFloat = 490

    private let corner: CGFloat = 4
    /// Estimates for how many rows currently fit — not pixel-precise (rows
    /// can wrap), but `StickyController.recheckContentSize()` snaps the
    /// window to the exact fit right after, so small errors self-correct.
    /// Matches the checkbox's 34pt-tall click target (see `checkbox(_:)`)
    /// plus the row's 6+6 vertical padding and 1pt divider — stale here
    /// after that target was made taller was exactly what caused a visible
    /// double-snap on "Show less"/"N more" for longer lists, since every
    /// row's error compounded across the whole list.
    private let rowHeightEstimate: CGFloat = 47
    private let chromeHeightEstimate: CGFloat = 254 // date line + title block + spacer + top/bottom padding
    /// Where "Show less" collapses back down to.
    private let defaultCollapsedRows = 6

    private var color: StickyColor { model.color }

    var body: some View {
        ZStack(alignment: .top) {
            paperBackground
            content
            bottomToolbar
            topRightButtons
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        // A `.background` GeometryReader reads the window's current height
        // for the fluid collapse threshold below without becoming the root
        // of the view tree — a GeometryReader as body's *root* (tried
        // earlier) has no well-defined ideal size of its own, which broke
        // NSHostingView.fittingSize for every other piece of sizing logic.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in availableHeight = newHeight }
            }
        )
        .contextMenu { contextMenu }
        .sheet(item: $paywallPack) { pack in
            ColorPackPaywallView(pack: pack) { }
        }
        .onHover { hovering = $0 }
        .onAppear {
            focusedID = model.items.first?.id
            model.focusedItemID = focusedID
            model.onBackspaceEmptyRow = { id in
                if let item = model.items.first(where: { $0.id == id }) {
                    _ = backspaceDelete(item)
                }
            }
            model.onRequestFocus = {
                focusedID = model.items.first(where: { !$0.isDone })?.id ?? model.items.first?.id
            }
            model.onMultilinePaste = { lines, targetID in
                if let lastID = model.pasteLines(lines, after: targetID) {
                    focusedID = lastID
                }
            }
        }
        .onChange(of: focusedID) { _, new in model.focusedItemID = new }
    }

    /// The flat paper itself.
    private var paperBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color.paper)
            GrainOverlay()
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    // MARK: - Content

    /// No trailing filler — this view's natural height is what the
    /// controller measures (via NSHostingView.fittingSize) to grow the
    /// window to fit.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 32)
            checklist
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 64) // clears the bottom hover toolbar, which now sits flush against the window edge
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The date sits on its own line above the title now — it used
            // to share the title's row (reserving a fixed slot beside it),
            // which ate into the title's width and made longer titles wrap
            // mid-word or get cut off. Up here it costs a line of height
            // instead, and the title gets the sticky's full width.
            Text(Self.dateFormatter.string(from: model.day))
                .font(bodyFont(14))
                .foregroundStyle(color.ink.opacity(0.3))

            // Measures the header's width and gives the title an explicit,
            // fixed budget (total minus the emoji field's slot) rather than
            // letting the TextField report its own "ideal" width — an
            // unconstrained TextField's ideal width just grows with its
            // content, so measuring that was circular and never actually
            // constrained anything (titles kept wrapping mid-word
            // regardless).
            GeometryReader { proxy in
                let emojiSize = AppSettings.shared.titleSize.baseSize
                let emojiSlot: CGFloat = emojiSize * 1.05
                let gap: CGFloat = 6
                let titleWidth = max(proxy.size.width - emojiSlot - gap, 80)
                let titleSize = Self.titleFontSize(
                    for: model.title, baseSize: AppSettings.shared.titleSize.baseSize, availableWidth: titleWidth
                )

                HStack(alignment: .top, spacing: gap) {
                    emojiField(size: emojiSize, slotWidth: emojiSlot)

                    // Editable title — wraps naturally up to 2 lines, Regular
                    // weight (Medium read too bold). Steps down in size as
                    // the title gets longer (see `titleFontSize`) so a
                    // single word that can't wrap (no space to break on)
                    // shrinks instead of getting cut mid-word ("Admin" →
                    // "Admi"/"n").
                    TextField("To Do", text: titleBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.custom("HelveticaNeue", size: titleSize))
                        .tracking(titleSize * -0.06) // -6% of size, same ratio at every step
                        .foregroundStyle(color.titleInk)
                        .tint(color.titleInk) // otherwise the cursor inherits the app's green accent — invisible on the green sticky
                        .lineLimit(1...2)
                        .lineSpacing(titleSize * -0.1) // ~90% line height, same ratio at every step
                        .onKeyPress(.return) { .handled } // titles wrap, they don't take manual line breaks
                        .padding(.trailing, 6) // headroom for negative tracking on the last glyph
                        .frame(width: titleWidth, height: 108, alignment: .topLeading)
                }
            }
            .frame(height: 108) // fixes this GeometryReader's own height so it doesn't disrupt the sticky's natural content-height sizing
        }
    }

    /// The icon slot to the left of the title — tapping it focuses a
    /// (visually real, just icon-sized) text field and pops open macOS's
    /// own Emoji & Symbols picker, Notion-style, rather than reimplementing
    /// an emoji grid ourselves. Typing an emoji directly, or the system
    /// shortcut (⌃⌘Space), works too, same as any other text field. Shows a
    /// faint "+" on hover when there's no icon yet.
    private func emojiField(size: CGFloat, slotWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if model.emoji == nil {
                Text("+")
                    .font(.system(size: size * 0.5, weight: .light))
                    .foregroundStyle(color.ink.opacity(hovering ? 0.25 : 0))
                    .frame(width: slotWidth, height: 108, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
            TextField("", text: emojiBinding)
                .textFieldStyle(.plain)
                .font(.system(size: size))
                .focused($emojiFieldFocused)
                .onChange(of: emojiFieldFocused) { _, focused in
                    if focused { NSApp.orderFrontCharacterPalette(nil) }
                }
                .frame(width: slotWidth, height: 108, alignment: .topLeading)
        }
    }

    /// Shrinks the title (starting from `baseSize`, the user's chosen
    /// ceiling in Settings) until its widest *unbroken word* actually fits
    /// `availableWidth` — a character-count tier isn't right here, since a
    /// single word that's too wide can't be fixed by wrapping (there's no
    /// space to break on), it just gets cut mid-word. Multi-word titles
    /// still wrap normally between words at whatever size their longest
    /// word lands on; only an unbroken word ever forces a shrink.
    private static func titleFontSize(for text: String, baseSize: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return baseSize }
        let longestWord = text
            .components(separatedBy: " ")
            .max(by: { $0.count < $1.count }) ?? text

        // A few points of slack below the measured column width — the
        // caret, subpixel rounding, and the trailing padding above all eat
        // into it in ways a raw string measurement doesn't capture.
        let budget = max(availableWidth - 10, 40)
        var size = baseSize
        while size > 20 {
            let font = NSFont(name: "HelveticaNeue", size: size) ?? NSFont.systemFont(ofSize: size)
            let width = (longestWord as NSString)
                .size(withAttributes: [.font: font, .kern: size * -0.06])
                .width
            if width <= budget { break }
            size -= 2
        }
        return size
    }

    private var titleBinding: Binding<String> {
        Binding(get: { model.title }, set: { model.setTitle($0) })
    }

    private var emojiBinding: Binding<String> {
        Binding(
            get: { model.emoji ?? "" },
            // Only ever keep the most recently typed/inserted character —
            // the field starts from whatever's already there (so the
            // picker can replace it), and the system palette can insert
            // more than one character if double-clicked.
            set: { model.setEmoji($0.last.map(String.init)) }
        )
    }

    /// Minimize + dismiss, pinned to the top-right corner, independent of
    /// the bottom hover toolbar. Kept very low-opacity so it doesn't compete
    /// with the date.
    ///
    /// Explicit `maxWidth: .infinity, alignment: .trailing` here, not just
    /// an inner `Spacer()` — the enclosing ZStack's own alignment is `.top`
    /// (top-*center*), so a child that doesn't span the full width centers
    /// itself there regardless of its own internal alignment. Learned that
    /// the hard way: an earlier version of this without the frame landed
    /// dead center instead of at either edge.
    private var topRightButtons: some View {
        VStack {
            HStack(spacing: 2) {
                Spacer()
                Button { controller.minimizeSticky() } label: {
                    Text("–")
                        .font(.custom("ABCStefanTrial-Simple", size: 16))
                        .foregroundStyle(color.ink.opacity(0.3))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { controller.closeSticky() } label: {
                    Text("X")
                        .font(.custom("ABCStefanTrial-Simple", size: 16))
                        .foregroundStyle(color.ink.opacity(0.3))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 14)
        .padding(.trailing, 14)
        .opacity(hovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    // MARK: - Checklist

    /// How many rows fit in the window's *current* height — purely a
    /// function of `availableHeight`, so dragging the sticky bigger/smaller
    /// immediately changes how many rows show and how big "N more" reads.
    private var visibleRowCapacity: Int {
        max(1, Int((availableHeight - chromeHeightEstimate) / rowHeightEstimate))
    }

    /// Rows actually rendered. Reserves one slot for the toggle row itself
    /// when something's hidden, so the toggle doesn't itself overflow.
    private var visibleItems: [TodoItem] {
        let all = model.orderedItems
        guard all.count > visibleRowCapacity else { return all }
        return Array(all.prefix(max(1, visibleRowCapacity - 1)))
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleItems) { item in
                row(item)
            }
            toggleIfNeeded
            addRowButton
        }
        // No `.animation(value: model.items)` here — the checkbox's own
        // `withAnimation` at the toggle call site is the single source of
        // truth for that motion. Layering both made the reorder read as
        // muddled/inelegant instead of one clean row (text + its divider)
        // sliding to its new spot.
        .animation(.snappy(duration: 0.3), value: availableHeight)
    }

    /// "N more" while something's hidden by the current size; once
    /// everything fits, "Show less" offers to shrink back to a compact
    /// default (only if the list is actually longer than that default).
    @ViewBuilder
    private var toggleIfNeeded: some View {
        let total = model.orderedItems.count
        let hidden = total - visibleItems.count
        if hidden > 0 {
            toggleButton(label: "\(hidden) more", systemImage: "chevron.down") {
                controller.growBy(rows: hidden, estimatedRowHeight: rowHeightEstimate)
            }
        } else if total > defaultCollapsedRows {
            toggleButton(label: "Show less", systemImage: "chevron.up") {
                controller.collapse(toRows: defaultCollapsedRows,
                                    rowHeight: rowHeightEstimate, chromeHeight: chromeHeightEstimate)
            }
        }
    }

    /// Always-there "next row," so starting a new line never requires
    /// clicking into an existing one first. Hidden when "N more" is already
    /// showing — no room to invite yet another row on top of that.
    @ViewBuilder
    private var addRowButton: some View {
        let hidden = model.orderedItems.count - visibleItems.count
        if hidden == 0 {
            Button {
                let newID = model.addItem()
                revealIfHidden()
                focusedID = newID
            } label: {
                HStack(spacing: 19) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color.ink.opacity(0.32))
                        .frame(width: 24, height: 24)
                    Text("Add item")
                        .font(bodyFont(13))
                        .foregroundStyle(color.ink.opacity(0.32))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(bodyFont(12))
            }
            .foregroundStyle(color.ink.opacity(0.5))
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: TodoItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 19) {
                checkbox(item)
                if item.isDone {
                    Text(item.text)
                        .font(bodyFont(14))
                        .foregroundStyle(color.inkSecondary)
                        .strikethrough(true, color: color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.identity) // no fade — just the row sliding to its new spot
                } else {
                    // axis: .vertical → wraps and grows to new lines instead of
                    // running off to the right. Enter handled below; backspace
                    // on an empty row is caught by the window's key monitor
                    // (StickyController) since TextField swallows .delete.
                    TextField("", text: textBinding(item), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(bodyFont(14))
                        .foregroundStyle(color.ink.opacity(0.8))
                        .tint(color.ink) // otherwise the cursor inherits the app's green accent — invisible on the green sticky
                        .lineLimit(1...12)
                        .focused($focusedID, equals: item.id)
                        .onChange(of: bindingValue(item)) { _, newValue in
                            handleDash(item, newValue)
                        }
                        .onKeyPress(.return) {
                            submit(item)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            moveFocus(from: item, by: -1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            moveFocus(from: item, by: 1)
                            return .handled
                        }
                        .transition(.identity)
                }
            }
            .padding(.vertical, 6)
            Rectangle()
                .fill(color.divider)
                .frame(height: 1)
        }
    }

    private func checkbox(_ item: TodoItem) -> some View {
        Button {
            toggleDone(item)
        } label: {
            ZStack {
                if item.isDone {
                    // Fill only when done — layering a stroke of the same
                    // color underneath a fill double-blends their opacities
                    // (the centered stroke's outer half also peeks past the
                    // fill's edge), which is why the border read as a
                    // different shade than the fill.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.ink.opacity(0.3))
                        .frame(width: 13, height: 13)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color.paper)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(color.ink.opacity(0.3), lineWidth: 1.1)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 24, height: 34)      // taller than the visual box — the whole row's click height, not just the glyph
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Toggling isDone swaps this row between an editable `TextField` and a
    /// static strikethrough `Text` — if the row being checked off still has
    /// keyboard focus, that swap yanks focus out from under the field
    /// mid-animation, which is what made this feel broken. Clearing focus
    /// *before* the toggle keeps the animation clean. (This used to move
    /// focus to a neighboring row instead of clearing it, but that planted
    /// a visible text cursor/focus ring on a row you never clicked, reading
    /// as a stray highlight on the line above.)
    private func toggleDone(_ item: TodoItem) {
        if !item.isDone, focusedID == item.id {
            focusedID = nil
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            model.toggle(item.id)
        }
    }

    // MARK: - Color picker (free swatches + paid packs)

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(StickyColor.allCases.filter { $0.pack == nil }) { c in
                    colorSwatchButton(c)
                }
            }
            ForEach(ColorPack.allCases) { pack in
                HStack(spacing: 10) {
                    if packStore.isUnlocked(pack) {
                        ForEach(pack.colors) { c in colorSwatchButton(c) }
                    } else {
                        Button { paywallPack = pack } label: {
                            HStack(spacing: 6) {
                                ForEach(pack.colors) { c in
                                    Circle().fill(c.paper).frame(width: 14, height: 14)
                                }
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }

    private func colorSwatchButton(_ c: StickyColor) -> some View {
        Button {
            model.setColor(c)
            showColors = false
        } label: {
            Circle()
                .fill(c.paper)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                .overlay(
                    Circle().stroke(color.ink, lineWidth: c == model.color ? 2 : 0)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom hover toolbar

    private var bottomToolbar: some View {
        VStack {
            Spacer()
            HStack(spacing: 18) {
                Button { showColors.toggle() } label: { Image(systemName: "paintpalette") }
                    .popover(isPresented: $showColors, arrowEdge: .top) {
                        colorPicker
                    }

                Button { showFonts.toggle() } label: {
                    Text("Aa").font(.custom("ABCStefanTrial-Simple", size: 15))
                }
                    .popover(isPresented: $showFonts, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(StickyFont.allCases) { f in
                                Button {
                                    model.setFont(f)
                                    showFonts = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(f.displayName)
                                        if f == model.font {
                                            Spacer(minLength: 12)
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding(8)
                    }

                Button { controller.requestNewSticky() } label: {
                    Text("+").font(.custom("ABCStefanTrial-Simple", size: 18))
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color.ink.opacity(0.5))
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                Capsule().fill(color.paper.opacity(0.6))
            )
            .padding(.bottom, 16)
            .opacity(hovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: hovering)
        }
    }

    // MARK: - Context menu

    @ViewBuilder private var contextMenu: some View {
        Menu("Color") {
            // Owned colors only — locked pack colors need the paywall UI in
            // the popover picker, not a bare menu item.
            ForEach(StickyColor.allCases.filter { $0.pack == nil || packStore.isUnlocked($0.pack!) }) { c in
                Button(c.displayName) { model.setColor(c) }
            }
        }
        Menu("Font") {
            ForEach(StickyFont.allCases) { f in
                Button(f.displayName) { model.setFont(f) }
            }
        }
        Divider()
        Button("New Sticky") { controller.requestNewSticky() }
        Button("Delete Sticky", role: .destructive) { controller.closeSticky() }
    }

    // MARK: - Editing helpers

    private func submit(_ item: TodoItem) {
        guard !isBlank(bindingValue(item)) else { return }
        let newID = model.addItem(after: item)
        revealIfHidden()
        focusedID = newID
    }

    /// A newly-created row past the current capacity wouldn't be rendered,
    /// so FocusState would point at nothing and keystrokes would silently
    /// land back in the last visible field instead. Grow by one row so it's
    /// actually there.
    private func revealIfHidden() {
        guard model.orderedItems.count > visibleRowCapacity else { return }
        controller.growBy(rows: 1, estimatedRowHeight: rowHeightEstimate)
    }

    /// Up/down arrow jumps focus to the adjacent row — same convention as
    /// Reminders/Things checklists. Trades away moving the cursor between a
    /// single item's own wrapped lines, but checklist rows are short enough
    /// in practice that row-to-row navigation is the more useful default.
    private func moveFocus(from item: TodoItem, by delta: Int) {
        let ordered = model.orderedItems
        guard let idx = ordered.firstIndex(where: { $0.id == item.id }) else { return }
        let target = idx + delta
        guard ordered.indices.contains(target) else { return }
        focusedID = ordered[target].id
    }

    /// Backspace on an empty (or whitespace-only) row deletes it and focuses
    /// the previous row. Returns true if it handled the keystroke.
    private func backspaceDelete(_ item: TodoItem) -> Bool {
        guard isBlank(bindingValue(item)) else { return false }
        let active = model.items.filter { !$0.isDone }
        guard active.count > 1, let idx = active.firstIndex(where: { $0.id == item.id })
        else { return false }
        let target = idx > 0 ? active[idx - 1].id : active[idx + 1].id
        controller.armSelectionSuppression()
        model.delete(item.id)
        focusedID = target
        return true
    }

    private func handleDash(_ item: TodoItem, _ value: String) {
        if value == "-" {
            model.setText(item.id, "")
            let newID = model.addItem(after: item)
            revealIfHidden()
            focusedID = newID
        }
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func bindingValue(_ item: TodoItem) -> String {
        model.items.first { $0.id == item.id }?.text ?? ""
    }

    private func textBinding(_ item: TodoItem) -> Binding<String> {
        Binding(
            get: { model.items.first { $0.id == item.id }?.text ?? "" },
            set: { model.setText(item.id, $0) }
        )
    }

    private func bodyFont(_ size: CGFloat) -> Font {
        model.font.body(size)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM dd, yyyy"
        return f
    }()
}
