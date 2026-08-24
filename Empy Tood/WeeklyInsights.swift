import Foundation

/// A single completed task as shown in the Home insight card. Enough to
/// render a colored dot (from whichever sticky it lived on) and its exact
/// text without the card needing to touch `StickyModel` directly.
struct CompletedTaskDisplay: Identifiable {
    let id: UUID
    let text: String
    let color: StickyColor
    let completedAt: Date
}

/// A still-open (unchecked) item, for the zero-state's "still on your list".
struct OpenTaskDisplay: Identifiable {
    let id: UUID
    let text: String
}

/// A journal entry's text shown verbatim (never summarized) in the insight
/// card, truncated for display. The full entry is one tap away, via
/// `JournalZenView`'s sidebar.
struct JournalExcerpt: Identifiable {
    let id: UUID
    let day: Date
    let text: String
}

/// One day's worth of completions, for the weekly wrap's day-by-day list.
struct DayCompletions: Identifiable {
    var id: Date { day }
    let day: Date
    let tasks: [CompletedTaskDisplay]
}

/// Everything the Home screen's insight stat needs to render, computed fresh
/// on demand from `StickyManager` and `JournalStore`. Nothing
/// here is cached or stored, so it's always exactly as current as the data
/// it's built from.
struct WeeklyInsightsSnapshot {
    /// True only on the last day of the calendar week (locale-aware), the
    /// one day the stat and its detail switch from daily to weekly.
    let isWeeklyWrapDay: Bool
    let weekRangeLabel: String

    let todayCount: Int
    let weekCount: Int
    let yesterdayCount: Int
    /// Consecutive days with at least one completed task, counting today
    /// only if it already has one. A day with nothing logged yet doesn't
    /// break a streak that's still "in progress".
    let streak: Int

    let todaysCompleted: [CompletedTaskDisplay]
    let openToday: [OpenTaskDisplay]
    let weekByDay: [DayCompletions]

    let todaysJournal: JournalExcerpt?
    let weekJournal: [JournalExcerpt]
    let daysJournaledThisWeek: Int

    var statNumber: Int { isWeeklyWrapDay ? weekCount : todayCount }
    var statLabel: String { isWeeklyWrapDay ? "done this week" : "done today" }
}

@MainActor
enum WeeklyInsights {
    static func snapshot(manager: StickyManager, journal: JournalStore, now: Date = Date()) -> WeeklyInsightsSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekInterval = cal.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: today, duration: 86400 * 7)

        let allCompletions = manager.completedItemsDisplay()
        let todaysCompleted = allCompletions.filter { cal.isDateInToday($0.completedAt) }
        let weekCompletions = allCompletions.filter { weekInterval.contains($0.completedAt) }

        let weekByDay = Dictionary(grouping: weekCompletions) { cal.startOfDay(for: $0.completedAt) }
            .map { DayCompletions(day: $0.key, tasks: $0.value.sorted { $0.completedAt < $1.completedAt }) }
            .sorted { $0.day < $1.day }

        // Day → count, for streak + yesterday, spanning a little past this
        // week so a streak can be traced back across a week boundary.
        var countsByDay: [Date: Int] = [:]
        for item in allCompletions {
            let day = cal.startOfDay(for: item.completedAt)
            countsByDay[day, default: 0] += 1
        }

        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let yesterdayCount = countsByDay[yesterday, default: 0]

        var streak = 0
        var cursor = today
        if countsByDay[cursor, default: 0] == 0 {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while countsByDay[cursor, default: 0] > 0 {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        let weekJournalEntries = journal.entries
            .filter { !$0.text.isEmpty && weekInterval.contains($0.day) }
            .sorted { $0.day < $1.day }
        let weekJournal = weekJournalEntries.map { JournalExcerpt(id: $0.id, day: $0.day, text: $0.text) }
        let todaysJournal = weekJournalEntries.first { cal.isDateInToday($0.day) }
            .map { JournalExcerpt(id: $0.id, day: $0.day, text: $0.text) }

        let rangeFormatter = DateFormatter()
        rangeFormatter.dateFormat = "MMM d"
        let weekRangeLabel = "\(rangeFormatter.string(from: weekInterval.start)) – \(rangeFormatter.string(from: cal.date(byAdding: .day, value: -1, to: weekInterval.end) ?? weekInterval.end))"

        return WeeklyInsightsSnapshot(
            isWeeklyWrapDay: isLastDayOfWeek(now, calendar: cal),
            weekRangeLabel: weekRangeLabel,
            todayCount: todaysCompleted.count,
            weekCount: weekCompletions.count,
            yesterdayCount: yesterdayCount,
            streak: streak,
            todaysCompleted: todaysCompleted,
            openToday: manager.openItemsDisplay(limit: 4),
            weekByDay: weekByDay,
            todaysJournal: todaysJournal,
            weekJournal: weekJournal,
            daysJournaledThisWeek: weekJournalEntries.count
        )
    }

    private static func isLastDayOfWeek(_ date: Date, calendar: Calendar) -> Bool {
        let currentWeekday = calendar.component(.weekday, from: date)
        let lastWeekday = ((calendar.firstWeekday + 5) % 7) + 1
        return currentWeekday == lastWeekday
    }
}
