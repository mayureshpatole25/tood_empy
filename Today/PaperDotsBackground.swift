import SwiftUI

/// A very faint dot-grid texture, like a bullet-journal page — the one
/// element that reads as "paper" before anything else on the Home screen
/// does. Deliberately close to invisible: light cream-grey dots at low
/// opacity, not a decorative pattern.
struct PaperDotsBackground: View {
    var spacing: CGFloat = 22
    var dotSize: CGFloat = 1.3
    var color: Color = Color(hex: 0xEDE6D2)

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                        with: .color(color)
                    )
                    y += spacing
                }
                x += spacing
            }
        }
        .opacity(0.5)
        .allowsHitTesting(false)
    }
}
