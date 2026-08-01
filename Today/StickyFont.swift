import SwiftUI

/// Font options for a sticky's body text. The big "To Do" title always uses
/// Helvetica Neue Medium regardless of this choice.
enum StickyFont: String, CaseIterable, Codable, Identifiable {
    case helvetica   // "Basic" — the system font (SF Pro). Rawvalue kept as
                     // "helvetica" for compatibility with already-saved stickies.
    case menlo       // "Technical" — monospaced
    case stefan      // "Cute" — ABC Stefan Trial (Simple), bundled
    case bradley     // "Handwritten" — Bradley Hand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .helvetica: return "Basic"
        case .menlo:     return "Technical"
        case .stefan:    return "Cute"
        case .bradley:   return "Handwritten"
        }
    }

    /// The exact font name used with `Font.custom` (PostScript names where it
    /// matters, so the correct face renders rather than a synthesized one).
    /// Unused for `.helvetica`, which renders via `Font.system` instead.
    var fontName: String {
        switch self {
        case .helvetica: return "HelveticaNeue"
        case .menlo:     return "Menlo"
        case .stefan:    return "ABCStefanTrial-Simple"
        case .bradley:   return "Bradley Hand"
        }
    }

    /// Body font at a given size. The big "To Do" title always stays
    /// Helvetica Neue regardless of this choice (set directly in the view).
    func body(_ size: CGFloat) -> Font {
        if self == .helvetica {
            return .system(size: size + sizeAdjustment) // SF Pro
        }
        return Font.custom(fontName, size: size + sizeAdjustment)
    }

    /// Some faces read small at the same nominal point size (smaller
    /// x-height than System/Menlo) — nudge them up so all four options look
    /// the same visual size next to each other, e.g. in the Settings picker.
    var sizeAdjustment: CGFloat {
        switch self {
        case .bradley: return 3
        case .stefan: return 3
        default: return 0
        }
    }
}

extension StickyFont {
    private static let defaultsKey = "today.defaultStickyFont"

    /// The font new stickies are created with. Set from the status-bar menu.
    static var defaultFont: StickyFont {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(StickyFont.init) ?? .helvetica }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
