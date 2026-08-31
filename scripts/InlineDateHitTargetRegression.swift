import AppKit

@main
enum InlineDateHitTargetRegression {
    static func main() {
        let font = NSFont.systemFont(ofSize: 14)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 110, height: 68))
        let view = DateGlyphHitView(frame: root.bounds)
        var openedPicker = false
        let prefix = "Hello in "
        let date = "Today at 3:45 PM"
        view.text = prefix + date + " after"
        view.dateRange = NSRange(location: (prefix as NSString).length, length: (date as NSString).length)
        view.font = font
        view.onDateClick = { openedPicker = true }
        root.addSubview(view)
        view.layoutSubtreeIfNeeded()

        precondition(view.dateHitRectsForTesting.count >= 2,
                     "a wrapped date must expose every clickable line")
        for rect in view.dateHitRectsForTesting {
            let point = view.convert(NSPoint(x: rect.midX, y: rect.midY), to: root)
            precondition(view.hitTest(point) === view,
                         "every visible date line must open the picker")
        }

        let taskEnd = ("Hello in" as NSString).size(withAttributes: [.font: font]).width
        let taskPoint = view.convert(NSPoint(x: max(taskEnd - 2, 0), y: 12), to: root)
        precondition(view.hitTest(taskPoint) == nil,
                     "the last task glyph must remain a normal editor click")

        view.mouseDown(with: NSEvent())
        precondition(openedPicker, "a date click must invoke the picker callback")

        print("Inline date hit-target regression checks passed (\(view.dateHitRectsForTesting.count) wrapped regions).")
    }
}
