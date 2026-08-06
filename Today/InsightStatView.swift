import SwiftUI

/// The Home screen's "N done today / this week" stat: quiet at rest, with
/// a small badge the first time each day it has something new, and a
/// click-to-expand card underneath with the real breakdown. Monday through
/// Saturday it's the light one-day version; on the week's last day it
/// becomes the fuller day-by-day wrap. Mirrors the interaction explored in
/// the Home-insights design artifact.
struct InsightStatView: View {
    let manager: StickyManager
    let journal: JournalStore
    var onOpenJournalDay: (Date) -> Void

    @State private var expanded = false
    @State private var hovering = false
    @State private var snapshot: WeeklyInsightsSnapshot?
    @AppStorage("today.insightLastOpenedDay") private var lastOpenedDayKey: String = ""

    private let ink = Color(hex: 0x3A3A33)
    private let mutedInk = Color(hex: 0xA39D8C)
    private let secondaryInk = Color(hex: 0x6F6A5D)

    var body: some View {
        trigger
            .onAppear { refresh() }
            // A popover, not inline flow: Home's window has a fixed size
            // (no auto-resize-to-content in the AppKit shell around it), so
            // an inline card that grows tall, the weekly wrap especially,
            // would push the stickies fan below the window's bottom edge,
            // clipped until manually resized. A popover renders in its own
            // floating layer and never affects the host window's size.
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                if let snapshot {
                    detailCard(snapshot)
                }
            }
    }

    // MARK: - Trigger

    private var trigger: some View {
        Button {
            refresh()
            expanded.toggle()
            if expanded { markOpenedToday() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(snapshot?.statNumber ?? 0)")
                    .font(.custom("HelveticaNeue-Medium", size: 22))
                    .foregroundStyle(ink)
                Text(snapshot?.statLabel ?? "done today")
                    .font(.system(size: 11.5))
                    .foregroundStyle(mutedInk)
                    .underline(color: mutedInk.opacity(0.5))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(hovering ? 0.05 : 0))
            )
            .overlay(alignment: .topTrailing) {
                if hasUnseenToday {
                    Circle()
                        .fill(Color(hex: 0x20211E))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color(hex: 0xFBF8F1), lineWidth: 2))
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .offset(x: -6)
        .onHover { hovering = $0 }
    }

    private var todayKey: String {
        Self.dayKeyFormatter.string(from: Date())
    }

    private var hasUnseenToday: Bool { lastOpenedDayKey != todayKey }

    private func markOpenedToday() { lastOpenedDayKey = todayKey }

    private func refresh() {
        snapshot = WeeklyInsights.snapshot(manager: manager, journal: journal)
    }

    // MARK: - Detail card

    @ViewBuilder
    private func detailCard(_ snapshot: WeeklyInsightsSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.isWeeklyWrapDay ? snapshot.weekRangeLabel : "Today")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(mutedInk)
                    .textCase(.uppercase)
                    .padding(.bottom, 8)

                Text(InsightPhrasing.summary(for: snapshot))
                    .font(.system(size: 14))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                if snapshot.isWeeklyWrapDay {
                    weeklySections(snapshot)
                } else if snapshot.todayCount == 0 {
                    zeroStateSections(snapshot)
                } else {
                    dailySections(snapshot)
                }
            }
            .padding(20)
        }
        .frame(width: 300)
        // Capped rather than growing unbounded: a long weekly wrap (many
        // days, several journal excerpts) scrolls inside the popover
        // instead of ever pushing off-screen.
        .frame(maxHeight: 480)
        // No extra background/shadow here. The popover chrome already
        // draws the rounded white panel and shadow around this content.
    }

    @ViewBuilder
    private func dailySections(_ snapshot: WeeklyInsightsSnapshot) -> some View {
        section("What you got done") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(snapshot.todaysCompleted) { taskRow($0) }
            }
        }
        section("From your journal") {
            journalSection(entry: snapshot.todaysJournal)
        }
    }

    @ViewBuilder
    private func zeroStateSections(_ snapshot: WeeklyInsightsSnapshot) -> some View {
        section("This week so far") {
            HStack(alignment: .top, spacing: 20) {
                statPair(snapshot.weekCount, "so far this week")
                statPair(snapshot.streak, "day streak")
                statPair(snapshot.yesterdayCount, "yesterday")
            }
        }
        if !snapshot.openToday.isEmpty {
            section("Still on your list") {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.openToday) { openTaskRow($0) }
                }
            }
        }
        section("From your journal") {
            journalSection(entry: snapshot.todaysJournal)
        }
    }

    @ViewBuilder
    private func weeklySections(_ snapshot: WeeklyInsightsSnapshot) -> some View {
        section("What you got done") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.weekByDay) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayLabel(group.day))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(secondaryInk)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(group.tasks) { taskRow($0) }
                        }
                    }
                }
            }
        }
        if !snapshot.weekJournal.isEmpty {
            section("From your journal") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.weekJournal) { journalRow($0) }
                }
            }
        }
        Text("\(snapshot.daysJournaledThisWeek) of 7 days journaled this week")
            .font(.system(size: 10.5))
            .foregroundStyle(mutedInk)
            .padding(.top, 14)
    }

    // MARK: - Rows

    private func taskRow(_ task: CompletedTaskDisplay) -> some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(task.color.paper)
                .frame(width: 7, height: 7)
                .padding(.top, 3)
            Text(task.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(hex: 0x555146))
                .strikethrough(true, color: Color(hex: 0x555146).opacity(0.35))
        }
    }

    private func openTaskRow(_ task: OpenTaskDisplay) -> some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(Color(hex: 0x555146).opacity(0.35), lineWidth: 1.3)
                .frame(width: 7, height: 7)
                .padding(.top, 3)
            Text(task.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(secondaryInk)
        }
    }

    @ViewBuilder
    private func journalSection(entry: JournalExcerpt?) -> some View {
        if let entry {
            journalRow(entry)
        } else {
            Text("No entry yet today. Your desk is open whenever you are.")
                .font(.system(size: 12))
                .foregroundStyle(mutedInk)
                .italic()
        }
    }

    private func journalRow(_ excerpt: JournalExcerpt) -> some View {
        Button {
            onOpenJournalDay(excerpt.day)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(dayLabel(excerpt.day))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(mutedInk)
                (
                    Text(truncated(excerpt.text))
                        .italic()
                        .font(.custom("Georgia", size: 13))
                        .foregroundStyle(Color(hex: 0x4A463C))
                    + Text("  read more →")
                        .font(.system(size: 10.5))
                        .foregroundStyle(mutedInk)
                )
                .lineLimit(3)
            }
        }
        .buttonStyle(.plain)
    }

    private func statPair(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.custom("HelveticaNeue-Medium", size: 17))
                .foregroundStyle(ink)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(mutedInk)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(mutedInk)
                .textCase(.uppercase)
            content()
        }
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(hex: 0xEEEBE3)).frame(height: 1)
        }
    }

    private func truncated(_ text: String, limit: Int = 130) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        return Self.dayLabelFormatter.string(from: day)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}
