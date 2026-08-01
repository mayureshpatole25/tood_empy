import Foundation
import Observation

/// Owns the journal's one-entry-per-day model. `@Observable` so the Home
/// screen's journal card updates live, same pattern as `StickyManager`.
@MainActor
@Observable
final class JournalStore {
    private(set) var entries: [JournalEntry] = []

    @ObservationIgnored private let persistence = JournalPersistenceService()
    @ObservationIgnored private var saveTimer: Timer?

    init() {
        entries = persistence.load()
    }

    /// The single card for today — nil until the first word is written.
    var todaysEntry: JournalEntry? {
        entries.first { Calendar.current.isDateInToday($0.day) }
    }

    var todaysText: String { todaysEntry?.text ?? "" }

    /// Called on every keystroke from the journal's text view, same
    /// live-binding pattern as a sticky's checklist text.
    func updateTodaysText(_ text: String) {
        if let idx = entries.firstIndex(where: { Calendar.current.isDateInToday($0.day) }) {
            entries[idx].text = text
            entries[idx].updatedAt = Date()
        } else {
            guard !text.isEmpty else { return } // don't create an entry just because the field was focused
            entries.append(JournalEntry(day: Calendar.current.startOfDay(for: Date()), text: text))
            stampLocationIfEnabled()
        }
        scheduleSave()
    }

    /// One-shot, only on the day's first save — never re-stamps on later edits.
    private func stampLocationIfEnabled() {
        guard AppSettings.shared.journalLocationEnabled else { return }
        LocationStamper.shared.requestLabel { [weak self] label in
            guard let self, let label,
                  let idx = self.entries.firstIndex(where: { Calendar.current.isDateInToday($0.day) })
            else { return }
            self.entries[idx].locationLabel = label
            self.scheduleSave()
        }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.persistence.save(self.entries)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        saveTimer = t
    }
}
