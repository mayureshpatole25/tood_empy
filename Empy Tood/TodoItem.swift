import Foundation

/// A single checklist line. Named `TodoItem` to avoid colliding with Swift's `Task`.
struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool
    /// Set when the item is completed — used for archiving and sort order.
    var completedAt: Date?

    init(id: UUID = UUID(), text: String = "", isDone: Bool = false, completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.completedAt = completedAt
    }
}
