import CoreGraphics
import Darwin
import Foundation

@main
enum StickyFanLayoutRegression {
    private static var checks = 0

    static func main() {
        expect(StickyFanLayout.positions(count: 0, availableWidth: 600, cardWidth: 178).isEmpty, "empty fan")
        expect(StickyFanLayout.positions(count: 1, availableWidth: 600, cardWidth: 178) == [0], "single card")

        let comfortable = StickyFanLayout.positions(count: 4, availableWidth: 600, cardWidth: 178)
        expect(comfortable == [0, 105, 210, 315], "comfortable fan uses equal maximum steps")

        let compressed = StickyFanLayout.positions(count: 6, availableWidth: 500, cardWidth: 178)
        expect(compressed.count == 6, "compressed fan returns every position")
        expect(equalDeltas(compressed), "compressed fan gaps remain equal")
        expect(abs((compressed.last ?? 0) - 322) < 0.001, "compressed fan fits")

        print("Sticky fan layout regression checks passed (\(checks)).")
    }

    private static func equalDeltas(_ values: [CGFloat]) -> Bool {
        guard values.count > 2 else { return true }
        let expected = values[1] - values[0]
        return zip(values.dropFirst(), values).allSatisfy { abs(($0 - $1) - expected) < 0.001 }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(label)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
