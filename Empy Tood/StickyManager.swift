import AppKit
import Observation

/// Owns every sticky controller and the shared services. Handles restore,
/// create, remove, show/hide, debounced saving, and the day rollover.
/// `@Observable` so the Home dashboard reflects sticky/task changes live —
/// same source of truth the floating stickies themselves use, nothing
/// duplicated for the dashboard.
@MainActor
@Observable
final class StickyManager {
    private(set) var controllers: [UUID: StickyController] = [:]
    /// User-controlled order for Home, the status menu, Control-number
    /// shortcuts, persistence, and new-sticky cascading.
    private(set) var order: [UUID] = []
    /// The sticky most recently brought to front or clicked into — what the
    /// global "show active sticky" shortcut jumps to.
    private(set) var mostRecentlyActiveID: UUID?
    /// The whole-sticky archive is observable alongside live controllers so
    /// Home updates the moment an archive operation succeeds.
    private(set) var archivedStickies: [ArchivedSticky] = []

    @ObservationIgnored private let persistence = PersistenceService()
    let stickyArchive = StickyArchiveService()
    @ObservationIgnored private var rollover: RolloverScheduler?

    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private let lastActiveDefaultsKey = "today.lastActiveStickyID"
    @ObservationIgnored private var recentlyClosedIDs: [UUID] = []
    @ObservationIgnored var onOpenHome: (() -> Void)?

    init() {
        refreshArchivedStickies()
        rollover = RolloverScheduler(onRollover: { [weak self] in self?.performRollover() })
    }

    // MARK: - Lifecycle

    func restoreAll() {
        if !persistence.hasSavedFile {
            // True first run: seed a note to type into, but keep it hidden —
            // StickyController's init shows any controller whose model is
            // already isVisible, which used to flash this on screen before
            // onboarding even started. The "Sticky" step is what's supposed
            // to reveal it, via its own explicit bringToFront().
            let model = StickyModel.makeNew(at: cascadeOrigin(), color: .nextNewStickyColor())
            model.isVisible = false
            addController(for: model)
            scheduleSave()
        } else {
            // File exists — respect it even if empty (all stickies deleted).
            // Restore at most the one sticky that was last active. A sticky
            // that was closed stays closed, and several windows can never
            // flood the desktop just because they were visible at shutdown.
            let saved = persistence.load()
            let savedLastActiveID = UserDefaults.standard
                .string(forKey: lastActiveDefaultsKey)
                .flatMap(UUID.init(uuidString:))
            let restoreID = savedLastActiveID.flatMap { id in
                saved.contains(where: { $0.id == id && $0.isVisible }) ? id : nil
            } ?? saved.last(where: \.isVisible)?.id

            mostRecentlyActiveID = restoreID
            for var data in saved {
                data.isVisible = data.id == restoreID
                let model = StickyModel(data: data)
                addController(for: model)
            }
        }
        rollover?.start()
    }

    private func addController(for model: StickyModel) {
        let controller = StickyController(model: model, manager: self)
        controllers[model.id] = controller
        order.append(model.id)
    }

    // MARK: - Commands

    func newSticky() {
        let origin = cascadeOrigin()
        let model = StickyModel.makeNew(at: origin, color: .nextNewStickyColor())
        addController(for: model)
        controllers[model.id]?.focusForTyping()
        noteActive(model.id)
        scheduleSave()
    }

    /// Creates a titled sticky for command-palette workflows. The caller
    /// decides when to reveal it so the palette can close before focus moves.
    @discardableResult
    func createNamedSticky(_ rawTitle: String) -> UUID? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let model = StickyModel.makeNew(at: cascadeOrigin(), color: .nextNewStickyColor())
        model.title = title
        model.isVisible = false
        addController(for: model)
        saveNow()
        return model.id
    }

    func remove(_ id: UUID) {
        controllers[id]?.panel.orderOut(nil)
        controllers[id]?.panel.close()
        controllers[id] = nil
        order.removeAll { $0 == id }
        recentlyClosedIDs.removeAll { $0 == id }
        scheduleSave()
    }

    /// Snapshots the sticky into `stickyArchive` — a full copy (title,
    /// items, color, day) kept as a browsable memory — then removes it the
    /// same way `remove(_:)` does. The close confirmation is what actually
    /// decides archive vs. delete; this just also keeps a copy.
    func archive(_ id: UUID) {
        guard let model = controllers[id]?.model else { return }
        let entry = ArchivedSticky(id: model.id, data: model.snapshot(), archivedAt: Date())
        guard stickyArchive.append(entry) else { return }
        refreshArchivedStickies()
        remove(id)
        // Archiving moves data between two files. Persist the removal now so
        // quitting before the normal debounce cannot resurrect a live copy.
        saveNow()
    }

    /// Returns a whole archived sticky to the desktop. The live store is
    /// written before the archive entry is removed, so an interrupted restore
    /// can leave a harmless duplicate but can never lose the sticky.
    func restoreArchived(_ entry: ArchivedSticky) {
        var data = entry.data
        // Older interrupted archive operations may have left this identifier
        // in both stores. Restore it as a distinct sticky instead of making
        // the button silently do nothing.
        if controllers[data.id] != nil {
            data.id = UUID()
        }
        data.isVisible = true
        let model = StickyModel(data: data)
        addController(for: model)
        controllers[model.id]?.focusForTyping()
        noteActive(model.id)
        guard saveNow() else { return }
        guard stickyArchive.delete(entry.id) else { return }
        refreshArchivedStickies()
    }

    func deleteArchived(_ id: UUID) {
        guard stickyArchive.delete(id) else { return }
        refreshArchivedStickies()
    }

    private func refreshArchivedStickies() {
        archivedStickies = stickyArchive.load().sorted { $0.archivedAt > $1.archivedAt }
    }

    /// Gathers every sticky onto the Space where the command was invoked.
    /// Keep the application inactive while ordering so the user's current
    /// Space remains the destination. The most recently used sticky is
    /// ordered last and therefore remains at the front of the gathered set.
    func showAll() {
        var orderedControllers = order.compactMap { controllers[$0] }
        if let activeID = mostRecentlyActiveID,
           let activeIndex = orderedControllers.firstIndex(where: { $0.model.id == activeID }) {
            orderedControllers.append(orderedControllers.remove(at: activeIndex))
        }
        for controller in orderedControllers {
            controller.gatherToActiveSpace()
        }
        scheduleSave()
    }
    func hideAll() { for c in controllers.values { c.hide() } }

    var openStickyCount: Int {
        controllers.values.reduce(into: 0) { count, controller in
            if controller.model.isVisible { count += 1 }
        }
    }

    /// Organises only the stickies that are currently open. Hidden stickies
    /// keep their saved size and position. Every layout targets the display
    /// containing the most recently active open sticky, falling back to the
    /// newest open sticky and then the main display.
    func arrangeOpenStickies(_ arrangement: StickyArrangement) {
        let openControllers = order.compactMap { id -> StickyController? in
            guard let controller = controllers[id], controller.model.isVisible else { return nil }
            return controller
        }
        guard !openControllers.isEmpty,
              let screen = arrangementScreen(for: openControllers) else { return }

        let frames = StickyArrangementLayout.frames(
            for: arrangement,
            currentFrames: openControllers.map(\.panel.frame),
            in: screen.visibleFrame
        )
        for (controller, frame) in zip(openControllers, frames) {
            controller.arrange(to: frame, on: screen)
        }
        orderArrangedControllers(openControllers, for: arrangement)
        scheduleSave()
    }

    /// Hides a sticky without deleting it and remembers the close order so
    /// Shift-Command-T can restore windows just like reopening a closed tab.
    func close(_ id: UUID) {
        guard let controller = controllers[id], controller.model.isVisible else { return }
        recentlyClosedIDs.removeAll { $0 == id }
        recentlyClosedIDs.append(id)
        controller.hide()
    }

    func reopenLastClosedSticky() {
        while let id = recentlyClosedIDs.popLast() {
            guard let controller = controllers[id], !controller.model.isVisible else { continue }
            controller.focusForTyping()
            noteActive(id)
            return
        }
    }

    func openHome() {
        onOpenHome?()
    }

    /// Deletes every sticky. Irreversible, same as closing one — the caller
    /// (the status menu) is responsible for confirming with the user first.
    func removeAll() {
        for id in order { remove(id) }
    }

    func bringToFront(_ id: UUID) {
        controllers[id]?.focusForTyping()
        noteActive(id)
    }

    /// Focuses one of the first ten stickies in the same creation order used
    /// by the status menu. Returns false when that numbered slot is empty so
    /// an otherwise unrelated Control-number event can continue normally.
    @discardableResult
    func focusSticky(atShortcutIndex index: Int) -> Bool {
        guard (0..<StickySelectionShortcut.maximumStickyCount).contains(index),
              order.indices.contains(index),
              let controller = controllers[order[index]] else { return false }
        controller.focusForTyping()
        noteActive(controller.model.id)
        return true
    }

    /// Moves a sticky to its final list index. Persist immediately because
    /// the order also determines the Control-number shortcuts.
    @discardableResult
    func moveSticky(_ id: UUID, to destinationIndex: Int) -> Bool {
        guard controllers[id] != nil,
              StickyOrder.move(id, to: destinationIndex, in: &order) else { return false }
        saveNow()
        return true
    }

    /// Called by `StickyController` (bringToFront, or the window becoming
    /// key from a plain click) so "show active sticky" always jumps to
    /// whichever one you actually used last.
    func noteActive(_ id: UUID) {
        mostRecentlyActiveID = id
        UserDefaults.standard.set(id.uuidString, forKey: lastActiveDefaultsKey)
    }

    /// Used by app launch/reopen. It focuses the last sticky that is already
    /// open, but never resurrects a sticky the user closed and never creates
    /// a replacement when all stickies are closed.
    func focusLastOpenSticky() {
        let id = mostRecentlyActiveID.flatMap { id in
            controllers[id]?.model.isVisible == true ? id : nil
        } ?? order.reversed().first(where: { controllers[$0]?.model.isVisible == true })
        guard let id, let controller = controllers[id] else { return }
        controller.focusForTyping()
    }

    /// The global shortcut: jump to whatever sticky you were last in, or the
    /// most recently created one, or make a brand new one if none exist —
    /// always ends with a sticky on screen, focused and ready to type into.
    func showActiveSticky() {
        NSApp.activate(ignoringOtherApps: true)
        if let id = mostRecentlyActiveID, let c = controllers[id] {
            c.focusForTyping()
        } else if let id = order.last, let c = controllers[id] {
            c.focusForTyping()
        } else {
            newSticky()
        }
    }

    /// (title, id) pairs in the persisted user-controlled order.
    func stickyList() -> [(title: String, id: UUID)] {
        order.compactMap { id in
            guard let c = controllers[id] else { return nil }
            let title = c.model.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = title.isEmpty ? "To Do" : title
            return (String(label.prefix(30)), id)
        }
    }

    /// Quick capture also needs the paper colour so assignment feedback can
    /// visually connect the capture panel to its destination sticky.
    func quickCaptureDestinations() -> [QuickCaptureDestination] {
        order.compactMap { id in
            guard let model = controllers[id]?.model else { return nil }
            let title = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return QuickCaptureDestination(
                id: id,
                title: String((title.isEmpty ? "To Do" : title).prefix(30)),
                color: model.color
            )
        }
    }

    /// Stores a task from the global quick-capture panel without revealing or
    /// focusing its destination sticky. A newly created destination starts
    /// hidden so capture never interrupts the app the user was working in.
    @discardableResult
    func captureItem(_ rawText: String, in stickyID: UUID?, newStickyTitle: String?) -> UUID? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let stickyID, let model = controllers[stickyID]?.model {
            model.addCapturedItem(text)
            saveNow()
            return stickyID
        }

        let title = newStickyTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return nil }

        let model = StickyModel.makeNew(at: cascadeOrigin(), color: .nextNewStickyColor())
        model.title = title
        model.items = [TodoItem(text: text)]
        model.isVisible = false
        addController(for: model)
        saveNow()
        return model.id
    }

    // MARK: - Dashboard stats

    /// All non-empty, unchecked items across every open sticky.
    var unfinishedTaskCount: Int {
        order.reduce(into: 0) { count, id in
            count += controllers[id]?.model.items.filter { !$0.isDone && !$0.text.isEmpty }.count ?? 0
        }
    }

    /// Checked-off today across live and whole-sticky archived items.
    var tasksCompletedToday: Int {
        let cal = Calendar.current
        return completedItemsDisplay().lazy.filter { cal.isDateInToday($0.completedAt) }.count
    }

    /// Every retained completion with its sticky color. Whole-sticky archive
    /// entries are included because archiving a sticky should not erase its
    /// contribution to insights.
    func completedItemsDisplay() -> [CompletedTaskDisplay] {
        var result: [CompletedTaskDisplay] = []
        for id in order {
            guard let model = controllers[id]?.model else { continue }
            for item in model.items where item.isDone && !item.text.isEmpty {
                guard let completedAt = item.completedAt else { continue }
                result.append(CompletedTaskDisplay(id: item.id, text: item.text, color: model.color, completedAt: completedAt))
            }
        }
        for sticky in archivedStickies {
            for item in sticky.data.items where item.isDone && !item.text.isEmpty {
                guard let completedAt = item.completedAt else { continue }
                result.append(CompletedTaskDisplay(id: item.id, text: item.text, color: sticky.data.colorID, completedAt: completedAt))
            }
        }
        return result.sorted { $0.completedAt < $1.completedAt }
    }

    func completedTodayDisplay() -> [CompletedTaskDisplay] {
        let cal = Calendar.current
        return completedItemsDisplay().filter { cal.isDateInToday($0.completedAt) }
    }

    /// A handful of currently open (unchecked, non-empty) items across every
    /// sticky — used by the insight card's zero-state, so a slow day still
    /// has something concrete to show instead of an empty list.
    func openItemsDisplay(limit: Int) -> [OpenTaskDisplay] {
        var result: [OpenTaskDisplay] = []
        for id in order {
            guard let model = controllers[id]?.model else { continue }
            for item in model.items where !item.isDone && !item.text.isEmpty {
                result.append(OpenTaskDisplay(id: item.id, text: item.text))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    // MARK: - Persistence (debounced)

    func scheduleSave() {
        saveTimer?.invalidate()
        let t = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.saveNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        saveTimer = t
    }

    @discardableResult
    func saveNow() -> Bool {
        saveTimer?.invalidate()
        saveTimer = nil
        let snapshots = order.compactMap { controllers[$0]?.model.snapshot() }
        return persistence.save(snapshots)
    }

    // MARK: - Rollover

    /// Advance the sticky day without removing its completed items. Their
    /// completion timestamps are the source of truth for visibility and stats.
    private func performRollover() {
        let now = Date()
        for id in order {
            guard let model = controllers[id]?.model else { continue }
            model.day = now
        }
        saveNow()
    }

    // MARK: - Helpers

    /// Tiles new stickies into a grid across the screen — like laying down
    /// cards — starting from whichever corner is set in the status menu.
    /// Columns sit side by side with no overlap; rows fan upward into the
    /// row above, close enough that only each card's title/date/first item
    /// peeks out, but never hiding a whole card.
    private func cascadeOrigin() -> CGPoint {
        guard let screen = NSScreen.main else { return CGPoint(x: 200, y: 200) }
        let visible = screen.visibleFrame
        let cardWidth = StickyWindowGeometry.defaultSize.width
        let cardHeight = StickyWindowGeometry.defaultSize.height
        let gutter: CGFloat = 24
        let rowStep: CGFloat = 210 // << cardHeight — rows overlap like a fanned stack

        let cols = max(1, Int((visible.width + gutter) / (cardWidth + gutter)))
        let n = order.count
        let colOffset = CGFloat(n % cols) * (cardWidth + gutter)
        let rowOffset = CGFloat(n / cols) * rowStep

        let x: CGFloat
        let y: CGFloat
        switch StickyCorner.startCorner {
        case .topLeft:
            x = visible.minX + gutter + colOffset
            y = visible.maxY - gutter - cardHeight - rowOffset
        case .topRight:
            x = visible.maxX - gutter - cardWidth - colOffset
            y = visible.maxY - gutter - cardHeight - rowOffset
        case .bottomLeft:
            x = visible.minX + gutter + colOffset
            y = visible.minY + gutter + rowOffset
        case .bottomRight:
            x = visible.maxX - gutter - cardWidth - colOffset
            y = visible.minY + gutter + rowOffset
        }
        return CGPoint(x: x, y: y)
    }

    private func arrangementScreen(for openControllers: [StickyController]) -> NSScreen? {
        if let id = mostRecentlyActiveID,
           let controller = controllers[id],
           controller.model.isVisible,
           let screen = controller.panel.screen {
            return screen
        }
        return openControllers.reversed().compactMap(\.panel.screen).first
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func orderArrangedControllers(
        _ arrangedControllers: [StickyController],
        for arrangement: StickyArrangement
    ) {
        let backToFront: [StickyController]
        if arrangement == .vertical {
            // `orderFront` is applied back-to-front. Sorting by the actual
            // arranged y-position guarantees the spatially highest sticky is
            // deepest in the z-order; every lower sticky then exposes the
            // title strip of the one immediately above it.
            backToFront = arrangedControllers.sorted {
                $0.panel.frame.maxY > $1.panel.frame.maxY
            }
        } else if arrangement == .pile {
            // Frames travel down and right. Put that lower-right end behind
            // the upper-left anchor so the visible pile recedes 45° to the
            // right; the opposite z-order makes the exposed edges read left.
            backToFront = Array(arrangedControllers.reversed())
        } else {
            backToFront = arrangedControllers
        }
        for controller in backToFront { controller.panel.orderFront(nil) }
    }
}

/// Which screen corner new stickies tile out from. Set from the status menu.
enum StickyCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    private static let defaultsKey = "today.newStickyCorner"

    static var startCorner: StickyCorner {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(StickyCorner.init) ?? .topLeft }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
