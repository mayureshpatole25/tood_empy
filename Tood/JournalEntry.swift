import Foundation

/// One day's journal writing — the "single daily journal card" from the
/// design: there's exactly one entry per calendar day, not a running feed.
/// Re-editing the same day updates `text`/`updatedAt` in place.
struct JournalEntry: Codable, Identifiable, Equatable {
    var id: UUID
    /// Normalized to the start of the day this entry belongs to.
    var day: Date
    var text: String
    var createdAt: Date
    var updatedAt: Date
    /// Set once, the first time an entry is saved with location access granted.
    var locationLabel: String?

    init(day: Date, text: String = "", createdAt: Date = Date(), updatedAt: Date = Date(),
         locationLabel: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.day = day
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.locationLabel = locationLabel
    }
}
