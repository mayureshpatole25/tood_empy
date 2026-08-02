import Foundation
import Observation

/// Fetches today's events from the signed-in Google account's primary
/// calendar. Read-only (`calendar.readonly` scope) — this app never writes
/// to Google Calendar.
@MainActor
@Observable
final class GoogleCalendarService {
    static let shared = GoogleCalendarService()

    private(set) var todaysEvents: [CalendarEvent] = []
    private(set) var isLoading = false
    private(set) var lastError: Error?

    private let auth = GoogleAuthService.shared

    func refreshToday() async {
        guard auth.isConnected else {
            todaysEvents = []
            lastError = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await auth.validAccessToken()
            todaysEvents = try await Self.fetchEvents(accessToken: token, day: Date())
            lastError = nil
        } catch {
            lastError = error
        }
    }

    private static func fetchEvents(accessToken: String, day: Date) async throws -> [CalendarEvent] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
        let iso = ISO8601DateFormatter()

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: startOfDay)),
            URLQueryItem(name: "timeMax", value: iso.string(from: endOfDay)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let list = try JSONDecoder().decode(EventsResponse.self, from: data)
        return list.items.compactMap { item in
            let title = item.summary ?? "(No title)"

            let link = item.htmlLink.flatMap(URL.init(string:))

            if let dateOnly = item.start.date, let endDateOnly = item.end.date,
               let start = Self.dateOnlyFormatter.date(from: dateOnly),
               let end = Self.dateOnlyFormatter.date(from: endDateOnly) {
                return CalendarEvent(id: item.id, title: title, start: start, end: end, isAllDay: true, htmlLink: link)
            }

            guard let startString = item.start.dateTime, let endString = item.end.dateTime,
                  let start = iso.date(from: startString) ?? Self.isoWithFraction.date(from: startString),
                  let end = iso.date(from: endString) ?? Self.isoWithFraction.date(from: endString)
            else { return nil }
            return CalendarEvent(id: item.id, title: title, start: start, end: end, isAllDay: false, htmlLink: link)
        }
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

private struct EventsResponse: Decodable {
    let items: [EventItem]
}

private struct EventItem: Decodable {
    let id: String
    let summary: String?
    let start: EventDateTime
    let end: EventDateTime
    let htmlLink: String?
}

private struct EventDateTime: Decodable {
    let date: String?
    let dateTime: String?
}
