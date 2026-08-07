import Foundation

struct GitHubContributionDay: Identifiable {
    var id: Date { date }
    let date: Date
    /// GitHub's own 0...4 bucketing of that day's activity.
    let level: Int
}

/// Reads a GitHub profile's public contribution calendar straight from the
/// same page github.com itself renders at github.com/users/{username}/contributions
/// — no API token, no OAuth, since it's the exact HTML anyone gets visiting
/// that page signed out. Screen-scraped, not an official API: if GitHub
/// changes that page's markup this quietly stops returning results rather
/// than breaking anything else in the app.
enum GitHubContributionsService {
    private static let dayPattern = #"data-date="(\d{4}-\d{2}-\d{2})"[^>]*data-level="([0-4])""#

    static func fetchRecentDays(username: String, count: Int = 7) async -> [GitHubContributionDay]? {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://github.com/users/\(trimmed)/contributions")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Tood macOS app)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: dayPattern)
        else { return nil }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var days: [GitHubContributionDay] = []
        for match in matches {
            guard let dateRange = Range(match.range(at: 1), in: html),
                  let levelRange = Range(match.range(at: 2), in: html),
                  let date = formatter.date(from: String(html[dateRange])),
                  let level = Int(html[levelRange])
            else { continue }
            days.append(GitHubContributionDay(date: date, level: level))
        }

        guard !days.isEmpty else { return nil }
        days.sort { $0.date < $1.date }
        return Array(days.suffix(count))
    }
}
