import SpriteKit

/// The first-run intro: a pile of stickies drop in one at a time from off
/// the top of the screen and stack up like blocks in Tetris.
///
/// This deliberately does NOT use SpriteKit's rigid-body physics engine —
/// that was the first version, and with ~25 small overlapping bodies it
/// jittered and never fully settled (bounce + gravity + a solver trying to
/// resolve dozens of simultaneous contacts every frame reads as "choppy",
/// not smooth). Instead each card's landing spot is computed analytically
/// (the top of whatever's already stacked directly beneath its x position,
/// same idea as a Tetris column height check) and it's animated there with
/// a plain eased `SKAction` — pure interpolation, nothing to resolve or
/// jitter, which is why it reads as smooth. Moving the cursor gently tilts
/// the landed pile toward it — the closest thing to "tilt your laptop" a
/// sandboxed Mac app can do; there's no public/sandbox-safe accelerometer
/// API on macOS.
final class StickyFallScene: SKScene {
    private let colors: [StickyColor] = [.blue, .pink, .cream, .green, .orange]
    private let cardSize = CGSize(width: 80, height: 102)

    // Tuned by eye via a live debug panel during development (since
    // removed) — these are the values that landed.
    private let dropCount = 22
    private let spawnInterval: TimeInterval = 0.21
    private let fallDurationBase = 0.52
    private let fallDurationJitter = 0.18
    private let dramaticTiltChance = 0.55
    private let bounceHeight: CGFloat = 12
    private let packRadiusMultiplier: CGFloat = 1.70

    private var started = false
    private var spawnedCount = 0
    private var settledCount = 0
    private var lastSpawnTime: TimeInterval = -1
    /// Resting footprints of everything that's landed so far, used purely
    /// for the stacking-height math — not physics bodies.
    private var landedFootprints: [CGRect] = []
    private var landedNodes: [StickyNode] = []
    private var pointerNormalizedX: CGFloat = 0
    private var hasFinished = false

    /// The view watches this to reveal "Continue" once every card has landed.
    var onSettled: (() -> Void)?

    override func didMove(to view: SKView) {
        guard !started else { return }
        started = true
        backgroundColor = .clear
        scaleMode = .aspectFill
        view.window?.acceptsMouseMovedEvents = true
    }

    override func update(_ currentTime: TimeInterval) {
        if lastSpawnTime < 0 { lastSpawnTime = currentTime }
        if spawnedCount < dropCount, currentTime - lastSpawnTime >= spawnInterval {
            lastSpawnTime = currentTime
            spawnOne()
            spawnedCount += 1
        }

        // Cosmetic cursor tilt: landed cards ease toward a rotation biased
        // by cursor x, instead of snapping — smoothed by a small lerp each
        // frame rather than driven by a physics gravity vector.
        let maxTilt: CGFloat = 0.12
        let target = pointerNormalizedX * maxTilt
        for node in landedNodes {
            node.zRotation += ((node.baseRotation + target) - node.zRotation) * 0.05
        }
    }

    private func spawnOne() {
        let color = colors[spawnedCount % colors.count]
        let node = StickyNode(size: cardSize, color: color)
        let minXBound = cardSize.width / 2
        let maxXBound = max(minXBound, frame.width - cardSize.width / 2)
        // Biased toward the middle (average of two uniform samples) rather
        // than flat across the whole width — builds up a mound in the
        // center with the desk showing at the edges, instead of tiling
        // edge-to-edge like a completely covered floor.
        let spawnX = min(max(
            (CGFloat.random(in: minXBound...maxXBound) + CGFloat.random(in: minXBound...maxXBound)) / 2,
            minXBound), maxXBound)
        let (finalX, landingY) = bestLanding(near: spawnX, minXBound: minXBound, maxXBound: maxXBound)

        // Tipped like scattered coins, not neat playing cards — most land
        // well off-vertical, and close to half go all the way onto their
        // side.
        if Double.random(in: 0...1) < dramaticTiltChance {
            let sign: CGFloat = Bool.random() ? 1 : -1
            node.baseRotation = sign * CGFloat.random(in: 0.85...1.45)
        } else {
            node.baseRotation = CGFloat.random(in: -0.6...0.6)
        }

        let startX = spawnX
        let startY = frame.height + cardSize.height
        node.position = CGPoint(x: startX, y: startY)
        node.zRotation = CGFloat.random(in: -0.6...0.6)
        addChild(node)

        landedFootprints.append(CGRect(
            x: finalX - cardSize.width / 2, y: landingY - cardSize.height / 2,
            width: cardSize.width, height: cardSize.height
        ))

        // Foam-cube toss, not a plumb drop: x eases out (the sideways slide
        // resolves early) while y eases in (gravity accelerating it down),
        // so it visibly arcs toward wherever it's slotting in rather than
        // falling in a dead-straight vertical line.
        let fallDuration = fallDurationBase + Double.random(in: 0...fallDurationJitter)
        let dx = finalX - startX
        let dy = landingY - startY
        let arc = SKAction.customAction(withDuration: fallDuration) { n, elapsed in
            let t = min(1, elapsed / CGFloat(fallDuration))
            let xt = 1 - pow(1 - t, 3)
            let yt = t * t * t
            n.position = CGPoint(x: startX + dx * xt, y: startY + dy * yt)
        }

        // Two decaying little bounces on impact — the "fluid and bouncy"
        // foam-cube landing, without a physics engine to jitter on it.
        let bounce1 = SKAction.moveTo(y: landingY + bounceHeight, duration: 0.09)
        bounce1.timingMode = .easeOut
        let drop1 = SKAction.moveTo(y: landingY, duration: 0.1)
        drop1.timingMode = .easeIn
        let bounce2 = SKAction.moveTo(y: landingY + bounceHeight * 0.35, duration: 0.055)
        bounce2.timingMode = .easeOut
        let drop2 = SKAction.moveTo(y: landingY, duration: 0.06)
        drop2.timingMode = .easeIn
        let move = SKAction.sequence([arc, bounce1, drop1, bounce2, drop2])

        let rotateIn = SKAction.rotate(toAngle: node.baseRotation * 1.4, duration: fallDuration, shortestUnitArc: true)
        rotateIn.timingMode = .easeOut
        let rotateSettle = SKAction.rotate(toAngle: node.baseRotation, duration: 0.22)
        rotateSettle.timingMode = .easeOut
        let rotate = SKAction.sequence([rotateIn, rotateSettle])

        node.run(.group([move, rotate])) { [weak self, weak node] in
            guard let self, let node else { return }
            self.landedNodes.append(node)
            self.settledCount += 1
            if self.settledCount >= self.dropCount, !self.hasFinished {
                self.hasFinished = true
                self.onSettled?()
            }
        }
    }

    /// The top of whatever's already stacked directly beneath a card
    /// centered at `x` — or the floor if the column's empty. Same idea as
    /// checking column height before a piece lands in Tetris.
    private func restingY(forX x: CGFloat) -> CGFloat {
        let minX = x - cardSize.width / 2
        let maxX = x + cardSize.width / 2
        let highest = landedFootprints
            .filter { $0.minX < maxX && $0.maxX > minX }
            .map(\.maxY)
            .max() ?? 0
        return highest + cardSize.height / 2
    }

    /// Scans a window around the spawn point for the lowest available
    /// landing — i.e. rolls sideways into the nearest gap instead of always
    /// planting straight down under its release point, so the pile packs in
    /// tight rather than growing as separate skinny columns with gaps
    /// between them.
    private func bestLanding(near x0: CGFloat, minXBound: CGFloat, maxXBound: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let searchRadius = cardSize.width * packRadiusMultiplier
        let step: CGFloat = 10
        var bestX = min(max(x0, minXBound), maxXBound)
        var bestY = restingY(forX: bestX)
        var x = max(minXBound, x0 - searchRadius)
        let end = min(maxXBound, x0 + searchRadius)
        while x <= end {
            let y = restingY(forX: x)
            if y < bestY - 1 {
                bestY = y
                bestX = x
            }
            x += step
        }
        return (bestX, bestY)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = event.location(in: self)
        pointerNormalizedX = (loc.x / max(frame.width, 1)) - 0.5
    }
}

/// A short pool of real-looking to-dos, so the falling stickies read as
/// actual checklists instead of abstract gray bars.
private let sampleTodos = [
    "Buy milk", "Call mom", "Walk dog", "Pay rent", "Read book",
    "Meal prep", "Buy coffee", "Do laundry", "Reply email", "Team sync",
    "Grocery run", "Backup files", "Wash car", "Book flight", "Pack bag",
    "Send invoice", "Water plants", "Clean desk", "Renew ID", "Plan trip",
]

/// One falling sticky: same paper/title/checklist look as the real thing —
/// a "To Do" title and a few checklist rows (checkbox + short item), some
/// pre-checked — so the pile reads as actual to-do lists, not decoration.
private final class StickyNode: SKShapeNode {
    /// The rotation it settles at once landed, before the cosmetic cursor
    /// tilt in `StickyFallScene.update` nudges it further.
    var baseRotation: CGFloat = 0

    init(size: CGSize, color: StickyColor) {
        super.init()
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        fillColor = NSColor(color.paper)
        strokeColor = NSColor(color.ink).withAlphaComponent(0.08)
        lineWidth = 1

        let left = -size.width / 2 + 10
        let top = size.height / 2 - 10

        let title = SKLabelNode(fontNamed: "HelveticaNeue")
        title.text = "To Do"
        title.fontSize = 12
        title.fontColor = NSColor(color.titleInk)
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .top
        title.position = CGPoint(x: left, y: top)
        addChild(title)

        let items = sampleTodos.shuffled().prefix(3)
        for (i, text) in items.enumerated() {
            let rowY = top - 26 - CGFloat(i) * 17
            let isDone = Bool.random() && i > 0

            let box = SKShapeNode(rectOf: CGSize(width: 8, height: 8), cornerRadius: 1.5)
            box.position = CGPoint(x: left + 4, y: rowY)
            if isDone {
                box.fillColor = NSColor(color.ink).withAlphaComponent(0.3)
                box.strokeColor = .clear
            } else {
                box.fillColor = .clear
                box.strokeColor = NSColor(color.ink).withAlphaComponent(0.3)
                box.lineWidth = 1
            }
            addChild(box)

            let label = SKLabelNode(fontNamed: "HelveticaNeue")
            label.text = text
            label.fontSize = 7.5
            label.fontColor = NSColor(color.ink).withAlphaComponent(isDone ? 0.35 : 0.75)
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: left + 12, y: rowY)
            addChild(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
