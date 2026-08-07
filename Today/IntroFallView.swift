import SwiftUI
import SpriteKit

/// First thing you see on a true first run, before the onboarding wizard:
/// a pile of stickies tumble in and stack up on the desk (`StickyFallScene`).
/// Move the cursor and the pile tilts toward it. Once it settles, a welcome
/// sticky pops up centered over the pile — same page, no separate
/// "Continue" step. Modeled on Josh Puckett's Pica: its DMG background has
/// giant glyphs continuously piling up at the bottom of the screen with a
/// "Hello, Josh" card sitting on top of the heap; this is that idea with an
/// actual sticky as the card instead of a plain text block.
struct IntroFallView: View {
    var onContinue: () -> Void

    @State private var scene: StickyFallScene = {
        let scene = StickyFallScene(size: CGSize(width: 640, height: 520))
        scene.backgroundColor = .clear
        scene.speed = 1.35 // landed on during tuning — a touch brisker than real-time gravity
        return scene
    }()
    @State private var showCTA = false

    private let desk = Color(hex: 0xFBF8F1)
    private let cardColor = StickyColor.green

    var body: some View {
        ZStack {
            desk.ignoresSafeArea()
            PaperDotsBackground().ignoresSafeArea()

            SpriteView(scene: scene, options: [.allowsTransparency])
                .ignoresSafeArea()

            welcomeStickyCard
                .opacity(showCTA ? 1 : 0)
                .scaleEffect(showCTA ? 1 : 0.7)
                .allowsHitTesting(showCTA)
                .animation(.spring(response: 0.45, dampingFraction: 0.62), value: showCTA)
        }
        .frame(width: 640, height: 520)
        .onAppear {
            scene.onSettled = { showCTA = true }
        }
    }

    /// The real sticky's own look — emerald paper, minimal corner radius —
    /// just with white type (rather than the usual black ink).
    private var welcomeStickyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to Tood.")
                .font(.custom("HelveticaNeue-Medium", size: 34))
                .foregroundStyle(.white)
            Text("A place for simple, no-fuss to-dos. Create little sticky notes that live on your desktop.")
                .font(StickyFont.menlo.body(15))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)

            Spacer(minLength: 0)

            // One row, not a stacked text-then-button — the caption and
            // the arrow read as a single baseline this way instead of the
            // arrow sitting a full row below (and visually low against)
            // the text above it.
            HStack(alignment: .center) {
                Text("Made with care in Sydney and California.")
                    .font(StickyFont.menlo.body(12))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Button(action: onContinue) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(28)
        .frame(width: 340, height: 460, alignment: .topLeading)
        .background(
            // The grid sits behind the text (as part of the background,
            // not an overlay drawn on top of it) so it reads as texture
            // on the paper rather than something laid over the words.
            ZStack {
                cardColor.paper
                GridPatternOverlay()
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        )
        .shadow(color: .black.opacity(0.25), radius: 28, y: 18)
    }
}

/// A faint white grid texture for the welcome sticky — same "barely
/// there" convention as `PaperDotsBackground`, just a grid instead of
/// dots and white instead of ink, since this sits on the green paper
/// rather than the cream desk.
private struct GridPatternOverlay: View {
    var spacing: CGFloat = 20
    var lineWidth: CGFloat = 0.75
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x <= size.width {
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(color), lineWidth: lineWidth
                )
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(color), lineWidth: lineWidth
                )
                y += spacing
            }
        }
        .opacity(0.25)
        .allowsHitTesting(false)
    }
}
