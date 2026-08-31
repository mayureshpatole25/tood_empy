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
    /// Nil is the backward-compatible legacy value: old date tokens always
    /// included a time. New date-only tokens persist `false` explicitly.
    var dueDateHasTime: Bool?

    init(
        id: UUID = UUID(),
        text: String = "",
        isDone: Bool = false,
        completedAt: Date? = nil,
        indentLevel: Int = 0,
        dueDate: Date? = nil,
        dueDateText: String? = nil,
        dueDateOffset: Int? = nil,
        dueDateHasTime: Bool? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.completedAt = completedAt
        self.indentLevel = Self.clampedIndentLevel(indentLevel)
        self.dueDate = dueDate
        self.dueDateText = dueDateText
        self.dueDateOffset = dueDateOffset
        self.dueDateHasTime = dueDateHasTime
    }

    mutating func adjustIndent(by change: Int) {
        indentLevel = Self.clampedIndentLevel(indentLevel + change)
    }

    private static func clampedIndentLevel(_ level: Int) -> Int {
        min(max(level, 0), maximumIndentLevel)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isDone, completedAt, indentLevel, dueDate, dueDateText, dueDateOffset, dueDateHasTime
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
        dueDateHasTime = try container.decodeIfPresent(Bool.self, forKey: .dueDateHasTime)
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

    var dateTokenHasTime: Bool {
        dueDateHasTime ?? dueDateText?.contains(" at ") == true
    }

    /// Date and time are separate atomic keyboard-selection units. The time
    /// range includes the joining space so no caret can become stranded in it.
    var dueDateDateRange: NSRange? {
        guard let whole = dueDateRange, let dueDateText else { return nil }
        guard dateTokenHasTime else { return whole }
        let separator = (dueDateText as NSString).range(of: " at ")
        guard separator.location != NSNotFound else { return whole }
        return NSRange(location: whole.location, length: separator.location)
    }

    var dueDateTimeRange: NSRange? {
        guard let whole = dueDateRange, let date = dueDateDateRange, dateTokenHasTime else { return nil }
        return NSRange(location: NSMaxRange(date), length: NSMaxRange(whole) - NSMaxRange(date))
    }
}
