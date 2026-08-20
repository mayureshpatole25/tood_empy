import Foundation

/// Maps the first ten stickies to the compact Control-number row used by
/// both the status menu and app-local keyboard handling. As is conventional
/// for ten numbered slots on a keyboard, the tenth slot uses zero.
enum StickySelectionShortcut {
    static let maximumStickyCount = 10

    static func keyEquivalent(forStickyIndex index: Int) -> String? {
        guard (0..<maximumStickyCount).contains(index) else { return nil }
        return index == 9 ? "0" : String(index + 1)
    }

    static func stickyIndex(forKeyEquivalent key: String) -> Int? {
        guard key.count == 1, let number = Int(key) else { return nil }
        if number == 0 { return 9 }
        guard (1...9).contains(number) else { return nil }
        return number - 1
    }
}
