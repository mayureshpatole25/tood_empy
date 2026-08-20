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
        expect(minimum == CGSize(width: 280, height: 400), "minimum live size")

        let valid = StickyWindowGeometry.constrainedSize(CGSize(width: 640, height: 550))
        expect(valid == CGSize(width: 640, height: 550), "valid live size survives")

        let narrow = StickyWindowGeometry.constrainedSize(CGSize(width: 2, height: 550))
        expect(narrow == CGSize(width: 280, height: 550), "width stops independently at minimum")

        let short = StickyWindowGeometry.constrainedSize(CGSize(width: 640, height: 3))
        expect(short == CGSize(width: 640, height: 400), "height stops independently at minimum")

        let widthCapped = StickyWindowGeometry.constrainedSize(
            CGSize(width: 2_000, height: 550),
            maximumSize: CGSize(width: 800, height: 900)
        )
        expect(widthCapped == CGSize(width: 800, height: 550), "visible-screen width cap")

        let heightCapped = StickyWindowGeometry.constrainedSize(
            CGSize(width: 640, height: 2_000),
            maximumSize: CGSize(width: 900, height: 800)
        )
        expect(heightCapped == CGSize(width: 640, height: 800), "visible-screen height cap")

        let bothCapped = StickyWindowGeometry.constrainedSize(
            CGSize(width: 2_000, height: 2_000),
            maximumSize: CGSize(width: 800, height: 700)
        )
        expect(bothCapped == CGSize(width: 800, height: 700), "both axes cap independently")

        let tiny = CGRect(x: 100, y: 500, width: 8, height: 7)
        let repairedPersisted = StickyWindowGeometry.persistedFrame(tiny)
        expect(repairedPersisted.size == CGSize(width: 378, height: 490), "tiny persisted size heals")
        expect(approximatelyEqual(repairedPersisted.maxY, tiny.maxY), "persisted repair keeps top edge")

        let corruptWidth = CGRect(x: 30, y: 40, width: 7, height: 620)
        let repairedWidth = StickyWindowGeometry.persistedFrame(corruptWidth)
        expect(repairedWidth.size == CGSize(width: 378, height: 620), "corrupt persisted width heals independently")
        expect(repairedWidth.origin.x == corruptWidth.origin.x, "width repair keeps left edge")

        let corruptHeight = CGRect(x: 30, y: 40, width: 640, height: 7)
        let repairedHeight = StickyWindowGeometry.persistedFrame(corruptHeight)
        expect(repairedHeight.size == CGSize(width: 640, height: 490), "corrupt persisted height heals independently")
        expect(approximatelyEqual(repairedHeight.maxY, corruptHeight.maxY), "height repair keeps top edge")

        let chosenSize = CGRect(x: 30, y: 40, width: 640, height: 620)
        let preserved = StickyWindowGeometry.persistedFrame(chosenSize)
        expect(preserved == chosenSize, "valid chosen size survives")

        let absurd = CGRect(x: .greatestFiniteMagnitude, y: -.greatestFiniteMagnitude,
                            width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let safe = StickyWindowGeometry.persistedFrame(absurd)
        expect(safe == CGRect(x: 0, y: 0, width: 378, height: 490), "absurd frame is safe before NSWindow init")

        let runtimeTiny = StickyWindowGeometry.runtimeFrame(
            tiny,
            maximumSize: CGSize(width: 1_200, height: 900)
        )
        expect(runtimeTiny.size == CGSize(width: 280, height: 400), "programmatic tiny frame stops at minimum")

        let runtimeWidthOnly = StickyWindowGeometry.runtimeFrame(
            CGRect(x: 100, y: 500, width: 8, height: 620),
            maximumSize: CGSize(width: 1_200, height: 900)
        )
        expect(runtimeWidthOnly.size == CGSize(width: 280, height: 620), "runtime width heals independently")

        let runtimeHeightOnly = StickyWindowGeometry.runtimeFrame(
            CGRect(x: 100, y: 500, width: 640, height: 7),
            maximumSize: CGSize(width: 1_200, height: 900)
        )
        expect(runtimeHeightOnly.size == CGSize(width: 640, height: 400), "runtime height heals independently")

        let negativeDisplay = CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080)
        let offscreen = CGRect(x: -9_000, y: 4_000, width: 2_500, height: 1_500)
        let onScreen = StickyWindowGeometry.runtimeFrame(offscreen, visibleFrame: negativeDisplay)
        expect(negativeDisplay.contains(onScreen), "offscreen frame heals onto a negative-coordinate display")
        expect(onScreen.width == negativeDisplay.width, "oversized width fits visible display")
        expect(onScreen.height == negativeDisplay.height, "oversized height fits visible display")

        let secondPass = StickyWindowGeometry.runtimeFrame(onScreen, visibleFrame: negativeDisplay)
        expect(secondPass == onScreen, "normalization is idempotent")

        let largeDisplay = CGRect(x: 0, y: 0, width: 4_097, height: 2_048)
        let largeDisplayFrame = StickyWindowGeometry.runtimeFrame(
            largeDisplay,
            visibleFrame: largeDisplay
        )
        expect(
            largeDisplayFrame == largeDisplay,
            "large display-valid size never collapses at an arbitrary area threshold"
        )

        let narrowDisplay = CGRect(x: 100, y: 50, width: 240, height: 800)
        let centeredOnNarrowDisplay = StickyWindowGeometry.runtimeFrame(
            CGRect(x: -300, y: 100, width: 270, height: 500),
            visibleFrame: narrowDisplay
        )
        expect(centeredOnNarrowDisplay.width == 280, "minimum width survives an exceptionally narrow display")
        expect(
            approximatelyEqual(centeredOnNarrowDisplay.midX, narrowDisplay.midX),
            "minimum-width frame centers on an exceptionally narrow display"
        )

        for width: CGFloat in [280, 640] {
            let bounds = CGRect(x: 0, y: 0, width: width, height: 490)
            for point in [
                CGPoint(x: 1, y: 1), CGPoint(x: width - 1, y: 1),
                CGPoint(x: 1, y: 489), CGPoint(x: width - 1, y: 489),
                CGPoint(x: width / 2, y: 4), CGPoint(x: width / 2, y: 486),
                CGPoint(x: 4, y: 245), CGPoint(x: width - 4, y: 245),
            ] {
                expect(
                    StickyWindowGeometry.isInNativeResizePerimeter(point, bounds: bounds),
                    "native resize perimeter at width \(width), point \(point)"
                )
            }
            expect(
                !StickyWindowGeometry.isInNativeResizePerimeter(
                    CGPoint(x: width / 2, y: 24),
                    bounds: bounds
                ),
                "header interior remains draggable at width \(width)"
            )
            expect(
                StickyWindowGeometry.isInNativeResizePerimeter(
                    CGPoint(x: width / 2, y: 12),
                    bounds: bounds
                ),
                "12-point inner edge remains reserved for native resizing at width \(width)"
            )
            expect(
                !StickyWindowGeometry.isInNativeResizePerimeter(
                    CGPoint(x: width / 2, y: 13),
                    bounds: bounds
                ),
                "content beyond the 12-point resize edge is not reserved at width \(width)"
            )
        }

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
