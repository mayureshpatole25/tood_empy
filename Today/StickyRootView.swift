import SwiftUI

/// The visible sticky: flat, edge-to-edge paper with a big two-line "To Do"
/// title, a date, and an editable checklist. Hosted in a borderless window.
struct StickyRootView: View {
    let model: StickyModel
    unowned let controller: StickyController

    @FocusState private var focusedID: UUID?
    @State private var hovering = false
    @State private var showColors = false
    @State private var showFonts = false
    /// The window's current available height, tracked live so the collapse
    /// threshold below stays in sync as the sticky is dragged bigger/smaller.
    @State private var availableHeight: CGFloat = 490

    private let corner: CGFloat = 4
    /// Estimates for how many rows currently fit — not pixel-precise (rows
    /// can wrap), but `StickyController.recheckContentSize()` snaps the
    /// window to the exact fit right after, so small errors self-correct.
    private let rowHeightEstimate: CGFloat = 31
    private let chromeHeightEstimate: CGFloat = 232 // title block + spacer + top/bottom padding
    /// Where "Show less" collapses back down to.
    private let defaultCollapsedRows = 6

    private var color: StickyColor { model.color }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color.paper)
            GrainOverlay()
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            content
            bottomToolbar
            closeButton
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
        }
        .onChange(of: focusedID) { _, new in model.focusedItemID = new }
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
        HStack(alignment: .top, spacing: 8) {
            // Editable title — wraps naturally up to 2 lines at 90% line
            // height, Regular weight (Medium read too bold), instead of the
            // old fixed "To Do" split one-word-per-line.
            TextField("To Do", text: titleBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.custom("HelveticaNeue", size: 60))
                .tracking(-3.6) // -6% of the 60pt size
                .foregroundStyle(color.titleInk)
                .lineLimit(1...2)
                .lineSpacing(-6) // ~90% line height at this size
                .onKeyPress(.return) { .handled } // titles wrap, they don't take manual line breaks
                .padding(.trailing, 6) // headroom for negative tracking on the last glyph
                .frame(height: 108, alignment: .top) // 54 * 2 — same footprint as the old fixed two-line block
            Spacer(minLength: 8)
            Text(Self.dateFormatter.string(from: model.day))
                .font(bodyFont(14))
                .foregroundStyle(color.ink.opacity(0.3))
                .padding(.top, 6)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(get: { model.title }, set: { model.setTitle($0) })
    }

    /// Small dismiss button pinned to the top-right corner, independent of
    /// the bottom hover toolbar. Kept very low-opacity so it doesn't compete
    /// with the date.
    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
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
                        .lineLimit(1...12)
                        .focused($focusedID, equals: item.id)
                        .onChange(of: bindingValue(item)) { _, newValue in
                            handleDash(item, newValue)
                        }
                        .onKeyPress(.return) {
                            submit(item)
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
            // Linear, not eased — a constant-speed slide reads as "both rows
            // moving together" rather than one darting ahead of the other.
            withAnimation(.linear(duration: 0.8)) { model.toggle(item.id) }
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
            .frame(width: 24, height: 24)      // generous, fully-tappable hit area
            .contentShape(Rectangle())
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
                        HStack(spacing: 10) {
                            ForEach(StickyColor.allCases) { c in
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
                        }
                        .padding(12)
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
            ForEach(StickyColor.allCases) { c in
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
