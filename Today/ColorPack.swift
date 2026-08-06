import Foundation

/// A paid bundle of sticky colors, sold as a one-time purchase via Polar.
enum ColorPack: String, CaseIterable, Identifiable {
    case candy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .candy: return "Candy Pack"
        }
    }

    var priceDisplay: String {
        switch self {
        case .candy: return "$3.99"
        }
    }

    /// Colors unlocked by owning this pack, in display order.
    var colors: [StickyColor] {
        switch self {
        case .candy: return [.candyLavender, .candyCoral, .candyPink, .candyYellow, .candyMint]
        }
    }

    /// Polar checkout link — opens in the browser.
    var checkoutURL: URL {
        switch self {
        case .candy: return URL(string: "https://buy.polar.sh/polar_cl_sK0AiofXosBUkvEPktaB0wxzgjsrPHHPRghJi3ZyImq")!
        }
    }
}
