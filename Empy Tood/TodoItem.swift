import Foundation

/// A single checklist line. Named `TodoItem` to avoid colliding with Swift's `Task`.
struct TodoItem: Identifiable, Codable, Equatable {
    static let maximumIndentLevel = 3

    let id: UUID
    var text: String
    var isDone: Bool
    /// Set when the item is completed — used for archiving and sort order.
    var completedAt: Date?
    /// Zero is a top-level task. Each level is rendered 24 points farther in.
    var indentLevel: Int

    init(
        id: UUID = UUID(),
        text: String = "",
        isDone: Bool = false,
        completedAt: Date? = nil,
        indentLevel: Int = 0
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.completedAt = completedAt
        self.indentLevel = Self.clampedIndentLevel(indentLevel)
    }

    mutating func adjustIndent(by change: Int) {
        indentLevel = Self.clampedIndentLevel(indentLevel + change)
    }

    private static func clampedIndentLevel(_ level: Int) -> Int {
        min(max(level, 0), maximumIndentLevel)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isDone, completedAt, indentLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        indentLevel = Self.clampedIndentLevel(
            try container.decodeIfPresent(Int.self, forKey: .indentLevel) ?? 0
        )
    }
}
