import Darwin
import Foundation

@main
enum TodoItemIndentRegression {
    private static var checks = 0

    static func main() throws {
        var item = TodoItem(text: "Nested")
        for _ in 0..<5 { item.adjustIndent(by: 1) }
        expect(item.indentLevel == 3, "indent stops at level three")

        for _ in 0..<5 { item.adjustIndent(by: -1) }
        expect(item.indentLevel == 0, "outdent stops at level zero")

        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","text":"Legacy","isDone":false}
        """.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(TodoItem.self, from: legacy)
        expect(decodedLegacy.indentLevel == 0, "saved tasks without indentation remain top level")
        expect(decodedLegacy.dueDate == nil, "saved tasks without dates remain undated")

        let encoded = try JSONEncoder().encode(TodoItem(text: "Child", indentLevel: 2))
        let roundTrip = try JSONDecoder().decode(TodoItem.self, from: encoded)
        expect(roundTrip.indentLevel == 2, "indentation persists across encoding")

        let assignedDate = Date(timeIntervalSince1970: 1_788_136_200)
        let datedData = try JSONEncoder().encode(TodoItem(text: "Dated", dueDate: assignedDate))
        let datedRoundTrip = try JSONDecoder().decode(TodoItem.self, from: datedData)
        expect(datedRoundTrip.dueDate == assignedDate, "task dates persist across encoding")

        let token = "Today at 2:30 PM"
        let inline = TodoItem(
            text: "Call \(token) after lunch",
            dueDate: assignedDate,
            dueDateText: token,
            dueDateOffset: 5
        )
        let inlineRoundTrip = try JSONDecoder().decode(
            TodoItem.self,
            from: JSONEncoder().encode(inline)
        )
        expect(inlineRoundTrip.dueDateRange == NSRange(location: 5, length: (token as NSString).length),
               "inline date ranges persist across encoding")

        var restored = roundTrip
        restored.adjustIndent(by: -1)
        expect(restored.indentLevel == 1, "an indent level can be restored for undo")

        print("Todo item indentation regression checks passed (\(checks)).")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(label)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
