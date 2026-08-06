import SwiftUI

/// The journal, Notes app style: a sidebar of past entries next to the
/// current day's writing surface, not a separate history window stacked on
/// top of another. Only "Today" is ever editable; past entries are
/// select-to-read only, matching how `JournalStore` has always worked.
struct JournalZenView: View {
    let journal: JournalStore
    /// Which day to show selected on open, e.g. jumping in from the Home
    /// insight card's "read more" on a specific day. Defaults to today,
    /// the normal write surface.
    var initialDay: Date?
    var onDone: () -> Void

    @FocusState private var bodyFocused: Bool
    @State private var selectedDay: Date

    init(journal: JournalStore, initialDay: Date? = nil, onDone: @escaping () -> Void) {
        self.journal = journal
        self.initialDay = initialDay
        self.onDone = onDone
        _selectedDay = State(initialValue: Calendar.current.startOfDay(for: initialDay ?? Date()))
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var isTodaySelected: Bool { Calendar.current.isDate(selectedDay, inSameDayAs: today) }

    private var pastEntries: [JournalEntry] {
        journal.entries
            .filter { !$0.text.isEmpty && !Calendar.current.isDateInToday($0.day) }
            .sorted { $0.day > $1.day }
    }

    private var selectedPastEntry: JournalEntry? {
        pastEntries.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 780, height: 520)
        .background(Color(hex: 0xFEFCF6))
        // The sidebar's own tinted background is a separate flat rectangle
        // layered on top of this one, so it doesn't automatically pick up
        // the sheet's rounded-corner mask the way a single flat background
        // would. Clipping the whole panel explicitly rounds all four
        // corners uniformly instead of leaving the top-left looking sharp.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { if isTodaySelected { bodyFocused = true } }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarRow(title: "Today", preview: journal.todaysText, isSelected: isTodaySelected) {
                    selectedDay = today
                    bodyFocused = true
                }
                if !pastEntries.isEmpty {
                    Text("PAST ENTRIES")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 6)
                    ForEach(pastEntries) { entry in
                        sidebarRow(
                            title: Self.dayFormatter.string(from: entry.day),
                            preview: entry.text,
                            isSelected: Calendar.current.isDate(entry.day, inSameDayAs: selectedDay)
                        ) {
                            selectedDay = Calendar.current.startOfDay(for: entry.day)
                            bodyFocused = false
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 220)
        .background(Color.black.opacity(0.02))
    }

    private func sidebarRow(title: String, preview: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x20211E))
                Text(preview.isEmpty ? "No entry yet" : preview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(isSelected ? Color.black.opacity(0.06) : .clear)
            // Without this, SwiftUI only hit-tests the visible glyphs, not
            // the transparent padding around them, so most of the row
            // silently ignored clicks unless you landed exactly on the
            // text itself. This makes the entire row tappable.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if isTodaySelected {
            todayEditor
        } else if let entry = selectedPastEntry {
            pastEntryReader(entry)
        }
    }

    private var todayEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Self.dayFormatter.string(from: today))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 22)

            ZStack(alignment: .topLeading) {
                if journal.todaysText.isEmpty {
                    Text(AppSettings.shared.journalPrompt)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                TextEditor(text: textBinding)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Color(hex: 0x20211E))
                    .tint(Color(hex: 0x20211E))
                    .contentMargins(.top, 0, for: .scrollContent)
                    // TextEditor carries its own internal inset that a plain
                    // Text sibling doesn't have; canceling it here keeps the
                    // placeholder and whatever you actually type flush with
                    // the date line above instead of sitting a few points
                    // right of it.
                    .padding(.leading, -5)
                    .focused($bodyFocused)
            }

            if let entry = journal.todaysEntry, !entry.text.isEmpty {
                Text(metaLine(for: entry))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .padding(.top, 14)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pastEntryReader(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Self.dayFormatter.string(from: entry.day))
                        .font(.system(size: 22, weight: .medium))
                    if let location = entry.locationLabel {
                        Text(location)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.text)
                        .font(.system(size: 14))
                        .lineSpacing(4.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(wordCountLabel(for: entry.text))
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.top, 14)
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textBinding: Binding<String> {
        Binding(get: { journal.todaysText }, set: { journal.updateTodaysText($0) })
    }

    private func metaLine(for entry: JournalEntry) -> String {
        let time = Self.timeFormatter.string(from: entry.updatedAt)
        let words = wordCountLabel(for: entry.text)
        if let location = entry.locationLabel { return "\(words) · Last updated \(time) · \(location)" }
        return "\(words) · Last updated \(time)"
    }

    private func wordCountLabel(for text: String) -> String {
        let count = text.split(whereSeparator: \.isWhitespace).count
        return "\(count) word\(count == 1 ? "" : "s")"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
