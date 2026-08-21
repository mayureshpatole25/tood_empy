import AppKit
import SwiftUI

private struct ChecklistRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private enum HoverMotion {
    static let feedback = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14)
}

private struct HoverFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let scale: CGFloat
    let darkening: Double
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion && isEnabled ? scale : 1)
            .brightness(isHovering && isEnabled ? darkening : 0)
            .animation(HoverMotion.feedback, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

private extension View {
    func hoverFeedback(
        scale: CGFloat,
        darkening: Double = 0,
        isEnabled: Bool = true
    ) -> some View {
        modifier(HoverFeedbackModifier(scale: scale, darkening: darkening, isEnabled: isEnabled))
    }
}

/// The visible sticky: flat, edge-to-edge paper with a big two-line "To Do"
/// title, a date, and an editable checklist. Hosted in a borderless window.
struct StickyRootView: View {
    let model: StickyModel
    unowned let controller: StickyController

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var focusedID: UUID?
    @FocusState private var titleFocused: Bool
    @State private var hovering = false
    @State private var hoveringTopChrome = false
    @State private var showColors = false
    @State private var showsDoneTasks = false
    @State private var retainedCompletionIDs: Set<UUID> = []
    @State private var completionExitTasks: [UUID: Task<Void, Never>] = [:]
    @State private var completionExitGenerations: [UUID: UUID] = [:]
    @State private var reduceMotionEnabled = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var draggingItemID: UUID?
    @State private var dragTranslationY: CGFloat = 0
    @State private var dragLayoutCompensationY: CGFloat = 0
    @State private var pressedCheckboxID: UUID?
    @State private var hoveredCheckboxID: UUID?
    @State private var addRowHovered = false
    @State private var suppressCheckboxToggleID: UUID?
    /// The window's current width — the title needs it (see `header`) without a local
    /// `GeometryReader` forcing a fixed height on it. A previous version
    /// used a `titleWraps` heuristic (does the whole title fit on one line?)
    /// to pick between a 58pt/108pt box, on the assumption that "doesn't fit
    /// on one line" always means "fits in two" — it doesn't (emoji + a few
    /// words can need three), and since the box couldn't grow past whichever
    /// of those two heights it guessed, the overflow just silently clipped:
    /// title text still in the data, invisibly cut from view. Letting the
    /// TextField size itself intrinsically, with no guess in the way, is
    /// what actually guarantees it never happens.
    @State private var availableWidth: CGFloat
    @State private var availableHeight: CGFloat

    private let corner: CGFloat = 4
    private let contentInset: CGFloat = 24
    private var color: StickyColor { model.color }

    init(model: StickyModel, controller: StickyController) {
        self.model = model
        self.controller = controller
        _availableWidth = State(initialValue: model.frame.width)
        _availableHeight = State(initialValue: model.frame.height)
    }

    var body: some View {
        ZStack(alignment: .top) {
            paperBackground
            content
            bottomToolbar
            windowControls
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        // A `.background` GeometryReader reads the window's current width
        // without becoming the root
        // of the view tree — a GeometryReader as body's *root* (tried
        // earlier) has no well-defined ideal size of its own, which broke
        // NSHostingView.fittingSize for every other piece of sizing logic.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableWidth = proxy.size.width
                        availableHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        availableWidth = newSize.width
                        availableHeight = newSize.height
                    }
            }
        )
        .contextMenu { contextMenu }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hovering = true
                hoveringTopChrome = location.y <= 120
            case .ended:
                hovering = false
                hoveringTopChrome = false
            }
        }
        .onAppear {
            reduceMotionEnabled = accessibilityReduceMotion
            focusedID = nil
            model.focusedItemID = focusedID
            model.onSplitTitle = { caret in
                splitTitle(atUTF16Offset: caret)
            }
            model.onSplitItem = { id, caret in
                if let newID = model.splitItem(id, atUTF16Offset: caret) {
                    focusItem(newID, atUTF16Offset: 0)
                }
            }
            model.onMergeItemBackward = { id in
                if let item = model.items.first(where: { $0.id == id }) {
                    mergeBackward(item)
                }
            }
            model.onMergeItemForward = { id in
                mergeForward(id)
            }
            model.onRequestFocus = {
                if let first = displayedItems.first {
                    focusItem(first.id, atUTF16Offset: (first.text as NSString).length)
                }
            }
            model.onRequestLastItemFocus = {
                focusLastItemForTyping()
            }
            model.onToggleDoneVisibility = {
                toggleDoneTaskVisibility()
            }
            model.onMoveCaretToDocumentBoundary = { direction in
                if direction < 0 {
                    focusTitle(atUTF16Offset: 0)
                } else {
                    focusLastItemForTyping()
                }
            }
            model.onMoveCaretHorizontally = { sourceID, direction in
                moveCaretHorizontally(from: sourceID, direction: direction)
            }
            model.onMoveCaretVertically = { sourceID, direction, screenX in
                moveCaretVertically(from: sourceID, direction: direction, screenX: screenX)
            }
            model.onMultilinePaste = { lines, targetID in
                if let lastID = model.pasteLines(lines, after: targetID) {
                    let offset = model.items.first(where: { $0.id == lastID })
                        .map { ($0.text as NSString).length } ?? 0
                    focusItem(lastID, atUTF16Offset: offset)
                }
            }
            model.onWillSetDone = { id, isDone in
                prepareDoneTransition(id: id, isDone: isDone)
            }
            focusLastItemForTyping()
        }
        .onDisappear {
            model.onWillSetDone = nil
            model.onToggleDoneVisibility = nil
            cancelCompletionExitTasks()
        }
        .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
            reduceMotionEnabled = reduceMotion
        }
        .onChange(of: focusedID) { _, new in model.focusedItemID = new }
        .onChange(of: titleFocused) { _, new in model.isTitleFocused = new }
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
            Spacer().frame(height: 26)
            checklist
        }
        .padding(.horizontal, contentInset)
        // Leaves a calm, deliberate gap below the traffic lights instead
        // of letting the date compete with the window controls. Moving the
        // the chrome and content independently preserves this gap while the
        // shared horizontal inset keeps every left/right edge aligned.
        .padding(.top, 48)
        .padding(.bottom, 64) // clears the bottom hover toolbar, which now sits flush against the window edge
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The date sits on its own line above the title now — it used
            // to share the title's row (reserving a fixed slot beside it),
            // which ate into the title's width and made longer titles wrap
            // mid-word or get cut off. Up here it costs a line of height
            // instead, and the title gets the sticky's full width.
            Text(Self.dateFormatter.string(from: model.day))
                .font(bodyFont(14))
                .foregroundStyle(color.ink.opacity(0.3))

            // Gives the title an explicit maximum width budget — an
            // unconstrained TextField's ideal width just grows with its
            // content, so measuring that was circular and never actually
            // constrained anything (titles kept wrapping mid-word
            // regardless) — but deliberately no fixed *height*. A previous
            // version picked between a 58pt/108pt box using a "does it fit
            // on one line?" guess, on the assumption that "no" always means
            // "fits in two" — it doesn't (emoji + a few words can need
            // three), and since the box couldn't grow past whichever height
            // it guessed, real title text silently clipped out of view.
            // Leaving height alone lets the TextField report however tall
            // it genuinely needs to be, which is the only way to guarantee
            // that never happens again.
            let titleWidth = max(availableWidth - (contentInset * 2), 80)
            let titleSize = Self.titleFontSize(
                for: model.title, baseSize: AppSettings.shared.titleSize.baseSize, availableWidth: titleWidth
            )

            // Editable title — wraps naturally up to 3 lines (comfortably
            // covers "icon + a few words"; the shrink-to-fit below already
            // handles a single overlong word), Regular weight (Medium read
            // too bold). Steps down in size as the title gets longer (see
            // `titleFontSize`) so a single word that can't wrap (no space to
            // break on) shrinks instead of getting cut mid-word ("Admin" →
            // "Admi"/"n").
            TextField("To Do", text: titleBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.custom("HelveticaNeue", size: titleSize))
                .tracking(titleSize * -0.06) // -6% of size, same ratio at every step
                .foregroundStyle(color.titleInk)
                .tint(color.titleInk) // otherwise the cursor inherits the app's green accent — invisible on the green sticky
                .lineLimit(1...3)
                .lineSpacing(titleSize * -0.1) // ~90% line height, same ratio at every step
                // Return is handled by StickyController, which can see the
                // AppKit caret and split the title at the exact insertion point.
                .onKeyPress(.return) { .handled }
                .focused($titleFocused)
                .padding(.trailing, 6) // headroom for negative tracking on the last glyph
                // A fixed frame here makes the hosting view advertise the
                // current window width as its minimum. That turns every
                // horizontal expansion into a one-way ratchet. A flexible
                // maximum still gives wrapping a concrete budget without
                // preventing the native window from becoming narrower again.
                .frame(minWidth: 0, maxWidth: titleWidth, alignment: .topLeading)
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

    /// Familiar macOS traffic-light controls. They only materialize while the
    /// pointer is in the sticky's top 120pt, keeping the paper quiet the rest
    /// of the time. Closing hides the sticky; it never archives or deletes it.
    private var windowControls: some View {
        VStack {
            HStack(spacing: 4) {
                trafficLight(color: Color(red: 1.0, green: 0.37, blue: 0.34),
                             label: "Close sticky") {
                    controller.closeSticky()
                }
                trafficLight(color: Color(red: 1.0, green: 0.74, blue: 0.18),
                             label: "Minimize sticky") {
                    controller.minimizeSticky()
                }
                Spacer(minLength: 0)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The circle is vertically centered inside a 16pt hit frame, adding
        // 2pt above its 12pt visual. 22 + 2 = the same 24pt as the left edge.
        .padding(.top, contentInset - 2)
        .padding(.leading, contentInset)
        .opacity(hoveringTopChrome ? 1 : 0)
        .allowsHitTesting(hoveringTopChrome)
        .animation(.easeInOut(duration: 0.15), value: hoveringTopChrome)
    }

    private func trafficLight(color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay(Circle().stroke(.black.opacity(0.14), lineWidth: 0.5))
                .frame(width: 12, height: 12)
                .frame(width: 16, height: 16, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverFeedback(scale: 1, darkening: -0.08)
        .accessibilityLabel(label)
        .help(label)
    }

    // MARK: - Checklist

    /// Uses whatever vertical room the resized sticky leaves below the
    /// header. Every item remains available; overflow scrolls inside this
    /// area instead of being replaced by "N more" / "Show less".
    private var checklist: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayedItems) { item in
                        row(item).id(item.id)
                    }

                    addRowButton
                }
            }
            .coordinateSpace(name: "checklist")
            .onPreferenceChange(ChecklistRowFramePreferenceKey.self) { frames in
                rowFrames = frames
            }
            .scrollIndicators(.automatic)
            .onChange(of: focusedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: availableHeight) { _, _ in
                // A live shrink or a newly wrapped title can move the existing
                // caret outside the checklist viewport without changing focus.
                // Keep that row visible, but don't animate every resize tick.
                keepFocusedRowVisible(using: proxy)
            }
            .onChange(of: availableWidth) { _, _ in
                // Narrowing wraps both the title and checklist rows. Their
                // changed heights can displace the caret even though the
                // window's vertical dimension did not move.
                keepFocusedRowVisible(using: proxy)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func keepFocusedRowVisible(using proxy: ScrollViewProxy) {
        guard let focusedID,
              displayedItems.contains(where: { $0.id == focusedID })
        else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(focusedID, anchor: .center)
        }
    }

    private var doneTaskCount: Int {
        model.items.lazy.filter(\.isDone).count
    }

    /// Visibility is the only transformation applied here. Keeping a single
    /// source-ordered collection prevents completed rows from regrouping or
    /// acquiring a second SwiftUI identity when the eye toggle changes.
    private var displayedItems: [TodoItem] {
        model.orderedItems.filter {
            showsDoneTasks || !$0.isDone || retainedCompletionIDs.contains($0.id)
        }
    }

    /// Always-there "next row," kept in the same scrollable checklist.
    private var addRowButton: some View {
        let inkOpacity = addRowHovered ? 0.46 : 0.32

        return Button {
            let newID = model.addItem()
            focusItem(newID, atUTF16Offset: 0)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color.ink.opacity(inkOpacity))
                    .frame(width: 13, height: 24)
                    .frame(width: 24, alignment: .leading)
                Text("Add item")
                    .font(bodyFont(14))
                    .foregroundStyle(color.ink.opacity(inkOpacity))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(HoverMotion.feedback, value: addRowHovered)
        .onHover { addRowHovered = $0 }
    }

    private func row(_ item: TodoItem) -> some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 7) {
                    checkbox(item)
                    // Keep completed rows editable too. Because this stays the
                    // same TextField when isDone changes, its caret survives a
                    // keyboard toggle and Command-Return can toggle it back.
                    TextField("", text: textBinding(item), prompt: rowPrompt(item), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(bodyFont(14))
                        .foregroundStyle(item.isDone ? color.inkSecondary : color.ink.opacity(0.8))
                        .strikethrough(item.isDone, color: color.inkSecondary)
                        .tint(color.ink) // otherwise the cursor inherits the app's green accent — invisible on the green sticky
                        .lineLimit(1...12)
                        .focused($focusedID, equals: item.id)
                        .onChange(of: bindingValue(item)) { _, newValue in
                            handleDash(item, newValue)
                        }
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.command) {
                                toggleDone(item)
                            } else {
                                submit(item)
                            }
                            return .handled
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .padding(.vertical, 6)

                Rectangle()
                    .fill(color.divider)
                    .frame(height: 1)
            }
            .offset(y: draggingItemID == item.id ? dragTranslationY - dragLayoutCompensationY : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChecklistRowFramePreferenceKey.self,
                    value: [item.id: proxy.frame(in: .named("checklist"))]
                )
            }
        )
        .zIndex(draggingItemID == item.id ? 1 : 0)
        .transaction { transaction in
            if draggingItemID == item.id {
                transaction.animation = nil
            }
        }
        .transition(.opacity)
    }

    private func checkbox(_ item: TodoItem) -> some View {
        let isCheckboxHovered = hoveredCheckboxID == item.id
        let checkboxOpacity = isCheckboxHovered ? 0.42 : 0.3
        let checkboxScale: CGFloat
        if pressedCheckboxID == item.id && draggingItemID == nil {
            checkboxScale = 0.97
        } else if isCheckboxHovered && draggingItemID == nil && !accessibilityReduceMotion {
            checkboxScale = 1.1
        } else {
            checkboxScale = 1
        }
        let checkboxScaleAnchor: UnitPoint = pressedCheckboxID == item.id ? .center : .leading

        return Button {
            guard suppressCheckboxToggleID != item.id else { return }
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
                        .fill(color.ink.opacity(checkboxOpacity))
                        .frame(width: 13, height: 13)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color.paper)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(color.ink.opacity(checkboxOpacity), lineWidth: 1.1)
                        .frame(width: 13, height: 13)
                }
            }
            // Scale only the visual checkbox, not its hit frame. Anchoring
            // hover growth to the leading edge keeps it inside the scroll
            // view instead of clipping against that boundary.
            .scaleEffect(checkboxScale, anchor: checkboxScaleAnchor)
            .padding(.leading, 1)
            // The visual checkbox shares the exact left edge used by the
            // date and title, inset by one point so the centered border
            // stroke stays inside the scroll view's clipped leading edge.
            // The remaining width stays as an easy target.
            .frame(width: 24, height: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(HoverMotion.feedback, value: isCheckboxHovered)
        .onHover { hoveredCheckboxID = $0 ? item.id : nil }
        .simultaneousGesture(reorderGesture(for: item, togglesOnTap: true))
        .accessibilityLabel(
            item.isDone
                ? "Mark \(item.text.isEmpty ? "to-do" : item.text) not done"
                : "Mark \(item.text.isEmpty ? "to-do" : item.text) done"
        )
        .accessibilityAction(named: "Move up") {
            moveVisibleItem(item, by: -1)
        }
        .accessibilityAction(named: "Move down") {
            moveVisibleItem(item, by: 1)
        }
        .help("Click to toggle, drag to reorder")
    }

    private func reorderGesture(for item: TodoItem, togglesOnTap: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("checklist"))
            .onChanged { value in
                if togglesOnTap, draggingItemID == nil {
                    pressedCheckboxID = item.id
                }

                let threshold: CGFloat = togglesOnTap ? 7 : 2
                guard abs(value.translation.height) >= threshold else { return }

                if draggingItemID == nil {
                    beginReordering(item, value: value)
                }
                guard draggingItemID == item.id else { return }

                pressedCheckboxID = nil
                dragTranslationY = value.translation.height
                reorderIfNeeded(item, pointerY: value.location.y)
            }
            .onEnded { value in
                let wasDragging = draggingItemID == item.id
                pressedCheckboxID = nil

                if wasDragging {
                    finishReordering()
                }

                // A Button may deliver its action just after the simultaneous
                // drag ends. Keep suppression through this event turn, then
                // clear it whether or not the pointer was released over it.
                if togglesOnTap {
                    DispatchQueue.main.async {
                        if suppressCheckboxToggleID == item.id {
                            suppressCheckboxToggleID = nil
                        }
                    }
                }
            }
    }

    private func beginReordering(_ item: TodoItem, value: DragGesture.Value) {
        guard rowFrames[item.id] != nil else { return }
        focusedID = nil
        titleFocused = false
        draggingItemID = item.id
        if item.id == pressedCheckboxID {
            suppressCheckboxToggleID = item.id
        }
        dragTranslationY = value.translation.height
        dragLayoutCompensationY = 0
    }

    private func reorderIfNeeded(_ item: TodoItem, pointerY: CGFloat) {
        let visible = displayedItems
        guard let currentIndex = visible.firstIndex(where: { $0.id == item.id }),
              let sourceFrame = rowFrames[item.id]
        else { return }

        let target: TodoItem?
        if currentIndex + 1 < visible.count,
           let nextFrame = rowFrames[visible[currentIndex + 1].id],
           pointerY > nextFrame.midY {
            target = visible[currentIndex + 1]
        } else if currentIndex > 0,
                  let previousFrame = rowFrames[visible[currentIndex - 1].id],
                  pointerY < previousFrame.midY {
            target = visible[currentIndex - 1]
        } else {
            target = nil
        }

        guard let target, let targetFrame = rowFrames[target.id] else { return }
        let layoutDelta: CGFloat
        if targetFrame.midY > sourceFrame.midY {
            layoutDelta = targetFrame.maxY - sourceFrame.maxY
        } else {
            layoutDelta = targetFrame.minY - sourceFrame.minY
        }
        dragLayoutCompensationY += layoutDelta

        let animation: Animation? = accessibilityReduceMotion
            ? nil
            : .interactiveSpring(response: 0.3, dampingFraction: 1, blendDuration: 0)
        withAnimation(animation) {
            model.moveItem(item.id, relativeTo: target.id)
        }
    }

    private func finishReordering() {
        let animation: Animation? = accessibilityReduceMotion
            ? nil
            : .interactiveSpring(response: 0.3, dampingFraction: 1, blendDuration: 0)
        withAnimation(animation) {
            draggingItemID = nil
            dragTranslationY = 0
            dragLayoutCompensationY = 0
        }
    }

    /// VoiceOver exposes the same ordering operation without requiring a
    /// precision drag. Keep keyboard/accessibility moves immediate; repeated
    /// commands should never make the interface wait for an animation.
    private func moveVisibleItem(_ item: TodoItem, by offset: Int) {
        let visible = displayedItems
        guard let sourceIndex = visible.firstIndex(where: { $0.id == item.id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard visible.indices.contains(destinationIndex) else { return }
        model.moveItem(item.id, relativeTo: visible[destinationIndex].id)
    }

    private func toggleDone(_ item: TodoItem) {
        let wasDone = item.isDone
        controller.toggleDone(item.id)

        guard !wasDone, !showsDoneTasks, focusedID == item.id else { return }
        moveFocusAfterHiding(item.id)
    }

    /// Completion keeps the editor continuous: prefer the next unfinished row,
    /// then the previous one, and finally the title when the checklist is empty.
    /// Update the two FocusStates in one turn instead of clearing focus first so
    /// AppKit never spends a run-loop iteration without an insertion point.
    private func moveFocusAfterHiding(_ completedID: UUID) {
        let ordered = model.orderedItems
        guard let completedIndex = ordered.firstIndex(where: { $0.id == completedID }) else { return }

        let next = ordered[(completedIndex + 1)...].first(where: { !$0.isDone })
        let previous = ordered[..<completedIndex].last(where: { !$0.isDone })
        if let destination = next ?? previous {
            model.isTitleFocused = false
            model.focusedItemID = destination.id
            controller.placeCaretOnNextItemFocus(destination.id, atUTF16Offset: 0)
            titleFocused = false
            focusedID = destination.id
        } else {
            model.focusedItemID = nil
            model.isTitleFocused = true
            controller.placeCaretOnNextTitleFocus(atUTF16Offset: (model.title as NSString).length)
            focusedID = nil
            titleFocused = true
        }
    }

    private func prepareDoneTransition(id: UUID, isDone: Bool) {
        completionExitTasks[id]?.cancel()
        completionExitTasks[id] = nil
        completionExitGenerations[id] = nil

        let suppressesTransition = controller.isReplayingCompletionHistory
        guard isDone, !showsDoneTasks, !suppressesTransition else {
            retainedCompletionIDs.remove(id)
            return
        }

        retainedCompletionIDs.insert(id)
        let generation = UUID()
        completionExitGenerations[id] = generation
        completionExitTasks[id] = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }

            guard completionExitGenerations[id] == generation else { return }
            guard model.items.first(where: { $0.id == id })?.isDone == true else {
                retainedCompletionIDs.remove(id)
                completionExitTasks[id] = nil
                completionExitGenerations[id] = nil
                return
            }

            if reduceMotionEnabled {
                retainedCompletionIDs.remove(id)
            } else {
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)) {
                    _ = retainedCompletionIDs.remove(id)
                }
            }
            guard completionExitGenerations[id] == generation else { return }
            completionExitTasks[id] = nil
            completionExitGenerations[id] = nil
        }
    }

    private func cancelCompletionExitTasks() {
        for task in completionExitTasks.values {
            task.cancel()
        }
        completionExitTasks.removeAll()
        completionExitGenerations.removeAll()
        retainedCompletionIDs.removeAll()
    }

    // MARK: - Color picker

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(22)), count: 5), spacing: 10) {
            ForEach(StickyColor.allCases) { c in
                colorSwatchButton(c)
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

    private func toggleDoneTaskVisibility() {
        guard doneTaskCount > 0 else { return }

        if showsDoneTasks,
           let focusedID,
           model.items.first(where: { $0.id == focusedID })?.isDone == true {
            self.focusedID = nil
        }

        if accessibilityReduceMotion {
            showsDoneTasks.toggle()
        } else {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) {
                showsDoneTasks.toggle()
            }
        }
    }

    private var bottomToolbar: some View {
        VStack {
            Spacer()
            HStack(spacing: 18) {
                Button { toggleDoneTaskVisibility() } label: {
                    Image(systemName: showsDoneTasks ? "eye" : "eye.slash")
                }
                .disabled(doneTaskCount == 0)
                .opacity(doneTaskCount == 0 ? 0.25 : 1)
                .hoverFeedback(scale: 1.1, darkening: -0.05, isEnabled: doneTaskCount > 0)
                .accessibilityLabel(showsDoneTasks ? "Hide done items" : "Show done items")
                .help(showsDoneTasks ? "Hide done items (⌘S)" : "Show \(doneTaskCount) done items (⌘S)")

                Button { showColors.toggle() } label: { Image(systemName: "paintpalette") }
                    .hoverFeedback(scale: 1.1, darkening: -0.05)
                    .popover(isPresented: $showColors, arrowEdge: .top) {
                        colorPicker
                    }

                Button { controller.requestClose() } label: {
                    Image(systemName: "archivebox")
                }
                .hoverFeedback(scale: 1.1, darkening: -0.05)
                .accessibilityLabel("Archive or delete sticky")
                .help("Archive or delete sticky")
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
            .allowsHitTesting(hovering)
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
        Divider()
        Button("New Sticky") { controller.requestNewSticky() }
        Button("Archive or Delete Sticky…", role: .destructive) { controller.requestClose() }
    }

    // MARK: - Editing helpers

    private func submit(_ item: TodoItem) {
        guard !isBlank(bindingValue(item)) else { return }
        let newID = model.addItem(after: item)
        focusItem(newID, atUTF16Offset: 0)
    }

    /// Crosses title/item boundaries after AppKit has exhausted the wrapped
    /// visual lines within the current field. The controller restores the
    /// caret at the closest screen-space x on the destination edge.
    private func moveCaretVertically(from sourceID: UUID?, direction: Int, screenX: CGFloat) {
        let ordered = displayedItems
        if sourceID == nil {
            guard direction > 0, let first = ordered.first else { return }
            focusItem(first.id, alignedToScreenX: screenX, entering: .top)
            return
        }

        guard let sourceID, let index = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        if direction < 0 {
            if index == 0 {
                focusTitle(alignedToScreenX: screenX, entering: .bottom)
            } else {
                focusItem(ordered[index - 1].id, alignedToScreenX: screenX, entering: .bottom)
            }
        } else if index + 1 < ordered.count {
            focusItem(ordered[index + 1].id, alignedToScreenX: screenX, entering: .top)
        }
    }

    /// Left/Right at a field boundary continues into the adjacent text block,
    /// exactly as if the title and checklist were one continuous document.
    private func moveCaretHorizontally(from sourceID: UUID?, direction: Int) {
        let ordered = displayedItems
        if sourceID == nil {
            guard direction > 0, let first = ordered.first else { return }
            focusItem(first.id, atUTF16Offset: 0)
            return
        }

        guard let sourceID, let index = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        if direction < 0 {
            if index == 0 {
                focusTitle(atUTF16Offset: (model.title as NSString).length)
            } else {
                let previous = ordered[index - 1]
                focusItem(previous.id, atUTF16Offset: (previous.text as NSString).length)
            }
        } else if index + 1 < ordered.count {
            focusItem(ordered[index + 1].id, atUTF16Offset: 0)
        }
    }

    private func focusTitle(atUTF16Offset offset: Int) {
        focusedID = nil
        titleFocused = false
        DispatchQueue.main.async {
            model.focusedItemID = nil
            model.isTitleFocused = true
            controller.placeCaretOnNextTitleFocus(atUTF16Offset: offset)
            titleFocused = true
        }
    }

    private func focusTitle(alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        focusedID = nil
        titleFocused = false
        DispatchQueue.main.async {
            model.focusedItemID = nil
            model.isTitleFocused = true
            controller.placeCaretOnNextTitleFocus(alignedToScreenX: screenX, entering: edge)
            titleFocused = true
        }
    }

    private func focusItem(_ id: UUID, atUTF16Offset offset: Int) {
        titleFocused = false
        focusedID = nil
        DispatchQueue.main.async {
            model.isTitleFocused = false
            model.focusedItemID = id
            controller.placeCaretOnNextItemFocus(id, atUTF16Offset: offset)
            focusedID = id
        }
    }

    private func focusItem(_ id: UUID, alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        titleFocused = false
        focusedID = nil
        DispatchQueue.main.async {
            model.isTitleFocused = false
            model.focusedItemID = id
            controller.placeCaretOnNextItemFocus(id, alignedToScreenX: screenX, entering: edge)
            focusedID = id
        }
    }

    /// Restores the text-editing flow when Return is pressed while the sticky
    /// window, rather than one of its fields, owns keyboard focus.
    private func focusLastItemForTyping() {
        let targetID: UUID
        let caret: Int
        if let last = displayedItems.last {
            targetID = last.id
            caret = (last.text as NSString).length
        } else {
            targetID = model.addItem()
            caret = 0
        }

        focusItem(targetID, atUTF16Offset: caret)
    }

    /// Return in the title creates the first checklist line. If the sticky's
    /// existing invitation row is empty, reuse it instead of creating two
    /// blank rows. Text after the caret moves into the new line.
    private func splitTitle(atUTF16Offset offset: Int) {
        let title = model.title as NSString
        let split = min(max(offset, 0), title.length)
        let prefix = title.substring(to: split)
        let suffix = title.substring(from: split)

        model.setTitle(prefix)
        let targetID: UUID
        if let first = model.orderedItems.first, isBlank(bindingValue(first)) {
            model.setText(first.id, suffix)
            targetID = first.id
        } else {
            let item = TodoItem(text: suffix)
            model.items.insert(item, at: 0)
            model.onChange?()
            targetID = item.id
        }

        // The first row is commonly still stored in `focusedID` from when
        // the sticky appeared. Assigning that same ID while the title owns
        // first responder does not trigger a SwiftUI focus change, so clear
        // it first and restore it on the next run-loop turn. Arm the caret
        // immediately before that restoration so an outgoing title
        // selection notification cannot consume it.
        focusItem(targetID, atUTF16Offset: 0)
    }

    /// Backspace at column zero joins an item to its preceding text block.
    /// The first row joins the title; every other row joins the prior item.
    private func mergeBackward(_ item: TodoItem) {
        let visible = displayedItems
        guard let visibleIndex = visible.firstIndex(where: { $0.id == item.id }) else { return }
        let itemText = bindingValue(item)

        if visibleIndex == 0 {
            let join = (model.title as NSString).length
            model.setTitle(model.title + itemText)
            model.delete(item.id)
            focusTitle(atUTF16Offset: join)
        } else {
            let previous = visible[visibleIndex - 1]
            let join = (previous.text as NSString).length
            model.setText(previous.id, previous.text + itemText)
            model.delete(item.id)
            focusItem(previous.id, atUTF16Offset: join)
        }
    }

    /// Forward Delete at the end of a row joins the next visible row into it.
    /// The current row keeps its identity and the caret stays at the join.
    private func mergeForward(_ id: UUID) {
        let visible = displayedItems
        guard let index = visible.firstIndex(where: { $0.id == id }),
              index + 1 < visible.count,
              let join = model.mergeItemForward(id, with: visible[index + 1].id)
        else { return }

        controller.restoreCaretInCurrentEditor(atUTF16Offset: join)
    }

    private func handleDash(_ item: TodoItem, _ value: String) {
        if value == "-" {
            model.setText(item.id, "")
            let newID = model.addItem(after: item)
            focusItem(newID, atUTF16Offset: 0)
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

    /// The first blank row should look and behave like an invitation to
    /// type, rather than an invisible one-character click target.
    private func rowPrompt(_ item: TodoItem) -> Text? {
        guard item.id == displayedItems.first?.id,
              bindingValue(item).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return Text("Add a to-do…").foregroundStyle(color.ink.opacity(0.32))
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
