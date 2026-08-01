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
    private let cardColor = StickyColor.orange

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

    /// The real sticky's own look, not a separate app-card style: same
    /// orange paper, same big "To Do" title in black ink, same minimal
    /// corner radius — just with one intro paragraph where the checklist
    /// would be, so this reads as one of the pile having landed face-up
    /// with the welcome message on it.
    private var welcomeStickyCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("To Do")
                .font(.custom("HelveticaNeue-Medium", size: 46))
                .foregroundStyle(cardColor.titleInk)
            Text("Welcome! Today is a calmer home for your to-dos — sticky notes that live right on your desktop, always in view.")
                .font(StickyFont.menlo.body(15))
                .foregroundStyle(cardColor.ink.opacity(0.8))
                .lineSpacing(3)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(action: onContinue) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(cardColor.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(28)
        .frame(width: 340, height: 460, alignment: .topLeading)
        .background(cardColor.paper, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 28, y: 18)
    }
}
