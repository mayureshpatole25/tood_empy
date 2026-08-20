import CoreGraphics
import Foundation

/// The desktop-wide layouts available from the status menu.
enum StickyArrangement: String, CaseIterable, Hashable {
    case grid
    case horizontal
    case vertical
    case pile
    case scatter

    var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .horizontal: return "Line Up Horizontally"
        case .vertical: return "Line Up Vertically"
        case .pile: return "Pile"
        case .scatter: return "Scatter"
        }
    }

    /// Mnemonic letter used by the fixed global shortcut and shown beside
    /// the matching status-menu command. All five share ⌃⌥⌘ modifiers.
    var shortcutKeyEquivalent: String {
        switch self {
        case .grid: return "g"
        case .horizontal: return "h"
        case .vertical: return "j"
        case .pile: return "k"
        case .scatter: return "l"
        }
    }
}

/// Pure frame calculation for arranging sticky windows on one display.
/// Keeping this independent from AppKit makes the dense/fallback layouts
/// deterministic and regression-testable without constructing NSWindows.
enum StickyArrangementLayout {
    static let screenMargin: CGFloat = 18
    static let gridGap: CGFloat = 14
    static let pileOffset: CGFloat = 12
    static let verticalTitleStep: CGFloat = 112

    static func frames(
        for arrangement: StickyArrangement,
        currentFrames: [CGRect],
        in visibleFrame: CGRect,
        randomUnit: () -> CGFloat = { CGFloat.random(in: 0...1) }
    ) -> [CGRect] {
        guard !currentFrames.isEmpty, visibleFrame.width > 0, visibleFrame.height > 0 else {
            return []
        }

        let workArea = insetWorkArea(visibleFrame)
        switch arrangement {
        case .grid:
            return gridFrames(count: currentFrames.count, in: workArea)
        case .horizontal:
            return horizontalFrames(count: currentFrames.count, in: workArea)
        case .vertical:
            return verticalFrames(count: currentFrames.count, in: workArea)
        case .pile:
            return pileFrames(count: currentFrames.count, in: workArea)
        case .scatter:
            return scatterFrames(count: currentFrames.count, in: workArea, randomUnit: randomUnit)
        }
    }

    private static func insetWorkArea(_ visibleFrame: CGRect) -> CGRect {
        let horizontalMargin = min(screenMargin, max(visibleFrame.width - StickyWindowGeometry.minimumWidth, 0) / 2)
        let verticalMargin = min(screenMargin, max(visibleFrame.height - StickyWindowGeometry.minimumHeight, 0) / 2)
        return visibleFrame.insetBy(dx: horizontalMargin, dy: verticalMargin)
    }

    private static func gridFrames(count: Int, in workArea: CGRect) -> [CGRect] {
        let columns = bestGridColumnCount(count: count, in: workArea)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellWidth = (workArea.width - (CGFloat(columns - 1) * gridGap)) / CGFloat(columns)
        let cellHeight = (workArea.height - (CGFloat(rows - 1) * gridGap)) / CGFloat(rows)
        let size = StickyWindowGeometry.constrainedSize(
            CGSize(
                width: min(StickyWindowGeometry.defaultWidth, cellWidth),
                height: min(StickyWindowGeometry.defaultHeight, cellHeight)
            ),
            maximumSize: workArea.size
        )

        let xStep = distributedStep(itemLength: size.width, count: columns, availableLength: workArea.width)
        let yStep = distributedStep(itemLength: size.height, count: rows, availableLength: workArea.height)
        let occupiedWidth = size.width + (CGFloat(columns - 1) * xStep)
        let occupiedHeight = size.height + (CGFloat(rows - 1) * yStep)
        let startX = workArea.midX - (occupiedWidth / 2)
        let topY = workArea.midY + (occupiedHeight / 2) - size.height

        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            return CGRect(
                x: startX + (CGFloat(column) * xStep),
                y: topY - (CGFloat(row) * yStep),
                width: size.width,
                height: size.height
            )
        }
    }

    private static func bestGridColumnCount(count: Int, in workArea: CGRect) -> Int {
        let defaultAspect = StickyWindowGeometry.defaultWidth / StickyWindowGeometry.defaultHeight
        let screenAspect = workArea.width / workArea.height
        let idealColumns = sqrt(CGFloat(count) * screenAspect / defaultAspect)
        var best: (columns: Int, area: CGFloat, distance: CGFloat)?

        for columns in 1...count {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let width = (workArea.width - (CGFloat(columns - 1) * gridGap)) / CGFloat(columns)
            let height = (workArea.height - (CGFloat(rows - 1) * gridGap)) / CGFloat(rows)
            guard width >= StickyWindowGeometry.minimumWidth,
                  height >= StickyWindowGeometry.minimumHeight else { continue }

            let area = min(width, StickyWindowGeometry.defaultWidth)
                * min(height, StickyWindowGeometry.defaultHeight)
            let candidate = (columns, area, abs(CGFloat(columns) - idealColumns))
            if best == nil
                || candidate.1 > best!.area
                || (candidate.1 == best!.area && candidate.2 < best!.distance) {
                best = candidate
            }
        }

        if let best { return best.columns }
        return min(max(Int(idealColumns.rounded()), 1), count)
    }

    private static func horizontalFrames(count: Int, in workArea: CGRect) -> [CGRect] {
        let fittedWidth = (workArea.width - (CGFloat(count - 1) * gridGap)) / CGFloat(count)
        let size = StickyWindowGeometry.constrainedSize(
            CGSize(
                width: min(StickyWindowGeometry.defaultWidth, fittedWidth),
                height: min(StickyWindowGeometry.defaultHeight, workArea.height)
            ),
            maximumSize: workArea.size
        )
        let step = distributedStep(itemLength: size.width, count: count, availableLength: workArea.width)
        let occupiedWidth = size.width + (CGFloat(count - 1) * step)
        let startX = workArea.midX - (occupiedWidth / 2)
        let y = workArea.maxY - size.height

        return (0..<count).map { index in
            CGRect(
                x: startX + (CGFloat(index) * step),
                y: y,
                width: size.width,
                height: size.height
            )
        }
    }

    private static func verticalFrames(count: Int, in workArea: CGRect) -> [CGRect] {
        let size = StickyWindowGeometry.constrainedSize(
            CGSize(
                width: min(StickyWindowGeometry.defaultWidth, workArea.width),
                height: min(StickyWindowGeometry.defaultHeight, workArea.height)
            ),
            maximumSize: workArea.size
        )
        let maximumStep = count > 1 ? max((workArea.height - size.height) / CGFloat(count - 1), 0) : 0
        let step = min(verticalTitleStep, maximumStep)
        let occupiedHeight = size.height + (CGFloat(count - 1) * step)
        let x = workArea.midX - (size.width / 2)
        let topY = workArea.midY + (occupiedHeight / 2) - size.height

        return (0..<count).map { index in
            CGRect(
                x: x,
                y: topY - (CGFloat(index) * step),
                width: size.width,
                height: size.height
            )
        }
    }

    private static func pileFrames(count: Int, in workArea: CGRect) -> [CGRect] {
        let stackTravel = CGFloat(count - 1) * pileOffset
        let maximumCardSize = CGSize(
            width: max(workArea.width - stackTravel, StickyWindowGeometry.minimumWidth),
            height: max(workArea.height - stackTravel, StickyWindowGeometry.minimumHeight)
        )
        let size = StickyWindowGeometry.constrainedSize(
            CGSize(
                width: min(StickyWindowGeometry.defaultWidth, maximumCardSize.width),
                height: min(StickyWindowGeometry.defaultHeight, maximumCardSize.height)
            ),
            maximumSize: workArea.size
        )
        let occupiedWidth = min(size.width + stackTravel, workArea.width)
        let occupiedHeight = min(size.height + stackTravel, workArea.height)
        let startX = workArea.midX - (occupiedWidth / 2)
        let topY = workArea.midY + (occupiedHeight / 2) - size.height
        let xStep = min(pileOffset, count > 1 ? max((workArea.width - size.width) / CGFloat(count - 1), 0) : 0)
        let yStep = min(pileOffset, count > 1 ? max((workArea.height - size.height) / CGFloat(count - 1), 0) : 0)

        return (0..<count).map { index in
            CGRect(
                x: startX + (CGFloat(index) * xStep),
                y: topY - (CGFloat(index) * yStep),
                width: size.width,
                height: size.height
            )
        }
    }

    private static func scatterFrames(
        count: Int,
        in workArea: CGRect,
        randomUnit: () -> CGFloat
    ) -> [CGRect] {
        let size = StickyWindowGeometry.constrainedSize(
            StickyWindowGeometry.defaultSize,
            maximumSize: workArea.size
        )
        return (0..<count).map { _ in
            let xTravel = max(workArea.width - size.width, 0)
            let yTravel = max(workArea.height - size.height, 0)
            let xUnit = min(max(randomUnit(), 0), 1)
            let yUnit = min(max(randomUnit(), 0), 1)
            return CGRect(
                x: workArea.minX + (xTravel * xUnit),
                y: workArea.minY + (yTravel * yUnit),
                width: size.width,
                height: size.height
            )
        }
    }

    private static func distributedStep(
        itemLength: CGFloat,
        count: Int,
        availableLength: CGFloat
    ) -> CGFloat {
        guard count > 1 else { return 0 }
        return min(itemLength + gridGap, max((availableLength - itemLength) / CGFloat(count - 1), 0))
    }
}
