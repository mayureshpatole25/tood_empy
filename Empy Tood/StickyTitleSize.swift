import Foundation

/// The starting (largest) size for a sticky's title. The actual rendered
/// size can still shrink below this for long or wide text (see
/// `StickyRootView.titleFontSize`) — this just sets the ceiling, for
/// people who don't want the title quite so big.
enum StickyTitleSize: String, CaseIterable, Identifiable, Codable {
    case large, medium, small

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .large: return "Large"
        case .medium: return "Medium"
        case .small: return "Small"
        }
    }

    var baseSize: CGFloat {
        switch self {
        case .large: return 60
        case .medium: return 46
        case .small: return 34
        }
    }
}
