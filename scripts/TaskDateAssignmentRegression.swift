import Darwin
import Foundation

@main
enum TaskDateAssignmentRegression {
    private static var checks = 0

    static func main() {
        expect(TaskDateCommand.active(in: "Call mum @")?.query == "", "bare at-sign opens the picker")
        expect(TaskDateCommand.active(in: "Call mum @to")?.query == "to", "query follows typing")
        expect(TaskDateCommand.active(in: "email@example.com") == nil, "email addresses do not open the picker")
        expect(
            TaskDateCommand.active(in: "Call mum @today 2 pm")?.query == "today 2 pm",
            "the active command accepts a natural-language time"
        )
        let middle = "Call @today then email"
        let middleCaret = ("Call @today" as NSString).length
        let middleCommand = TaskDateCommand.active(in: middle, caretUTF16Offset: middleCaret)!
        expect(middleCommand.query == "today", "a command ends at the caret, not at the end of the task")
        expect(String(middle[middleCommand.range.upperBound...]) == " then email",
               "text after a middle-of-sentence command is preserved")

        let command = TaskDateCommand.active(in: "Call mum @today")!
        let removed = command.removingFrom("Call mum @today")
        expect(removed.text == "Call mum", "committing removes the command and its separator")
        expect(removed.caretUTF16Offset == 8, "caret returns to the end of task text")

        let today = TaskDateSuggestion.matching("tod")
        expect(today.map(\.id) == ["today"], "today appears while its command is typed")
        expect(
            TaskDateSuggestion.matching("today 2 p").map(\.id) == ["today"],
            "today remains selected while its time is typed"
        )
        expect(TaskDateSuggestion.matching("tom").map(\.id) == ["tomorrow"], "suggestions filter by prefix")

        let calendar = Calendar(identifier: .gregorian)
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 16))!
        let naturalDate = TaskDateExpression.date(from: "today 2 pm", now: fixedNow, calendar: calendar)
        expect(
            naturalDate.map { calendar.component(.hour, from: $0) } == 14,
            "today with a typed 2 pm resolves to 14:00"
        )
        expect(
            TaskDateExpression.date(from: "today at 2:30 pm", now: fixedNow, calendar: calendar)
                .map { calendar.dateComponents([.hour, .minute], from: $0) }
                == DateComponents(hour: 14, minute: 30),
            "today at 2:30 pm resolves with the typed minutes"
        )
        expect(
            TaskDateExpression.timeComponents(from: "2:35 pm")?.hour == 14,
            "the editable time field accepts 12-hour time"
        )

        let twoPast = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 16, minute: 2))!
        let threePast = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 16, minute: 3))!
        expect(calendar.component(.minute, from: twoPast.roundedToNearestFiveMinutes(calendar: calendar)) == 0,
               "two minutes rounds down to the closest five")
        expect(calendar.component(.minute, from: threePast.roundedToNearestFiveMinutes(calendar: calendar)) == 5,
               "three minutes rounds up to the closest five")
        expect(
            TaskDatePresentation.string(from: fixedNow, now: fixedNow, calendar: calendar) == "Today at 4:00 PM",
            "the inline date phrase uses 12-hour time"
        )

        let tokenText = "Today at 2:30 PM"
        let tokenItem = TodoItem(
            text: "Call \(tokenText) then email",
            dueDate: naturalDate,
            dueDateText: tokenText,
            dueDateOffset: ("Call " as NSString).length
        )
        expect(tokenItem.dueDateRange == NSRange(location: 5, length: (tokenText as NSString).length),
               "the inline date retains its exact atomic range")

        print("Task date assignment regression checks passed (\(checks)).")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(label)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
