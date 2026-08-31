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
    /// Optional date and time assigned through the inline `@` command.
    var dueDate: Date?
    /// The formatted date is stored in `text`; these fields identify its
    /// atomic UTF-16 range while still letting the native editor lay it out.
    var dueDateText: String?
    var dueDateOffset: Int?

    init(
        id: UUID = UUID(),
        text: String = "",
        isDone: Bool = false,
        completedAt: Date? = nil,
        indentLevel: Int = 0,
        dueDate: Date? = nil,
        dueDateText: String? = nil,
        dueDateOffset: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.completedAt = completedAt
        self.indentLevel = Self.clampedIndentLevel(indentLevel)
        self.dueDate = dueDate
        self.dueDateText = dueDateText
        self.dueDateOffset = dueDateOffset
    }

    mutating func adjustIndent(by change: Int) {
        indentLevel = Self.clampedIndentLevel(indentLevel + change)
    }

    private static func clampedIndentLevel(_ level: Int) -> Int {
        min(max(level, 0), maximumIndentLevel)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isDone, completedAt, indentLevel, dueDate, dueDateText, dueDateOffset
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
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        dueDateText = try container.decodeIfPresent(String.self, forKey: .dueDateText)
        dueDateOffset = try container.decodeIfPresent(Int.self, forKey: .dueDateOffset)
    }

    var dueDateRange: NSRange? {
        guard dueDate != nil, let dueDateText, let dueDateOffset else { return nil }
        let range = NSRange(location: dueDateOffset, length: (dueDateText as NSString).length)
        let textLength = (text as NSString).length
        guard range.location >= 0, NSMaxRange(range) <= textLength,
              (text as NSString).substring(with: range) == dueDateText
        else { return nil }
        return range
    }
}
