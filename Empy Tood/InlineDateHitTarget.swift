import AppKit
import SwiftUI

/// A transparent pointer layer over the stable SwiftUI TextField. It accepts
/// clicks only on the date glyphs and returns `nil` everywhere else so normal
/// task-text clicks continue straight through to the native editor beneath.
struct InlineDateHitTarget: NSViewRepresentable {
    let text: String
    let dateRange: NSRange
    let font: NSFont
    let onDateClick: () -> Void

    func makeNSView(context: Context) -> DateGlyphHitView {
        let view = DateGlyphHitView()
        view.onDateClick = onDateClick
        return view
    }

    func updateNSView(_ view: DateGlyphHitView, context: Context) {
        view.text = text
        view.dateRange = dateRange
        view.font = font
        view.onDateClick = onDateClick
        view.needsLayout = true
    }
}

final class DateGlyphHitView: NSView {
    var text = ""
    var dateRange = NSRange(location: 0, length: 0)
    var font = NSFont.systemFont(ofSize: 14)
    var onDateClick: (() -> Void)?

    private var dateRects: [NSRect] = []
    var dateHitRectsForTesting: [NSRect] { dateRects }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        dateRects = Self.dateRects(
            text: text,
            dateRange: dateRange,
            font: font,
            size: bounds.size
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        return dateRects.contains(where: { $0.contains(localPoint) }) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onDateClick?()
    }

    private static func dateRects(
        text: String,
        dateRange: NSRange,
        font: NSFont,
        size: NSSize
    ) -> [NSRect] {
        guard size.width > 0 else { return [] }
        guard dateRange.length > 0, NSMaxRange(dateRange) <= (text as NSString).length else { return [] }

        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = 12
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        let usedHeight = layoutManager.usedRect(for: container).height
        let verticalOffset = max(0, (size.height - usedHeight) / 2)

        let glyphRange = layoutManager.glyphRange(forCharacterRange: dateRange, actualCharacterRange: nil)
        var rects: [NSRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container
        ) { rect, _ in
            let positioned = rect.offsetBy(dx: 0, dy: verticalOffset)
            rects.append(NSRect(
                x: positioned.minX,
                y: positioned.minY - 4,
                width: positioned.width + 3,
                height: positioned.height + 8
            ))
        }
        return rects
    }
}
