import CoreGraphics
import Darwin
import Foundation

@main
enum StickyArrangementRegression {
    private static var checks = 0

    static func main() {
        let screen = CGRect(x: -200, y: 50, width: 1_440, height: 900)
        let current: [CGRect] = (0..<7).map { index in
            let offset = CGFloat(index * 10)
            return CGRect(x: offset, y: 100, width: 300 + offset, height: 400 + offset)
        }

        expect(
            StickyArrangement.allCases.map(\.shortcutKeyEquivalent) == ["g", "h", "j", "k", "l"],
            "arrangement shortcuts use the sequential GHJKL cluster"
        )

        let grid = StickyArrangementLayout.frames(for: .grid, currentFrames: current, in: screen)
        expect(grid.count == current.count, "grid returns one frame per sticky")
        expect(Set(grid.map(\.size)).count == 1, "grid sizes are uniform")
        expect(grid.allSatisfy(screen.contains), "grid remains on the target display")
        expect(Set(grid.map(\.origin)).count == current.count, "grid positions are distinct")

        let horizontal = StickyArrangementLayout.frames(for: .horizontal, currentFrames: current, in: screen)
        expect(Set(horizontal.map(\.size)).count == 1, "horizontal sizes are uniform")
        expect(Set(horizontal.map(\.maxY)).count == 1, "horizontal cards align at the top")
        expect(horizontal.allSatisfy(screen.contains), "horizontal layout remains on the target display")
        expect(isNondecreasing(horizontal.map(\.minX)), "horizontal cards run left to right")

        let vertical = StickyArrangementLayout.frames(for: .vertical, currentFrames: current, in: screen)
        expect(Set(vertical.map(\.size)).count == 1, "vertical sizes are uniform")
        expect(Set(vertical.map(\.minX)).count == 1, "vertical cards share one column")
        expect(isNonincreasing(vertical.map(\.maxY)), "vertical cards tile downward")
        expect(vertical.allSatisfy(screen.contains), "vertical layout remains on the target display")

        let pile = StickyArrangementLayout.frames(for: .pile, currentFrames: current, in: screen)
        expect(Set(pile.map(\.size)).count == 1, "pile sizes are uniform")
        expect(pile.allSatisfy(screen.contains), "pile remains on the target display")
        for pair in zip(pile, pile.dropFirst()) {
            expect(approximatelyEqual(pair.1.minX - pair.0.minX, 12), "pile offsets right by 12 points")
            expect(approximatelyEqual(pair.0.minY - pair.1.minY, 12), "pile offsets down by 12 points")
        }

        var units: [CGFloat] = [0, 0, 1, 1, 0.25, 0.75, 0.5, 0.5, 0.8, 0.2, 0.1, 0.9, 0.6, 0.4]
        let scatter = StickyArrangementLayout.frames(
            for: .scatter,
            currentFrames: current,
            in: screen,
            randomUnit: { units.removeFirst() }
        )
        expect(Set(scatter.map(\.size)).count == 1, "scatter sizes are uniform")
        expect(scatter.allSatisfy(screen.contains), "scatter remains on the target display")
        expect(scatter[0].minX < scatter[1].minX, "scatter consumes independent random x positions")
        expect(scatter[0].minY < scatter[1].minY, "scatter consumes independent random y positions")

        print("Sticky arrangement regression checks passed (\(checks)).")
    }

    private static func isNondecreasing(_ values: [CGFloat]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }

    private static func isNonincreasing(_ values: [CGFloat]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 >= $1 }
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(label)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
