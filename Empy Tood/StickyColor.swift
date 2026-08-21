import SwiftUI

/// The built-in sticky colors. Color is chosen per-sticky.
/// Hex values come straight from Renee's Figma file.
enum StickyColor: String, CaseIterable, Codable, Identifiable {
    case pink       // #FE9591 — default
    case cream      // #F8E6CF
    case blue       // #72D6E9
    case orange     // #FE6926
    case green      // #17C862

    // Additional palette — hex values from Renee. The raw values stay stable
    // so existing stickies keep their saved colors.
    case candyLavender  // #ABCCF8
    case candyCoral     // #FF5E58
    case candyPink      // #FFB2D5
    case candyYellow    // #FFE74E
    case candyMint      // #94F48F

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pink:   return "Pink"
        case .cream:  return "Cream"
        case .blue:   return "Blue"
        case .orange: return "Orange"
        case .green:  return "Green"
        case .candyLavender: return "Lavender"
        case .candyCoral:    return "Coral"
        case .candyPink:     return "Bubblegum"
        case .candyYellow:   return "Lemon"
        case .candyMint:     return "Mint"
        }
    }

    /// The sticky "paper" fill.
    var paper: Color {
        switch self {
        case .pink:   return hex(0xFE9591)
        case .cream:  return hex(0xF8E6CF)
        case .blue:   return hex(0x72D6E9)
        case .orange: return hex(0xFE6926)
        case .green:  return hex(0x17C862)
        case .candyLavender: return hex(0xABCCF8)
        case .candyCoral:    return hex(0xFF5E58)
        case .candyPink:     return hex(0xFFB2D5)
        case .candyYellow:   return hex(0xFFE74E)
        case .candyMint:     return hex(0x94F48F)
        }
    }

    /// Ink for the "To Do" title (#232320).
    var titleInk: Color { hex(0x232320) }

    /// Ink for items, checkbox, divider and the date (#20211E).
    var ink: Color { hex(0x20211E) }

    /// Grey for completed (struck-through) items.
    var inkSecondary: Color { ink.opacity(0.45) }

    /// Hairline divider under each checklist row.
    var divider: Color { ink.opacity(0.18) }

    private func hex(_ v: UInt32) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }
}

extension StickyColor {
    private static let defaultsKey = "today.defaultStickyColor"

    /// The color new stickies are created with, set from the status-bar
    /// menu. `nil` means no default has been chosen — new stickies get a
    /// random color instead (see `nextNewStickyColor()`).
    static var defaultColor: StickyColor? {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(StickyColor.init) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }

    /// "Random" is a predictable rotation through the full built-in palette.
    private static let cycleOrder: [StickyColor] = StickyColor.allCases
    private static let cycleIndexKey = "today.stickyColorCycleIndex"

    /// What a freshly-created sticky should be colored: the chosen default,
    /// or the next color in the cycle if none has been set.
    static func nextNewStickyColor() -> StickyColor {
        if let defaultColor { return defaultColor }
        let index = UserDefaults.standard.integer(forKey: cycleIndexKey) // 0 if never set
        UserDefaults.standard.set(index + 1, forKey: cycleIndexKey)
        return cycleOrder[index % cycleOrder.count]
    }
}
