import Foundation

/// What happens when a sticky is closed (the X button, ⌘D, or the context
/// menu) — asking every time is the safe default, but some people know they
/// always want the same answer and would rather skip the dialog entirely.
/// Settable from the status menu, or from the dialog's own "Don't ask me
/// again" checkbox at the moment you pick Archive or Delete.
enum StickyCloseBehavior: String, CaseIterable, Identifiable, Codable {
    case alwaysAsk, alwaysArchive, alwaysDelete

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alwaysAsk: return "Always Ask"
        case .alwaysArchive: return "Always Archive"
        case .alwaysDelete: return "Always Delete"
        }
    }
}
