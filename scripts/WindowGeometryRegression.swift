import Darwin
import CoreGraphics
import Foundation

@main
enum WindowGeometryRegression {
    private static var checks = 0

    static func main() {
        let defaultSize = StickyWindowGeometry.defaultSize
        expect(defaultSize == CGSize(width: 378, height: 490), "default size")

        let minimum = StickyWindowGeometry.constrainedSize(CGSize(width: 2, height: 3))
        expect(minimum == CGSize(width: 378, height: 400), "minimum live size")

        let valid = StickyWindowGeometry.constrainedSize(CGSize(width: 900, height: 550))
        expect(valid == CGSize(width: 378, height: 550), "fixed width and preserved height")

        let capped = StickyWindowGeometry.constrainedSize(
            CGSize(width: 378, height: 2_000),
            maximumHeight: 800
        )
        expect(capped == CGSize(width: 378, height: 800), "visible-screen height cap")

        let tiny = CGRect(x: 100, y: 500, width: 8, height: 7)
        let repairedPersisted = StickyWindowGeometry.persistedFrame(tiny)
        expect(repairedPersisted.size == CGSize(width: 378, height: 490), "tiny persisted size heals")
        expect(approximatelyEqual(repairedPersisted.maxY, tiny.maxY), "persisted repair keeps top edge")

        let chosenHeight = CGRect(x: 30, y: 40, width: 700, height: 620)
        let preserved = StickyWindowGeometry.persistedFrame(chosenHeight)
        expect(preserved.size == CGSize(width: 378, height: 620), "valid chosen height survives")

        let absurd = CGRect(x: .greatestFiniteMagnitude, y: -.greatestFiniteMagnitude,
                            width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let safe = StickyWindowGeometry.persistedFrame(absurd)
        expect(safe == CGRect(x: 0, y: 0, width: 378, height: 490), "absurd frame is safe before NSWindow init")

        let runtimeTiny = StickyWindowGeometry.runtimeFrame(tiny, maximumHeight: 900)
        expect(runtimeTiny.size == CGSize(width: 378, height: 400), "programmatic tiny frame stops at minimum")

        let negativeDisplay = CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080)
        let offscreen = CGRect(x: -9_000, y: 4_000, width: 378, height: 1_500)
        let onScreen = StickyWindowGeometry.runtimeFrame(offscreen, visibleFrame: negativeDisplay)
        expect(negativeDisplay.contains(onScreen), "offscreen frame heals onto a negative-coordinate display")
        expect(onScreen.height == negativeDisplay.height, "oversized height fits visible display")

        let secondPass = StickyWindowGeometry.runtimeFrame(onScreen, visibleFrame: negativeDisplay)
        expect(secondPass == onScreen, "normalization is idempotent")

        let bounds = CGRect(x: 0, y: 0, width: 378, height: 490)
        for point in [
            CGPoint(x: 0, y: 0), CGPoint(x: 377, y: 0),
            CGPoint(x: 0, y: 489), CGPoint(x: 377, y: 489),
            CGPoint(x: 189, y: 4), CGPoint(x: 189, y: 486),
            CGPoint(x: 4, y: 245), CGPoint(x: 374, y: 245),
        ] {
            expect(
                StickyWindowGeometry.isInNativeResizePerimeter(point, bounds: bounds),
                "native resize perimeter at \(point)"
            )
        }
        expect(
            !StickyWindowGeometry.isInNativeResizePerimeter(
                CGPoint(x: 189, y: 24),
                bounds: bounds
            ),
            "header interior remains draggable"
        )

        print("Window geometry regression checks passed (\(checks)).")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(label)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }
}
