import Darwin
import Foundation

@main
enum StickySelectionShortcutRegression {
    private static var checks = 0

    static func main() {
        let expectedKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        for (index, expectedKey) in expectedKeys.enumerated() {
            expect(
                StickySelectionShortcut.keyEquivalent(forStickyIndex: index) == expectedKey,
                "sticky index \(index) maps to Control-\(expectedKey)"
            )
            expect(
                StickySelectionShortcut.stickyIndex(forKeyEquivalent: expectedKey) == index,
                "Control-\(expectedKey) maps back to sticky index \(index)"
            )
        }

        expect(
            StickySelectionShortcut.keyEquivalent(forStickyIndex: -1) == nil,
            "negative sticky index has no shortcut"
        )
        expect(
            StickySelectionShortcut.keyEquivalent(forStickyIndex: 10) == nil,
            "eleventh sticky has no shortcut"
        )
        expect(
            StickySelectionShortcut.stickyIndex(forKeyEquivalent: "x") == nil,
            "non-number key has no sticky index"
        )
        expect(
            StickySelectionShortcut.stickyIndex(forKeyEquivalent: "10") == nil,
            "multi-character number has no sticky index"
        )

        print("Sticky selection shortcut regression checks passed (\(checks)).")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(label)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
