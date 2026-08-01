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
    /// Preserves creation order for the status menu / cascading.
    private(set) var order: [UUID] = []
    /// The sticky most recently brought to front or clicked into — what the
    /// global "show active sticky" shortcut jumps to.
    private(set) var mostRecentlyActiveID: UUID?

    @ObservationIgnored private let persistence = PersistenceService()
    let archive = ArchiveService()
    @ObservationIgnored private var rollover: RolloverScheduler?

    @ObservationIgnored private var saveTimer: Timer?

    init() {
        rollover = RolloverScheduler(onRollover: { [weak self] in self?.performRollover() })
    }

    // MARK: - Lifecycle

    func restoreAll() {
        if !persistence.hasSavedFile {
            newSticky() // true first run: give Renee a note to type into
        } else {
            // File exists — respect it even if empty (all stickies deleted).
            for data in persistence.load() {
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
        controllers[model.id]?.bringToFront()
        scheduleSave()
    }

    func remove(_ id: UUID) {
        controllers[id]?.panel.orderOut(nil)
        controllers[id]?.panel.close()
        controllers[id] = nil
        order.removeAll { $0 == id }
        scheduleSave()
    }

    func showAll() { for c in controllers.values { c.show() } }
    func hideAll() { for c in controllers.values { c.hide() } }

    /// Deletes every sticky. Irreversible, same as closing one — the caller
    /// (the status menu) is responsible for confirming with the user first.
    func removeAll() {
        for id in order { remove(id) }
    }

    func bringToFront(_ id: UUID) {
        controllers[id]?.bringToFront()
        noteActive(id)
    }

    /// Called by `StickyController` (bringToFront, or the window becoming
    /// key from a plain click) so "show active sticky" always jumps to
    /// whichever one you actually used last.
    func noteActive(_ id: UUID) { mostRecentlyActiveID = id }

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

    /// (title, id) pairs in creation order for the status menu.
    func stickyList() -> [(title: String, id: UUID)] {
        order.compactMap { id in
            guard let c = controllers[id] else { return nil }
            let items = c.model.items.filter { !$0.text.isEmpty }
            let label = items.first?.text ?? c.model.title
            return (String(label.prefix(30)), id)
        }
    }

    // MARK: - Dashboard stats

    /// All non-empty, unchecked items across every open sticky.
    var unfinishedTaskCount: Int {
        order.reduce(into: 0) { count, id in
            count += controllers[id]?.model.items.filter { !$0.isDone && !$0.text.isEmpty }.count ?? 0
        }
    }

    /// Checked-off today — counts both still-live done items (not yet swept
    /// into the archive by tonight's rollover) and anything already archived
    /// today, so the number is right whichever side of rollover you're on.
    var tasksCompletedToday: Int {
        let cal = Calendar.current
        let liveToday = order.reduce(into: 0) { count, id in
            count += controllers[id]?.model.items.filter {
                $0.isDone && $0.completedAt.map { cal.isDateInToday($0) } == true
            }.count ?? 0
        }
        let archivedToday = archive.load().filter {
            $0.completedAt.map { cal.isDateInToday($0) } == true
        }.count
        return liveToday + archivedToday
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

    func saveNow() {
        let snapshots = order.compactMap { controllers[$0]?.model.snapshot() }
        persistence.save(snapshots)
    }

    // MARK: - Rollover

    /// Move completed items into the archive; keep unfinished; advance the day.
    private func performRollover() {
        var archived: [ArchivedItem] = []
        let now = Date()
        for id in order {
            guard let model = controllers[id]?.model else { continue }
            let done = model.items.filter { $0.isDone }
            for item in done where !item.text.isEmpty {
                archived.append(ArchivedItem(
                    id: item.id, text: item.text,
                    stickyID: model.id, stickyTitle: model.title,
                    completedAt: item.completedAt, archivedOn: now))
            }
            model.items.removeAll { $0.isDone }
            model.day = now
        }
        archive.append(archived)
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
        let cardWidth: CGFloat = 378
        let cardHeight: CGFloat = 490
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
