import CoreGraphics
import Foundation

/// The single source of truth for floating-sticky geometry.
///
/// AppKit's `minSize`/`maxSize` only constrain interactive resizing. They do
/// not repair an invalid initial frame and `setFrame(_:display:)` deliberately
/// bypasses them, so every persisted and programmatic frame also comes through
/// this policy before it reaches `NSWindow`.
enum StickyWindowGeometry {
    static let defaultWidth: CGFloat = 378
    static let minimumWidth: CGFloat = 280
    static let defaultHeight: CGFloat = 490
    static let minimumHeight: CGFloat = 400

    /// Large enough for any real display while preventing individually corrupt
    /// dimensions from reaching AppKit unchecked. StickyController additionally
    /// clamps the combined size to a real display before constructing NSWindow.
    static let maximumSafeWidth: CGFloat = 16_384
    static let maximumSafeHeight: CGFloat = 16_384
    static let maximumSafeCoordinateMagnitude: CGFloat = 1_000_000

    /// Mouse-downs inside this perimeter belong to AppKit's native resize
    /// tracking, never to the custom draggable header.
    static let nativeResizeEdgeInset: CGFloat = 12

    static let defaultSize = CGSize(width: defaultWidth, height: defaultHeight)
    static let minimumSize = CGSize(width: minimumWidth, height: minimumHeight)
    static let maximumSafeSize = CGSize(width: maximumSafeWidth, height: maximumSafeHeight)

    /// Sanitizes data loaded from disk before an `NSWindow` is constructed.
    /// A paper-thin or otherwise corrupt legacy size reopens at the normal
    /// default on that axis; intentional user-selected dimensions survive.
    static func persistedFrame(_ frame: CGRect) -> CGRect {
        normalizedFrame(
            frame,
            maximumSize: maximumSafeSize,
            invalidSizeFallback: defaultSize,
            visibleFrame: nil
        )
    }

    /// Constrains a live/programmatic size. Unlike persisted corruption, a
    /// resize below either lower bound stops exactly at the declared minimum.
    static func constrainedSize(
        _ proposedSize: CGSize,
        maximumSize requestedMaximumSize: CGSize = maximumSafeSize
    ) -> CGSize {
        let maximumSize = safeMaximumSize(requestedMaximumSize)
        let proposedWidth = proposedSize.width.isFinite && proposedSize.width > 0
            ? proposedSize.width
            : defaultWidth
        let proposedHeight = proposedSize.height.isFinite && proposedSize.height > 0
            ? proposedSize.height
            : defaultHeight
        return CGSize(
            width: min(max(proposedWidth, minimumWidth), maximumSize.width),
            height: min(max(proposedHeight, minimumHeight), maximumSize.height)
        )
    }

    /// Repairs runtime geometry while preserving its top edge. Pass a visible
    /// frame when the whole sticky must be brought back on-screen (launch,
    /// reopen, display changes, and the end of a live resize).
    static func runtimeFrame(_ frame: CGRect, visibleFrame: CGRect? = nil) -> CGRect {
        normalizedFrame(
            frame,
            maximumSize: visibleFrame?.size ?? maximumSafeSize,
            invalidSizeFallback: minimumSize,
            visibleFrame: visibleFrame
        )
    }

    /// Repairs size without changing an otherwise valid position. Used while
    /// a native live resize is in progress, when AppKit owns the anchored edge.
    static func runtimeFrame(_ frame: CGRect, maximumSize: CGSize) -> CGRect {
        normalizedFrame(
            frame,
            maximumSize: maximumSize,
            invalidSizeFallback: minimumSize,
            visibleFrame: nil
        )
    }

    static func effectiveMaximumSize(_ proposed: CGSize) -> CGSize {
        safeMaximumSize(proposed)
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
        maximumSize requestedMaximumSize: CGSize,
        invalidSizeFallback: CGSize,
        visibleFrame requestedVisibleFrame: CGRect?
    ) -> CGRect {
        let visibleFrame = validVisibleFrame(requestedVisibleFrame)
        let maximumSize = safeMaximumSize(visibleFrame?.size ?? requestedMaximumSize)

        var targetWidth: CGFloat
        if isSafeDimension(frame.width, upperBound: maximumSafeWidth), frame.width >= minimumWidth {
            targetWidth = min(frame.width, maximumSize.width)
        } else {
            targetWidth = min(
                max(invalidSizeFallback.width, minimumWidth),
                maximumSize.width
            )
        }

        let sourceHeight: CGFloat
        var targetHeight: CGFloat
        if isSafeDimension(frame.height, upperBound: maximumSafeHeight), frame.height >= minimumHeight {
            sourceHeight = frame.height
            targetHeight = min(frame.height, maximumSize.height)
        } else {
            sourceHeight = isSafeDimension(frame.height, upperBound: maximumSafeHeight)
                ? frame.height
                : invalidSizeFallback.height
            targetHeight = min(
                max(invalidSizeFallback.height, minimumHeight),
                maximumSize.height
            )
        }

        var x = safeCoordinate(frame.origin.x, fallback: visibleFrame?.minX ?? 0)
        let sourceY = safeCoordinate(frame.origin.y, fallback: visibleFrame?.minY ?? 0)
        let sourceTop = safeCoordinate(sourceY + sourceHeight, fallback: sourceY + targetHeight)
        var y = sourceTop - targetHeight

        if let visibleFrame {
            if targetWidth <= visibleFrame.width {
                x = min(max(x, visibleFrame.minX), visibleFrame.maxX - targetWidth)
            } else {
                // An exceptionally narrow display cannot satisfy both the
                // minimum width and full visibility. Centering keeps both sides
                // equally reachable instead of feeding a reversed clamp range.
                x = visibleFrame.midX - (targetWidth / 2)
            }

            if targetHeight <= visibleFrame.height {
                y = min(max(y, visibleFrame.minY), visibleFrame.maxY - targetHeight)
            } else {
                // Keep the draggable header and top resize edge reachable.
                y = visibleFrame.maxY - targetHeight
            }
        }

        return CGRect(x: x, y: y, width: targetWidth, height: targetHeight)
    }

    private static func safeMaximumSize(_ proposed: CGSize) -> CGSize {
        CGSize(
            width: safeMaximumWidth(proposed.width),
            height: safeMaximumHeight(proposed.height)
        )
    }

    private static func safeMaximumWidth(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite, proposed > 0 else { return maximumSafeWidth }
        return min(max(proposed, minimumWidth), maximumSafeWidth)
    }

    private static func safeMaximumHeight(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite, proposed > 0 else { return maximumSafeHeight }
        return min(max(proposed, minimumHeight), maximumSafeHeight)
    }

    private static func isSafeDimension(_ value: CGFloat, upperBound: CGFloat) -> Bool {
        value.isFinite && value > 0 && value <= upperBound
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
