import SwiftUI

struct TaskDateCommand: Equatable {
    let range: Range<String.Index>
    let query: String

    static func active(in text: String, caretUTF16Offset: Int? = nil) -> TaskDateCommand? {
        let nsText = text as NSString
        let caret = min(max(caretUTF16Offset ?? nsText.length, 0), nsText.length)
        guard let caretIndex = String.Index(utf16Offset: caret, in: text) as String.Index? else { return nil }
        let beforeCaret = text[..<caretIndex]
        guard let at = beforeCaret.lastIndex(of: "@") else { return nil }
        if at > text.startIndex {
            let preceding = text[text.index(before: at)]
            guard preceding.isWhitespace else { return nil }
        }

        let token = text[at..<caretIndex]
        guard !token.contains(where: { $0.isNewline }) else { return nil }
        return TaskDateCommand(
            range: at..<caretIndex,
            query: String(token.dropFirst()).lowercased()
        )
    }

    func removingFrom(_ text: String) -> (text: String, caretUTF16Offset: Int) {
        var updated = text
        let caret = updated[..<range.lowerBound].utf16.count
        updated.removeSubrange(range)
        if updated.last?.isWhitespace == true {
            updated.removeLast()
            return (updated, max(caret - 1, 0))
        }
        return (updated, caret)
    }
}

enum TaskDateExpression {
    static func date(
        from query: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let normalized = query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let pattern = #"^(today|tomorrow|tonight|next week)(?: at)? (\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#
        guard let match = normalized.firstMatch(of: try! Regex(pattern)),
              let hour = Int(String(match.output[2].substring!)),
              (1...12).contains(hour)
        else { return nil }

        let minuteText = match.output[3].substring.map(String.init)
        let minute = minuteText.flatMap(Int.init) ?? 0
        guard (0...59).contains(minute) else { return nil }
        let meridiem = String(match.output[4].substring!)
        let hour24 = (hour % 12) + (meridiem == "pm" ? 12 : 0)
        let dayPhrase = String(match.output[1].substring!)
        let today = calendar.startOfDay(for: now)
        let day: Date
        switch dayPhrase {
        case "tomorrow":
            day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case "next week":
            day = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        default:
            day = today
        }
        return calendar.date(bySettingHour: hour24, minute: minute, second: 0, of: day)
    }

    static func timeComponents(from text: String) -> (hour: Int, minute: Int)? {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#
        guard let match = normalized.firstMatch(of: try! Regex(pattern)),
              let hour = Int(String(match.output[1].substring!)),
              (1...12).contains(hour)
        else { return nil }
        let minute = match.output[2].substring.flatMap { Int(String($0)) } ?? 0
        guard (0...59).contains(minute) else { return nil }
        let meridiem = String(match.output[3].substring!)
        return ((hour % 12) + (meridiem == "pm" ? 12 : 0), minute)
    }
}

extension Date {
    func roundedToNearestFiveMinutes(calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: self)
        let roundedMinute = Int((Double(minute) / 5).rounded()) * 5
        let startOfHour = calendar.dateInterval(of: .hour, for: self)?.start ?? self
        return calendar.date(byAdding: .minute, value: roundedMinute, to: startOfHour) ?? self
    }
}

struct TaskDateSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let date: Date

    static func matching(_ query: String, now: Date = Date(), calendar: Calendar = .current) -> [Self] {
        let candidates = all(now: now, calendar: calendar)
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return candidates }
        return candidates.filter {
            $0.id.hasPrefix(normalized) ||
            $0.title.lowercased().hasPrefix(normalized) ||
            normalized.hasPrefix($0.id + " ") ||
            normalized.hasPrefix($0.title.lowercased() + " ")
        }
    }

    private static func all(now: Date, calendar: Calendar) -> [Self] {
        let roundedNow = now.roundedToNearestFiveMinutes(calendar: calendar)
        let time = calendar.dateComponents([.hour, .minute], from: roundedNow)
        func applyingTime(to day: Date) -> Date {
            calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
        }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today) ?? today
        return [
            Self(id: "today", title: "Today", detail: dayDetail(today), date: applyingTime(to: today)),
            Self(id: "tonight", title: "Tonight", detail: "6:00 PM", date: evening),
            Self(id: "tomorrow", title: "Tomorrow", detail: dayDetail(tomorrow), date: applyingTime(to: tomorrow)),
            Self(id: "nextweek", title: "Next week", detail: dayDetail(nextWeek), date: applyingTime(to: nextWeek))
        ]
    }

    private static func dayDetail(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}

struct TaskDateDraft: Equatable {
    let itemID: UUID
    var query: String
    var selectedDate: Date
    var displayedMonth: Date
    var commandRange: NSRange?

    init(itemID: UUID, query: String, selectedDate: Date, commandRange: NSRange? = nil) {
        self.itemID = itemID
        self.query = query
        self.selectedDate = selectedDate
        self.displayedMonth = Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        self.commandRange = commandRange
    }
}

enum TaskDatePresentation {
    static func string(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            day = formatter.string(from: date)
        }
        return "\(day) at \(timeString(from: date))"
    }

    static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

private enum TaskDatePickerStyle {
    static let surface = Color(red: 0.975, green: 0.975, blue: 0.98)
    static let raised = Color.white
    static let border = Color.black.opacity(0.11)
    static let primary = Color.black.opacity(0.88)
    static let secondary = Color.black.opacity(0.48)
    static let accent = Color(red: 0.12, green: 0.49, blue: 0.91)
    static let highlight = accent.opacity(0.10)
}

struct TaskDateAssignmentPopover: View {
    @Binding var draft: TaskDateDraft
    let highlightedSuggestion: Int
    let onHighlight: (Int) -> Void
    let onChooseSuggestion: (TaskDateSuggestion) -> Void
    let onCommit: (Date) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    let onTimeEditingChange: (Bool) -> Void

    @State private var timeText = ""
    @State private var timeEditing = false
    @FocusState private var timeFocused: Bool

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private var suggestions: [TaskDateSuggestion] {
        TaskDateSuggestion.matching(draft.query)
    }

    var body: some View {
        VStack(spacing: 0) {
            dateAndTimeHeader

            if !suggestions.isEmpty {
                suggestionsList
                Divider().overlay(TaskDatePickerStyle.border)
            }

            calendarHeader
            weekdayHeader
            calendarGrid

            Divider().overlay(TaskDatePickerStyle.border)
                .padding(.top, 8)

            footer
        }
        .padding(14)
        .frame(width: 360)
        .background(TaskDatePickerStyle.surface)
        .preferredColorScheme(.light)
        .onAppear {
            timeText = TaskDatePresentation.timeString(from: draft.selectedDate)
            timeEditing = false
            timeFocused = false
            onTimeEditingChange(false)
        }
        .onChange(of: draft.selectedDate) { _, date in
            guard !timeFocused else { return }
            timeText = TaskDatePresentation.timeString(from: date)
        }
        .onChange(of: timeEditing) { _, editing in
            onTimeEditingChange(editing)
        }
        .onDisappear {
            onTimeEditingChange(false)
        }
    }

    private var dateAndTimeHeader: some View {
        HStack(spacing: 0) {
            Text(fullDate(draft.selectedDate))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(TaskDatePickerStyle.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(TaskDatePickerStyle.border)
                .frame(width: 1, height: 24)
                .padding(.horizontal, 12)

            Group {
                if timeEditing {
                    TextField("2:00 PM", text: $timeText)
                        .textFieldStyle(.plain)
                        .focused($timeFocused)
                        .onSubmit {
                            applyTypedTime()
                            timeEditing = false
                            timeFocused = false
                        }
                        .onChange(of: timeFocused) { wasFocused, isFocused in
                            if wasFocused && !isFocused {
                                applyTypedTime()
                                timeEditing = false
                            }
                        }
                } else {
                    Button {
                        timeEditing = true
                        DispatchQueue.main.async { timeFocused = true }
                    } label: {
                        Text(TaskDatePresentation.timeString(from: draft.selectedDate))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(TaskDatePickerStyle.primary)
            .frame(width: 86, alignment: .leading)

            VStack(spacing: 0) {
                timeStepButton(symbol: "chevron.up", minutes: 5)
                timeStepButton(symbol: "chevron.down", minutes: -5)
            }
            .frame(width: 22)
            .help("Adjust time by 5 minutes")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(TaskDatePickerStyle.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TaskDatePickerStyle.border, lineWidth: 1)
        }
        .padding(.bottom, 10)
    }

    private var suggestionsList: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onChooseSuggestion(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Text("@\(suggestion.id)")
                            .foregroundStyle(TaskDatePickerStyle.primary)
                        Spacer(minLength: 8)
                        Text(suggestion.detail)
                            .foregroundStyle(TaskDatePickerStyle.secondary)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(index == highlightedSuggestion ? TaskDatePickerStyle.highlight : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { onHighlight(index) }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var calendarHeader: some View {
        HStack {
            Text(monthTitle(draft.displayedMonth))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TaskDatePickerStyle.primary)
            Spacer()
            Button("Now") {
                let now = Date().roundedToNearestFiveMinutes(calendar: calendar)
                draft.selectedDate = now
                draft.displayedMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
                timeText = TaskDatePresentation.timeString(from: now)
            }
            .foregroundStyle(TaskDatePickerStyle.secondary)
            .buttonStyle(.plain)
            monthButton(symbol: "chevron.left", offset: -1)
            monthButton(symbol: "chevron.right", offset: 1)
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TaskDatePickerStyle.secondary)
                    .frame(height: 28)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(calendarDays, id: \.self) { date in
                let selected = calendar.isDate(date, inSameDayAs: draft.selectedDate)
                let inMonth = calendar.isDate(date, equalTo: draft.displayedMonth, toGranularity: .month)
                Button {
                    selectDay(date)
                } label: {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 14, weight: selected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(
                            selected
                                ? Color.white
                                : (inMonth ? TaskDatePickerStyle.primary : TaskDatePickerStyle.secondary.opacity(0.7))
                        )
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(selected ? TaskDatePickerStyle.accent : .clear)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Clear", action: onClear)
                .foregroundStyle(TaskDatePickerStyle.secondary)
            Spacer()
            Button("Cancel", action: onCancel)
                .foregroundStyle(TaskDatePickerStyle.secondary)
            Button("Set") {
                let date = dateApplyingTypedTime() ?? draft.selectedDate
                draft.selectedDate = date
                timeText = TaskDatePresentation.timeString(from: date)
                onCommit(date)
            }
            .fontWeight(.semibold)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(TaskDatePickerStyle.accent)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private var calendarDays: [Date] {
        guard let month = calendar.dateInterval(of: .month, for: draft.displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: month.start)
        else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek.start) }
    }

    private func monthButton(symbol: String, offset: Int) -> some View {
        Button {
            draft.displayedMonth = calendar.date(byAdding: .month, value: offset, to: draft.displayedMonth)
                ?? draft.displayedMonth
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(TaskDatePickerStyle.secondary)
    }

    private func selectDay(_ date: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: draft.selectedDate)
        draft.selectedDate = calendar.date(
            bySettingHour: time.hour ?? 9,
            minute: time.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
        if !calendar.isDate(date, equalTo: draft.displayedMonth, toGranularity: .month) {
            draft.displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    private func timeStepButton(symbol: String, minutes: Int) -> some View {
        Button {
            applyTypedTime()
            let updated = calendar.date(
                byAdding: .minute,
                value: minutes,
                to: draft.selectedDate
            ) ?? draft.selectedDate
            draft.selectedDate = updated
            timeText = TaskDatePresentation.timeString(from: updated)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TaskDatePickerStyle.secondary)
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applyTypedTime() {
        guard let date = dateApplyingTypedTime() else {
            timeText = TaskDatePresentation.timeString(from: draft.selectedDate)
            return
        }
        draft.selectedDate = date
        timeText = TaskDatePresentation.timeString(from: date)
    }

    private func dateApplyingTypedTime() -> Date? {
        guard let time = TaskDateExpression.timeComponents(from: timeText) else { return nil }
        return calendar.date(
            bySettingHour: time.hour,
            minute: time.minute,
            second: 0,
            of: draft.selectedDate
        )
    }

    private func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}
