import Darwin
import Foundation

@main
enum StickyOrderRegression {
    private static var checks = 0

    static func main() {
        var values = ["A", "B", "C", "D"]

        expect(StickyOrder.move("D", to: 0, in: &values), "last item moves to first")
        expect(values == ["D", "A", "B", "C"], "move to first produces expected order")
        expect(StickyOrder.move("D", to: 2, in: &values), "first item moves down")
        expect(values == ["A", "B", "D", "C"], "downward move uses final destination index")
        expect(!StickyOrder.move("B", to: 1, in: &values), "same-position move is ignored")
        expect(StickyOrder.move("A", to: 99, in: &values), "large destination is accepted")
        expect(values == ["B", "D", "C", "A"], "large destination clamps to the end")
        expect(StickyOrder.move("A", to: -10, in: &values), "negative destination is accepted")
        expect(values == ["A", "B", "D", "C"], "negative destination clamps to the beginning")
        expect(!StickyOrder.move("missing", to: 0, in: &values), "missing item is ignored")

        print("Sticky order regression checks passed (\(checks)).")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(label)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
