import CoreGraphics

/// Equal horizontal distribution keeps every overlapping Home card available
/// as a drag-and-drop target, compressing only when the window requires it.
enum StickyFanLayout {
    static func positions(
        count: Int,
        availableWidth: CGFloat,
        cardWidth: CGFloat,
        maximumStep: CGFloat = 105
    ) -> [CGFloat] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [0] }
        let availableSpan = max(0, availableWidth - cardWidth)
        let step = min(maximumStep, availableSpan / CGFloat(count - 1))
        return (0..<count).map { CGFloat($0) * step }
    }
}
