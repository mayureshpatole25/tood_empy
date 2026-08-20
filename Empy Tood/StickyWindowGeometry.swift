import CoreGraphics
import Foundation

/// The single source of truth for floating-sticky geometry.
///
/// AppKit's `minSize`/`maxSize` only constrain interactive resizing. They do
/// not repair an invalid initial frame and `setFrame(_:display:)` deliberately
/// bypasses them, so every persisted and programmatic frame also comes through
/// this policy before it reaches `NSWindow`.
enum StickyWindowGeometry {
    static let fixedWidth: CGFloat = 378
    static let defaultHeight: CGFloat = 490
    static let minimumHeight: CGFloat = 400

    /// Large enough for any real display while preventing corrupt persisted
    /// geometry from reaching AppKit as a gigantic allocation.
    static let maximumSafeHeight: CGFloat = 16_384
    static let maximumSafeCoordinateMagnitude: CGFloat = 1_000_000

    /// Mouse-downs inside this perimeter belong to AppKit's native resize
    /// tracking, never to the custom draggable header.
    static let nativeResizeEdgeInset: CGFloat = 8

    static let defaultSize = CGSize(width: fixedWidth, height: defaultHeight)
    static let minimumSize = CGSize(width: fixedWidth, height: minimumHeight)

    /// Sanitizes data loaded from disk before an `NSWindow` is constructed.
    /// A paper-thin or otherwise corrupt legacy height reopens at the normal
    /// default height; an intentional, valid user-selected height survives.
    static func persistedFrame(_ frame: CGRect) -> CGRect {
        normalizedFrame(
            frame,
            maximumHeight: maximumSafeHeight,
            invalidHeightFallback: defaultHeight,
            visibleFrame: nil
        )
    }

    /// Constrains a live/programmatic size. Unlike persisted corruption, a
    /// resize below the lower bound stops exactly at the declared minimum.
    static func constrainedSize(
        _ proposedSize: CGSize,
        maximumHeight requestedMaximumHeight: CGFloat = maximumSafeHeight
    ) -> CGSize {
        let maximumHeight = safeMaximumHeight(requestedMaximumHeight)
        let proposedHeight = proposedSize.height.isFinite && proposedSize.height > 0
            ? proposedSize.height
            : defaultHeight
        return CGSize(
            width: fixedWidth,
            height: min(max(proposedHeight, minimumHeight), maximumHeight)
        )
    }

    /// Repairs runtime geometry while preserving its top edge. Pass a visible
    /// frame when the whole sticky must be brought back on-screen (launch,
    /// reopen, display changes, and the end of a live resize).
    static func runtimeFrame(_ frame: CGRect, visibleFrame: CGRect? = nil) -> CGRect {
        normalizedFrame(
            frame,
            maximumHeight: visibleFrame?.height ?? maximumSafeHeight,
            invalidHeightFallback: minimumHeight,
            visibleFrame: visibleFrame
        )
    }

    /// Repairs size without changing an otherwise valid position. Used while
    /// a native live resize is in progress, when AppKit owns the anchored edge.
    static func runtimeFrame(_ frame: CGRect, maximumHeight: CGFloat) -> CGRect {
        normalizedFrame(
            frame,
            maximumHeight: maximumHeight,
            invalidHeightFallback: minimumHeight,
            visibleFrame: nil
        )
    }

    static func effectiveMaximumHeight(_ proposed: CGFloat) -> CGFloat {
        safeMaximumHeight(proposed)
    }

    static func isInNativeResizePerimeter(_ point: CGPoint, bounds: CGRect) -> Bool {
        guard bounds.contains(point) else { return false }
        let inset = nativeResizeEdgeInset
        return point.x - bounds.minX <= inset
            || bounds.maxX - point.x <= inset
            || point.y - bounds.minY <= inset
            || bounds.maxY - point.y <= inset
    }

    private static func normalizedFrame(
        _ frame: CGRect,
        maximumHeight requestedMaximumHeight: CGFloat,
        invalidHeightFallback: CGFloat,
        visibleFrame requestedVisibleFrame: CGRect?
    ) -> CGRect {
        let visibleFrame = validVisibleFrame(requestedVisibleFrame)
        let maximumHeight = safeMaximumHeight(visibleFrame?.height ?? requestedMaximumHeight)

        let sourceHeight: CGFloat
        let targetHeight: CGFloat
        if isSafeDimension(frame.height), frame.height >= minimumHeight {
            sourceHeight = frame.height
            targetHeight = min(frame.height, maximumHeight)
        } else {
            sourceHeight = isSafeDimension(frame.height) ? frame.height : invalidHeightFallback
            targetHeight = min(max(invalidHeightFallback, minimumHeight), maximumHeight)
        }

        var x = safeCoordinate(frame.origin.x, fallback: visibleFrame?.minX ?? 0)
        let sourceY = safeCoordinate(frame.origin.y, fallback: visibleFrame?.minY ?? 0)
        let sourceTop = safeCoordinate(sourceY + sourceHeight, fallback: sourceY + targetHeight)
        var y = sourceTop - targetHeight

        if let visibleFrame {
            if fixedWidth <= visibleFrame.width {
                x = min(max(x, visibleFrame.minX), visibleFrame.maxX - fixedWidth)
            } else {
                // An exceptionally narrow display cannot satisfy both fixed
                // width and full visibility. Centering keeps both sides equally
                // reachable instead of feeding a reversed clamp range.
                x = visibleFrame.midX - (fixedWidth / 2)
            }

            if targetHeight <= visibleFrame.height {
                y = min(max(y, visibleFrame.minY), visibleFrame.maxY - targetHeight)
            } else {
                // Keep the draggable header and top resize edge reachable.
                y = visibleFrame.maxY - targetHeight
            }
        }

        return CGRect(x: x, y: y, width: fixedWidth, height: targetHeight)
    }

    private static func safeMaximumHeight(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite, proposed > 0 else { return maximumSafeHeight }
        return min(max(proposed, minimumHeight), maximumSafeHeight)
    }

    private static func isSafeDimension(_ value: CGFloat) -> Bool {
        value.isFinite && value > 0 && value <= maximumSafeHeight
    }

    private static func safeCoordinate(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        guard value.isFinite, abs(value) <= maximumSafeCoordinateMagnitude else { return fallback }
        return value
    }

    private static func validVisibleFrame(_ frame: CGRect?) -> CGRect? {
        guard let frame,
              frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0
        else { return nil }
        return frame.standardized
    }
}
