import Foundation

/// Pure ordering logic shared by the manager and regression coverage.
/// `destinationIndex` is the element's final index after the move.
enum StickyOrder {
    @discardableResult
    static func move<Element: Equatable>(
        _ element: Element,
        to destinationIndex: Int,
        in elements: inout [Element]
    ) -> Bool {
        guard elements.count > 1,
              let sourceIndex = elements.firstIndex(of: element) else { return false }

        let boundedDestination = min(max(destinationIndex, 0), elements.count - 1)
        guard sourceIndex != boundedDestination else { return false }

        elements.remove(at: sourceIndex)
        elements.insert(element, at: boundedDestination)
        return true
    }
}
