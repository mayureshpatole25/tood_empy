import SwiftUI
import AppKit

/// A tiny cached noise tile for the soft film-grain texture on the paper.
enum Grain {
    static let image: NSImage = make(120)

    private static func make(_ n: Int) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return NSImage() }

        for y in 0..<n {
            for x in 0..<n {
                let v = CGFloat.random(in: 0...1)
                let a = CGFloat.random(in: 0...0.45)
                rep.setColor(NSColor(white: v, alpha: a), atX: x, y: y)
            }
        }
        let img = NSImage(size: NSSize(width: n, height: n))
        img.addRepresentation(rep)
        return img
    }
}

/// Very light grain overlaid on the sticky (non-interactive).
struct GrainOverlay: View {
    var body: some View {
        Image(nsImage: Grain.image)
            .resizable(resizingMode: .tile)
            .opacity(0.05)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }
}
