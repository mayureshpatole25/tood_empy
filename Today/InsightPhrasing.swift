import Foundation

/// Turns a computed `WeeklyInsightsSnapshot` into the one-line summary shown
/// at the top of the insight card. The counts and task/journal content are
/// always exact regardless of this. This only phrases them, and does so
/// with a plain deterministic template. A natural seam for swapping in
/// on-device Apple Intelligence (`FoundationModels`, macOS 26+) later, with
/// this template staying as the fallback whenever that's unavailable.
enum InsightPhrasing {
    static func summary(for snapshot: WeeklyInsightsSnapshot) -> String {
        if snapshot.isWeeklyWrapDay {
            let n = snapshot.weekCount
            guard n > 0 else { return "A quiet week. Nothing completed yet." }
            return "You wrapped up \(n) task\(n == 1 ? "" : "s") this week."
        }
        let n = snapshot.todayCount
        if n == 0 {
            return "Nothing logged yet today. Here's where the week stands so far."
        }
        return "You've completed \(n) task\(n == 1 ? "" : "s") today."
    }
}
