import Foundation

/// One Google Calendar event, trimmed to what the Home agenda actually shows.
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// Google's own "open this exact event" link, straight from the API
    /// response — more reliable than constructing a calendar URL by hand.
    let htmlLink: URL?
}
