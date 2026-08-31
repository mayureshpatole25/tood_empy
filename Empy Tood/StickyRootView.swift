import AppKit
import SwiftUI
@preconcurrency import UserNotifications

private struct ChecklistRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct CompletionLineCountPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Int] = [:]

    static func reduce(value: inout [UUID: Int], nextValue: () -> [UUID: Int]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private enum HoverMotion {
    static let feedback = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14)
}

private enum StickyTimerMotion {
    static let stateChange = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
}

/// A solid remaining-time indicator that empties anticlockwise from twelve
/// o'clock, giving the timer a quiet pie-chart appearance.
private struct StickyTimerPie: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let amount = max(0, min(progress, 1))
        guard amount < 0.9999 else { return Path(ellipseIn: rect) }
        guard amount > 0 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + (360 * amount)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

@MainActor
private enum StickyTimerCompletion {
    static func schedule(
        identifier: String,
        after seconds: Double,
        stickyTitle: String,
        playsSound: Bool
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let addRequest = {
            let content = UNMutableNotificationContent()
            content.title = "Timer complete"
            content.body = stickyTitle.isEmpty
                ? "Your sticky timer is finished."
                : "\(stickyTitle) is ready."
            content.sound = playsSound ? .default : nil
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(seconds, 1),
                repeats: false
            )
            center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )
            )
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                addRequest()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
                    if allowed { addRequest() }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    static func cancel(identifier: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    static func playSelectedCompletionSound() {
        guard let name = AppSettings.shared.timerCompletionSound.systemSoundName else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

private struct StickyTimerControl: View {
    let model: StickyModel
    let defaultSeconds: Int
    let ink: Color
    let font: Font
    let reveal: () -> Void
    let prepareForEditing: () -> Void
    let restoreAfterEditing: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editingTime: Bool
    @State private var isNearby = false
    @State private var isHoveringRing = false
    @State private var isRunning = false
    @State private var hasStarted = false
    @State private var totalSeconds: Double
    @State private var remainingSeconds: Double
    @State private var endDate: Date?
    @State private var timeText: String

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(
        model: StickyModel,
        defaultSeconds: Int,
        ink: Color,
        font: Font,
        reveal: @escaping () -> Void,
        prepareForEditing: @escaping () -> Void,
        restoreAfterEditing: @escaping () -> Void
    ) {
        self.model = model
        self.defaultSeconds = max(defaultSeconds, 1)
        self.ink = ink
        self.font = font
        self.reveal = reveal
        self.prepareForEditing = prepareForEditing
        self.restoreAfterEditing = restoreAfterEditing
        _totalSeconds = State(initialValue: Double(max(defaultSeconds, 1)))
        _remainingSeconds = State(initialValue: Double(max(defaultSeconds, 1)))
        _timeText = State(initialValue: Self.format(Double(max(defaultSeconds, 1))))
    }

    var body: some View {
        HStack(spacing: 9) {
            TextField("5:00", text: $timeText)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(ink.opacity(0.3))
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .focused($editingTime)
                .onSubmit { submitEditedTime() }

            Button(action: toggleTimer) {
                ZStack {
                    if hasStarted {
                        Circle()
                            .fill(ink.opacity(isHoveringRing ? 0.025 : 0.08))
                        StickyTimerPie(
                            progress: remainingSeconds / max(totalSeconds, 1)
                        )
                        .fill(ink.opacity(isHoveringRing ? 0.08 : 0.48))
                    }
                    Image(systemName: buttonSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.52))
                        .opacity(!hasStarted || isHoveringRing || !isRunning ? 1 : 0)
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringRing = $0 }
            .accessibilityLabel(isRunning ? "Pause timer" : "Start timer")
            .help(isRunning ? "Pause timer (⌘P)" : "Start timer (⌘P)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .contentShape(Rectangle())
        .onHover { isNearby = $0 }
        .animation(reduceMotion ? nil : StickyTimerMotion.stateChange, value: isNearby)
        .animation(reduceMotion ? nil : StickyTimerMotion.stateChange, value: hasStarted)
        .animation(reduceMotion ? nil : StickyTimerMotion.stateChange, value: isHoveringRing)
        .onReceive(ticker) { now in tick(now) }
        .onChange(of: editingTime) { wasEditing, isEditing in
            if wasEditing, !isEditing { commitEditedTime() }
        }
        .onChange(of: defaultSeconds) { _, newValue in
            guard !hasStarted, !editingTime else { return }
            reset(to: newValue)
        }
        .onAppear {
            model.onToggleTimer = { toggleTimer() }
            model.onEditTimer = { focusTimeEditor() }
            model.onStopTimer = { stopTimer() }
        }
        .onDisappear {
            model.onToggleTimer = nil
            model.onEditTimer = nil
            model.onStopTimer = nil
            reset(to: defaultSeconds)
        }
    }

    private var notificationIdentifier: String {
        "sticky-timer-\(model.id.uuidString)"
    }

    private var buttonSymbol: String {
        isRunning ? (isHoveringRing ? "pause.fill" : "") : "play.fill"
    }

    private func toggleTimer() {
        reveal()
        if isRunning {
            tick(Date())
            isRunning = false
            endDate = nil
            StickyTimerCompletion.cancel(identifier: notificationIdentifier)
        } else {
            startTimer()
        }
    }

    private func startTimer() {
        if remainingSeconds <= 0 { remainingSeconds = totalSeconds }
        hasStarted = true
        isRunning = true
        endDate = Date().addingTimeInterval(remainingSeconds)
        StickyTimerCompletion.schedule(
            identifier: notificationIdentifier,
            after: remainingSeconds,
            stickyTitle: model.title,
            playsSound: AppSettings.shared.timerCompletionSound != .none
        )
    }

    private func tick(_ now: Date) {
        guard isRunning, let endDate else { return }
        remainingSeconds = max(0, endDate.timeIntervalSince(now))
        if !editingTime { timeText = Self.format(remainingSeconds) }
        guard remainingSeconds <= 0 else { return }
        isRunning = false
        self.endDate = nil
        StickyTimerCompletion.playSelectedCompletionSound()
    }

    private func commitEditedTime() {
        guard let seconds = Self.parse(timeText) else {
            timeText = Self.format(remainingSeconds)
            return
        }
        totalSeconds = seconds
        remainingSeconds = seconds
        hasStarted = hasStarted || isRunning
        if isRunning {
            endDate = Date().addingTimeInterval(seconds)
            StickyTimerCompletion.schedule(
                identifier: notificationIdentifier,
                after: seconds,
                stickyTitle: model.title,
                playsSound: AppSettings.shared.timerCompletionSound != .none
            )
        }
        timeText = Self.format(seconds)
    }

    private func submitEditedTime() {
        commitEditedTime()
        if !isRunning { startTimer() }
        editingTime = false
        DispatchQueue.main.async { restoreAfterEditing() }
    }

    private func stopTimer() {
        StickyTimerCompletion.cancel(identifier: notificationIdentifier)
        editingTime = false
        reset(to: defaultSeconds)
        isNearby = false
    }

    private func focusTimeEditor() {
        reveal()
        prepareForEditing()
        isNearby = true
        editingTime = true
        DispatchQueue.main.async {
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
        }
    }

    private func reset(to seconds: Int) {
        let value = Double(max(seconds, 1))
        isRunning = false
        hasStarted = false
        endDate = nil
        totalSeconds = value
        remainingSeconds = value
        timeText = Self.format(value)
    }

    private static func parse(_ value: String) -> Double? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard (1...2).contains(parts.count), parts.allSatisfy({ Double($0) != nil }) else { return nil }
        let seconds = parts.count == 1
            ? (Double(parts[0]) ?? 0) * 60
            : (Double(parts[0]) ?? 0) * 60 + (Double(parts[1]) ?? 0)
        return seconds > 0 ? min(seconds, 359_999) : nil
    }

    private static func format(_ seconds: Double) -> String {
        let rounded = max(0, Int(ceil(seconds)))
        return "\(rounded / 60):\(String(format: "%02d", rounded % 60))"
    }
}

private enum DoneItemsFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"

    var id: Self { self }

    func includes(_ completedAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard self != .allTime else { return true }
        guard let completedAt else { return false }

        switch self {
        case .today:
            return calendar.isDate(completedAt, inSameDayAs: now)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(completedAt) == true
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.contains(completedAt) == true
        case .allTime:
            return true
        }
    }
}

private enum CompletionMotion {
    static let feedback = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
    static let strike = Animation.linear(duration: 0.2)
    static let lineStagger: TimeInterval = 0.05

    static func strikeMilliseconds(for lineCount: Int) -> Int64 {
        200 + Int64(max(lineCount - 1, 0)) * 50
    }
}

private enum CompletionTextLayout {
    static func lineWidths(for text: String, font: NSFont, width: CGFloat) -> [CGFloat] {
        guard width > 0 else { return [1] }

        let storage = NSTextStorage(
            string: text.isEmpty ? " " : text,
            attributes: [.font: font]
        )
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true

        let container = NSTextContainer(
            containerSize: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = 12

        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let glyphRange = layoutManager.glyphRange(for: container)
        var widths: [CGFloat] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            _, usedRect, _, _, _ in
            widths.append(max(usedRect.width, 1))
        }
        return widths.isEmpty ? [1] : Array(widths.prefix(12))
    }
}

/// Mirrors the editable field's text layout, but renders only its decoration.
/// Keeping it separate leaves the real TextField (and its caret) uninterrupted
/// while each visual line reveals from left to right, then hands off to the
/// next line from top to bottom.
private struct CompletionStrikethrough: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let itemID: UUID
    let text: String
    let font: Font
    let nsFont: NSFont
    let color: Color
    let isVisible: Bool
    let animationsEnabled: Bool

    private var decoratedText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.clear)
            .strikethrough(true, color: color)
            .lineLimit(1...12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    let lineCount = CompletionTextLayout.lineWidths(
                        for: text,
                        font: nsFont,
                        width: proxy.size.width
                    ).count

                    Color.clear.preference(
                        key: CompletionLineCountPreferenceKey.self,
                        value: [itemID: lineCount]
                    )
                }
            }
    }

    @ViewBuilder
    var body: some View {
        if !animationsEnabled {
            decoratedText
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if reduceMotion {
            decoratedText
                .opacity(isVisible ? 1 : 0)
                .animation(CompletionMotion.feedback, value: isVisible)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            decoratedText
                .opacity(isVisible ? 1 : 0)
                .mask(alignment: .topLeading) {
                    CompletionStrikethroughMask(
                        text: text,
                        font: nsFont,
                        isVisible: isVisible
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct CompletionStrikethroughMask: View {
    let text: String
    let font: NSFont
    let isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            let lineWidths = CompletionTextLayout.lineWidths(
                for: text,
                font: font,
                width: proxy.size.width
            )

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lineWidths.enumerated()), id: \.offset) { index, lineWidth in
                    Rectangle()
                        .frame(width: lineWidth)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(
                            x: isVisible ? 1 : 0.001,
                            y: 1,
                            anchor: .leading
                        )
                        .animation(
                            isVisible
                                ? CompletionMotion.strike.delay(Double(index) * CompletionMotion.lineStagger)
                                : CompletionMotion.strike,
                            value: isVisible
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct CompletionParticleBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isChecked: Bool
    let paperColor: Color
    let inkColor: Color
    let animationsEnabled: Bool

    @State private var burst: Burst?

    private struct Particle {
        let degrees: Double
        let distance: CGFloat
        let delay: TimeInterval
        let size: CGFloat
        let shadeStrength: Double
    }

    private struct Burst {
        let id = UUID()
        let startedAt = Date()
        let particles = CompletionParticleBurst.makeParticles()
    }

    private static let baseParticles = [
        (distance: CGFloat(12), size: CGFloat(1.6)),
        (distance: CGFloat(15), size: CGFloat(2.0)),
        (distance: CGFloat(13), size: CGFloat(1.6)),
        (distance: CGFloat(16), size: CGFloat(2.1)),
        (distance: CGFloat(14), size: CGFloat(1.8)),
        (distance: CGFloat(12), size: CGFloat(1.6)),
    ]

    private static func makeParticles() -> [Particle] {
        let rotation = Double.random(in: 0..<360)

        return baseParticles.enumerated().map { index, particle in
            let evenSpacing = Double(index) * (360 / Double(baseParticles.count))
            return Particle(
                degrees: rotation + evenSpacing + Double.random(in: -20...20),
                distance: particle.distance * CGFloat.random(in: 0.78...1.12),
                delay: Double(index) * 0.01,
                size: particle.size * 1.1 * 1.15 * CGFloat.random(in: 0.82...1.24),
                shadeStrength: Double.random(in: 0.14...0.32)
            )
        }
    }

    private static let easeOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.23, y: 1),
        endControlPoint: UnitPoint(x: 0.32, y: 1)
    )

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: burst == nil)) { timeline in
            Canvas { context, size in
                guard let burst else { return }

                let elapsed = timeline.date.timeIntervalSince(burst.startedAt)
                let origin = CGPoint(x: size.width / 2, y: size.height / 2)

                for particle in burst.particles {
                    let rawProgress = (elapsed - particle.delay) / 0.3
                    guard rawProgress >= 0, rawProgress <= 1 else { continue }

                    let progress = min(max(rawProgress, 0), 1)
                    let easedProgress = CGFloat(Self.easeOut.value(at: progress))
                    let angle = CGFloat(particle.degrees * .pi / 180)
                    let radius = 5.5 + particle.distance * easedProgress
                    let diameter = particle.size * (1 - 0.25 * CGFloat(progress))
                    let fadeIn = min(1, progress / 0.08)
                    let fadeOut = 1 - max(0, (progress - 0.35) / 0.65)
                    let opacity = fadeIn * fadeOut

                    let center = CGPoint(
                        x: origin.x + cos(angle) * radius,
                        y: origin.y + sin(angle) * radius
                    )
                    let rect = CGRect(
                        x: center.x - diameter / 2,
                        y: center.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )

                    let path = Path(ellipseIn: rect)
                    context.fill(path, with: .color(paperColor.opacity(opacity)))
                    context.fill(
                        path,
                        with: .color(inkColor.opacity(opacity * particle.shadeStrength))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isChecked) { wasChecked, isChecked in
            if !wasChecked, isChecked, animationsEnabled, !reduceMotion {
                burst = Burst()
            } else if !isChecked || reduceMotion {
                burst = nil
            }
        }
        .onChange(of: reduceMotion) { _, shouldReduce in
            if shouldReduce {
                burst = nil
            }
        }
        .onChange(of: animationsEnabled) { _, isEnabled in
            if !isEnabled {
                burst = nil
            }
        }
        .task(id: burst?.id) {
            guard let burstID = burst?.id else { return }

            do {
                try await Task.sleep(for: .milliseconds(360))
            } catch {
                return
            }

            guard burst?.id == burstID else { return }
            burst = nil
        }
    }
}

private struct HoverFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let scale: CGFloat
    let darkening: Double
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion && isEnabled ? scale : 1)
            .brightness(isHovering && isEnabled ? darkening : 0)
            .animation(HoverMotion.feedback, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

private extension View {
    func hoverFeedback(
        scale: CGFloat,
        darkening: Double = 0,
        isEnabled: Bool = true
    ) -> some View {
        modifier(HoverFeedbackModifier(scale: scale, darkening: darkening, isEnabled: isEnabled))
    }
}

private enum TimerReturnFocus {
    case title(offset: Int)
    case item(UUID, offset: Int)
}

/// The visible sticky: flat, edge-to-edge paper with a big two-line "To Do"
/// title, a date, and an editable checklist. Hosted in a borderless window.
struct StickyRootView: View {
    let model: StickyModel
    unowned let controller: StickyController

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var focusedID: UUID?
    @FocusState private var titleFocused: Bool
    @State private var hovering = false
    @State private var hoveringTopChrome = false
    @State private var showColors = false
    @State private var timerReturnFocus: TimerReturnFocus?
    @State private var doneItemsFilter: DoneItemsFilter = .allTime
    @State private var retainedCompletionIDs: Set<UUID> = []
    @State private var completionExitTasks: [UUID: Task<Void, Never>] = [:]
    @State private var completionExitGenerations: [UUID: UUID] = [:]
    @State private var completionLineCounts: [UUID: Int] = [:]
    @State private var reduceMotionEnabled = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var draggingItemID: UUID?
    @State private var dragTranslationY: CGFloat = 0
    @State private var dragLayoutCompensationY: CGFloat = 0
    @State private var pressedCheckboxID: UUID?
    @State private var hoveredCheckboxID: UUID?
    @State private var addRowHovered = false
    @State private var suppressCheckboxToggleID: UUID?
    @State private var dateDraft: TaskDateDraft?
    @State private var highlightedDateSuggestion = 0
    /// The window's current width — the title needs it (see `header`) without a local
    /// `GeometryReader` forcing a fixed height on it. A previous version
    /// used a `titleWraps` heuristic (does the whole title fit on one line?)
    /// to pick between a 58pt/108pt box, on the assumption that "doesn't fit
    /// on one line" always means "fits in two" — it doesn't (emoji + a few
    /// words can need three), and since the box couldn't grow past whichever
    /// of those two heights it guessed, the overflow just silently clipped:
    /// title text still in the data, invisibly cut from view. Letting the
    /// TextField size itself intrinsically, with no guess in the way, is
    /// what actually guarantees it never happens.
    @State private var availableWidth: CGFloat
    @State private var availableHeight: CGFloat

    private let corner: CGFloat = 4
    private let contentInset: CGFloat = 24
    private var color: StickyColor { model.color }
    private var completionAnimationsEnabled: Bool {
        AppSettings.shared.completionAnimationsEnabled
    }
    private var showsTimer: Bool {
        AppSettings.shared.showsStickyTimers
    }
    private var showsDoneTasks: Bool {
        AppSettings.shared.showsDoneTasks
    }

    init(model: StickyModel, controller: StickyController) {
        self.model = model
        self.controller = controller
        _availableWidth = State(initialValue: model.frame.width)
        _availableHeight = State(initialValue: model.frame.height)
    }

    var body: some View {
        ZStack(alignment: .top) {
            paperBackground
            content
            bottomToolbar
            windowControls
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        // A `.background` GeometryReader reads the window's current width
        // without becoming the root
        // of the view tree — a GeometryReader as body's *root* (tried
        // earlier) has no well-defined ideal size of its own, which broke
        // NSHostingView.fittingSize for every other piece of sizing logic.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableWidth = proxy.size.width
                        availableHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        availableWidth = newSize.width
                        availableHeight = newSize.height
                    }
            }
        )
        .contextMenu { contextMenu }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hovering = true
                hoveringTopChrome = location.y <= 120
            case .ended:
                hovering = false
                hoveringTopChrome = false
            }
        }
        .onAppear {
            reduceMotionEnabled = accessibilityReduceMotion
            focusedID = nil
            model.focusedItemID = focusedID
            model.onSplitTitle = { caret in
                splitTitle(atUTF16Offset: caret)
            }
            model.onSplitItem = { id, caret in
                if let newID = model.splitItem(id, atUTF16Offset: caret) {
                    focusItem(newID, atUTF16Offset: 0)
                }
            }
            model.onMergeItemBackward = { id in
                if let item = model.items.first(where: { $0.id == id }) {
                    mergeBackward(item)
                }
            }
            model.onMergeItemForward = { id in
                mergeForward(id)
            }
            model.onRequestFocus = {
                if let first = displayedItems.first {
                    focusItem(first.id, atUTF16Offset: (first.text as NSString).length)
                }
            }
            model.onRequestLastItemFocus = {
                focusLastItemForTyping()
            }
            model.onToggleDoneVisibility = {
                toggleDoneTaskVisibility()
            }
            model.onMoveCaretToDocumentBoundary = { direction in
                if direction < 0 {
                    focusTitle(atUTF16Offset: 0)
                } else {
                    focusLastItemForTyping()
                }
            }
            model.onMoveCaretHorizontally = { sourceID, direction in
                moveCaretHorizontally(from: sourceID, direction: direction)
            }
            model.onMoveCaretVertically = { sourceID, direction, screenX in
                moveCaretVertically(from: sourceID, direction: direction, screenX: screenX)
            }
            model.onHandleDatePickerKey = { keyCode, modifiers in
                handleDatePickerKey(keyCode, modifiers: modifiers)
            }
            model.onHandleDateTokenKey = { keyCode, modifiers, selection in
                handleDateTokenKey(keyCode, modifiers: modifiers, selection: selection)
            }
            model.onNormalizeDateTokenSelection = { selection in
                normalizeDateTokenSelection(selection)
            }
            model.onMultilinePaste = { lines, targetID in
                if let lastID = model.pasteLines(lines, after: targetID) {
                    let offset = model.items.first(where: { $0.id == lastID })
                        .map { ($0.text as NSString).length } ?? 0
                    focusItem(lastID, atUTF16Offset: offset)
                }
            }
            model.onWillSetDone = { id, isDone in
                prepareDoneTransition(id: id, isDone: isDone)
            }
            focusLastItemForTyping()
        }
        .onDisappear {
            model.onWillSetDone = nil
            model.onToggleDoneVisibility = nil
            model.onHandleDatePickerKey = nil
            model.onHandleDateTokenKey = nil
            model.onNormalizeDateTokenSelection = nil
            cancelCompletionExitTasks()
        }
        .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
            reduceMotionEnabled = reduceMotion
        }
        .onChange(of: completionAnimationsEnabled) { _, isEnabled in
            if !isEnabled {
                cancelCompletionExitTasks()
            }
        }
        .onChange(of: showsDoneTasks) { wasShowing, isShowing in
            if isShowing {
                model.groupDoneItemsAtBottom()
            } else if wasShowing,
                      let focusedID,
                      model.items.first(where: { $0.id == focusedID })?.isDone == true {
                self.focusedID = nil
            }
        }
        .onChange(of: focusedID) { _, new in model.focusedItemID = new }
        .onChange(of: titleFocused) { _, new in model.isTitleFocused = new }
    }

    /// The flat paper itself.
    private var paperBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color.paper)
            GrainOverlay()
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    // MARK: - Content

    /// No trailing filler — this view's natural height is what the
    /// controller measures (via NSHostingView.fittingSize) to grow the
    /// window to fit.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 26)
            checklist
        }
        .padding(.horizontal, contentInset)
        // Leaves a calm, deliberate gap below the traffic lights instead
        // of letting the date compete with the window controls. Moving the
        // the chrome and content independently preserves this gap while the
        // shared horizontal inset keeps every left/right edge aligned.
        .padding(.top, 48)
        .padding(.bottom, 64) // clears the bottom hover toolbar, which now sits flush against the window edge
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The date sits on its own line above the title now — it used
            // to share the title's row (reserving a fixed slot beside it),
            // which ate into the title's width and made longer titles wrap
            // mid-word or get cut off. Up here it costs a line of height
            // instead, and the title gets the sticky's full width.
            HStack(alignment: .center, spacing: 12) {
                Text(Self.dateFormatter.string(from: model.day))
                    .font(bodyFont(14))
                    .foregroundStyle(color.ink.opacity(0.3))
                Spacer(minLength: 8)
            }

            // Gives the title an explicit maximum width budget — an
            // unconstrained TextField's ideal width just grows with its
            // content, so measuring that was circular and never actually
            // constrained anything (titles kept wrapping mid-word
            // regardless) — but deliberately no fixed *height*. A previous
            // version picked between a 58pt/108pt box using a "does it fit
            // on one line?" guess, on the assumption that "no" always means
            // "fits in two" — it doesn't (emoji + a few words can need
            // three), and since the box couldn't grow past whichever height
            // it guessed, real title text silently clipped out of view.
            // Leaving height alone lets the TextField report however tall
            // it genuinely needs to be, which is the only way to guarantee
            // that never happens again.
            let titleWidth = max(availableWidth - (contentInset * 2), 80)
            let titleSize = Self.titleFontSize(
                for: model.title, baseSize: AppSettings.shared.titleSize.baseSize, availableWidth: titleWidth
            )

            // Editable title — wraps naturally up to 3 lines (comfortably
            // covers "icon + a few words"; the shrink-to-fit below already
            // handles a single overlong word), Regular weight (Medium read
            // too bold). Steps down in size as the title gets longer (see
            // `titleFontSize`) so a single word that can't wrap (no space to
            // break on) shrinks instead of getting cut mid-word ("Admin" →
            // "Admi"/"n").
            TextField("To Do", text: titleBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.custom("HelveticaNeue", size: titleSize))
                .tracking(titleSize * -0.06) // -6% of size, same ratio at every step
                .foregroundStyle(color.titleInk)
                .tint(color.titleInk) // otherwise the cursor inherits the app's green accent — invisible on the green sticky
                .lineLimit(1...3)
                .lineSpacing(titleSize * -0.1) // ~90% line height, same ratio at every step
                // Return is handled by StickyController, which can see the
                // AppKit caret and split the title at the exact insertion point.
                .onKeyPress(.return) { .handled }
                .focused($titleFocused)
                .padding(.trailing, 6) // headroom for negative tracking on the last glyph
                // A fixed frame here makes the hosting view advertise the
                // current window width as its minimum. That turns every
                // horizontal expansion into a one-way ratchet. A flexible
                // maximum still gives wrapping a concrete budget without
                // preventing the native window from becoming narrower again.
                .frame(minWidth: 0, maxWidth: titleWidth, alignment: .topLeading)
        }
        .overlay(alignment: .topTrailing) {
            StickyTimerControl(
                model: model,
                defaultSeconds: AppSettings.shared.defaultTimerSeconds,
                ink: color.ink,
                font: bodyFont(14),
                reveal: { AppSettings.shared.showsStickyTimers = true },
                prepareForEditing: captureTimerReturnFocus,
                restoreAfterEditing: restoreFocusAfterTimerEdit
            )
            .frame(
                width: max(140, (availableWidth - contentInset * 2) * 0.42),
                height: 112,
                alignment: .topTrailing
            )
            .opacity(showsTimer ? 1 : 0)
            .allowsHitTesting(showsTimer)
            .accessibilityHidden(!showsTimer)
            .animation(
                accessibilityReduceMotion ? nil : StickyTimerMotion.stateChange,
                value: showsTimer
            )
        }
    }

    /// Shrinks the title (starting from `baseSize`, the user's chosen
    /// ceiling in Settings) until its widest *unbroken word* actually fits
    /// `availableWidth` — a character-count tier isn't right here, since a
    /// single word that's too wide can't be fixed by wrapping (there's no
    /// space to break on), it just gets cut mid-word. Multi-word titles
    /// still wrap normally between words at whatever size their longest
    /// word lands on; only an unbroken word ever forces a shrink.
    private static func titleFontSize(for text: String, baseSize: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return baseSize }
        let longestWord = text
            .components(separatedBy: " ")
            .max(by: { $0.count < $1.count }) ?? text

        // A few points of slack below the measured column width — the
        // caret, subpixel rounding, and the trailing padding above all eat
        // into it in ways a raw string measurement doesn't capture.
        let budget = max(availableWidth - 10, 40)
        var size = baseSize
        while size > 20 {
            let font = NSFont(name: "HelveticaNeue", size: size) ?? NSFont.systemFont(ofSize: size)
            let width = (longestWord as NSString)
                .size(withAttributes: [.font: font, .kern: size * -0.06])
                .width
            if width <= budget { break }
            size -= 2
        }
        return size
    }

    private var titleBinding: Binding<String> {
        Binding(get: { model.title }, set: { model.setTitle($0) })
    }

    /// Familiar macOS traffic-light controls. They only materialize while the
    /// pointer is in the sticky's top 120pt, keeping the paper quiet the rest
    /// of the time. Closing hides the sticky; it never archives or deletes it.
    private var windowControls: some View {
        VStack {
            HStack(spacing: 4) {
                trafficLight(color: Color(red: 1.0, green: 0.37, blue: 0.34),
                             label: "Close sticky") {
                    controller.closeSticky()
                }
                trafficLight(color: Color(red: 1.0, green: 0.74, blue: 0.18),
                             label: "Minimize sticky") {
                    controller.minimizeSticky()
                }
                Spacer(minLength: 0)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The circle is vertically centered inside a 16pt hit frame, adding
        // 2pt above its 12pt visual. 22 + 2 = the same 24pt as the left edge.
        .padding(.top, contentInset - 2)
        .padding(.leading, contentInset)
        .opacity(hoveringTopChrome ? 1 : 0)
        .allowsHitTesting(hoveringTopChrome)
        .animation(.easeInOut(duration: 0.15), value: hoveringTopChrome)
    }

    private func trafficLight(color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay(Circle().stroke(.black.opacity(0.14), lineWidth: 0.5))
                .frame(width: 12, height: 12)
                .frame(width: 16, height: 16, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverFeedback(scale: 1, darkening: -0.08)
        .accessibilityLabel(label)
        .help(label)
    }

    // MARK: - Checklist

    /// Uses whatever vertical room the resized sticky leaves below the
    /// header. Every item remains available; overflow scrolls inside this
    /// area instead of being replaced by "N more" / "Show less".
    private var checklist: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayedItems) { item in
                        row(item).id(item.id)
                    }

                    addRowButton
                }
                // The checklist's content stays aligned at its original x,
                // while its scroll viewport reaches into the paper inset so
                // left-flying completion particles are not clipped.
                .padding(.leading, contentInset)
            }
            .coordinateSpace(name: "checklist")
            .onPreferenceChange(ChecklistRowFramePreferenceKey.self) { frames in
                rowFrames = frames
            }
            .onPreferenceChange(CompletionLineCountPreferenceKey.self) { lineCounts in
                completionLineCounts = lineCounts
            }
            .scrollIndicators(.automatic)
            .onChange(of: focusedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: availableHeight) { _, _ in
                // A live shrink or a newly wrapped title can move the existing
                // caret outside the checklist viewport without changing focus.
                // Keep that row visible, but don't animate every resize tick.
                keepFocusedRowVisible(using: proxy)
            }
            .onChange(of: availableWidth) { _, _ in
                // Narrowing wraps both the title and checklist rows. Their
                // changed heights can displace the caret even though the
                // window's vertical dimension did not move.
                keepFocusedRowVisible(using: proxy)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.leading, -contentInset)
    }

    private func keepFocusedRowVisible(using proxy: ScrollViewProxy) {
        guard let focusedID,
              displayedItems.contains(where: { $0.id == focusedID })
        else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(focusedID, anchor: .center)
        }
    }

    private var doneTaskCount: Int {
        model.items.lazy.filter(\.isDone).count
    }

    /// Visibility is the only transformation applied here. The hidden-to-shown
    /// transition performs its one-time grouping in `toggleDoneTaskVisibility`;
    /// while shown, completion and drag operations retain the resulting order.
    private var displayedItems: [TodoItem] {
        model.orderedItems.filter {
            !$0.isDone ||
            retainedCompletionIDs.contains($0.id) ||
            (showsDoneTasks && doneItemsFilter.includes($0.completedAt))
        }
    }

    /// Always-there "next row," kept in the same scrollable checklist.
    private var addRowButton: some View {
        let inkOpacity = addRowHovered ? 0.46 : 0.32

        return Button {
            let newID = model.addItem()
            focusItem(newID, atUTF16Offset: 0)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color.ink.opacity(inkOpacity))
                    .frame(width: 13, height: 24)
                    .frame(width: 24, alignment: .leading)
                Text("Add to-do")
                    .font(bodyFont(14))
                    .foregroundStyle(color.ink.opacity(inkOpacity))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(HoverMotion.feedback, value: addRowHovered)
        .onHover { addRowHovered = $0 }
    }

    private func row(_ item: TodoItem) -> some View {
        let currentItem = model.items.first(where: { $0.id == item.id }) ?? item
        let dueDate = currentItem.dueDate
        let dateRange = currentItem.dueDateRange

        return ZStack {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 7) {
                    checkbox(item)
                    // Keep the proven native SwiftUI TextField as the sole
                    // editor/first responder. When a date exists, a combined
                    // Text overlay renders task + date as one wrapping run;
                    // the transparent hit layer accepts only date clicks.
                    ZStack(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                        TextField(
                            "",
                            text: textBinding(item),
                            prompt: dueDate == nil ? rowPrompt(item) : nil,
                            axis: .vertical
                        )
                            .textFieldStyle(.plain)
                            .font(bodyFont(14))
                            .foregroundStyle(dateRange == nil
                                ? (item.isDone ? color.inkSecondary : color.ink.opacity(0.8))
                                : Color.clear)
                            .tint(color.ink)
                            .lineLimit(1...12)
                            .focused($focusedID, equals: item.id)
                            .onKeyPress(.return, phases: .down) { press in
                                if press.modifiers.contains(.command) {
                                    toggleDone(item)
                                } else {
                                    submit(item)
                                }
                                return .handled
                            }
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                            .contentShape(Rectangle())
                        .onChange(of: bindingValue(item)) { _, newValue in
                            handleDash(item, newValue)
                            syncDateCommand(for: item.id, text: newValue)
                        }

                        if let dueDate, let dateRange {
                            inlineTaskText(currentItem, dateRange: dateRange)
                                .font(bodyFont(14))
                                .lineLimit(1...12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .allowsHitTesting(false)
                                .overlay {
                                    InlineDateHitTarget(
                                        text: currentItem.text,
                                        dateRange: dateRange,
                                        font: bodyNSFont(14),
                                        onDateClick: {
                                            openDatePicker(for: item.id, selectedDate: dueDate)
                                        }
                                    )
                                    .accessibilityLabel("Change date and time")
                                }
                        }

                        CompletionStrikethrough(
                            itemID: item.id,
                            text: bindingValue(item),
                            font: bodyFont(14),
                            nsFont: bodyNSFont(14),
                            color: color.inkSecondary,
                            isVisible: item.isDone,
                            animationsEnabled: completionAnimationsEnabled
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.leading, CGFloat(item.indentLevel) * 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(color.divider)
                    .frame(height: 1)
            }
            .offset(y: draggingItemID == item.id ? dragTranslationY - dragLayoutCompensationY : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChecklistRowFramePreferenceKey.self,
                    value: [item.id: proxy.frame(in: .named("checklist"))]
                )
            }
        )
        .zIndex(draggingItemID == item.id ? 1 : 0)
        .transaction { transaction in
            if draggingItemID == item.id {
                transaction.animation = nil
            }
        }
        .popover(
            isPresented: datePopoverPresented(for: item.id),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            TaskDateAssignmentPopover(
                draft: dateDraftBinding(for: item.id),
                highlightedSuggestion: highlightedDateSuggestion,
                onHighlight: { highlightedDateSuggestion = $0 },
                onChooseSuggestion: { suggestion in
                    commitDate(suggestion.date, includesTime: suggestion.includesTime, for: item.id)
                },
                onCommit: { date, includesTime in
                    commitDate(date, includesTime: includesTime, for: item.id)
                },
                onClear: { clearDate(for: item.id) },
                onCancel: { closeDatePicker() },
                onTimeEditingChange: { editing in
                    model.isDateTimeFieldEditing = editing
                }
            )
        }
        .transition(.opacity)
    }

    private func checkbox(_ item: TodoItem) -> some View {
        let isCheckboxHovered = hoveredCheckboxID == item.id
        let checkboxOpacity = isCheckboxHovered ? 0.42 : 0.3
        let checkboxScale: CGFloat
        if pressedCheckboxID == item.id && draggingItemID == nil {
            checkboxScale = 0.97
        } else if isCheckboxHovered && draggingItemID == nil && !accessibilityReduceMotion {
            checkboxScale = 1.1
        } else {
            checkboxScale = 1
        }
        let checkboxScaleAnchor: UnitPoint = pressedCheckboxID == item.id ? .center : .leading

        return Button {
            guard suppressCheckboxToggleID != item.id else { return }
            toggleDone(item)
        } label: {
            ZStack {
                if item.isDone {
                    // Fill only when done — layering a stroke of the same
                    // color underneath a fill double-blends their opacities
                    // (the centered stroke's outer half also peeks past the
                    // fill's edge), which is why the border read as a
                    // different shade than the fill.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.ink.opacity(checkboxOpacity))
                        .frame(width: 13, height: 13)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(color.ink.opacity(checkboxOpacity), lineWidth: 1.1)
                        .frame(width: 13, height: 13)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color.paper)
                    .opacity(item.isDone ? 1 : 0)
                    .scaleEffect(
                        accessibilityReduceMotion || !completionAnimationsEnabled || item.isDone
                            ? 1
                            : 0.92
                    )
                    .animation(
                        completionAnimationsEnabled && !accessibilityReduceMotion
                            ? CompletionMotion.feedback
                            : nil,
                        value: item.isDone
                    )
            }
            .frame(width: 13, height: 13)
            // Keep press/hover feedback on the checkbox itself so it neither
            // scales the hit frame nor stretches the particle travel.
            .scaleEffect(checkboxScale, anchor: checkboxScaleAnchor)
            .overlay {
                CompletionParticleBurst(
                    isChecked: item.isDone,
                    paperColor: color.paper,
                    inkColor: color.ink,
                    animationsEnabled: completionAnimationsEnabled
                )
                .frame(width: 46, height: 46)
                .id(item.id)
            }
            .padding(.leading, 1)
            // The visual checkbox shares the exact left edge used by the
            // date and title, inset by one point so the centered border
            // stroke stays inside the scroll view's clipped leading edge.
            // The remaining width stays as an easy target.
            .frame(width: 24, height: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(HoverMotion.feedback, value: isCheckboxHovered)
        .onHover { hoveredCheckboxID = $0 ? item.id : nil }
        .simultaneousGesture(reorderGesture(for: item, togglesOnTap: true))
        .accessibilityLabel(
            item.isDone
                ? "Mark \(item.text.isEmpty ? "to-do" : item.text) not done"
                : "Mark \(item.text.isEmpty ? "to-do" : item.text) done"
        )
        .accessibilityAction(named: "Move up") {
            moveVisibleItem(item, by: -1)
        }
        .accessibilityAction(named: "Move down") {
            moveVisibleItem(item, by: 1)
        }
        .help("Click to toggle, drag to reorder")
    }

    private func reorderGesture(for item: TodoItem, togglesOnTap: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("checklist"))
            .onChanged { value in
                if togglesOnTap, draggingItemID == nil {
                    pressedCheckboxID = item.id
                }

                let threshold: CGFloat = togglesOnTap ? 7 : 2
                guard abs(value.translation.height) >= threshold else { return }

                if draggingItemID == nil {
                    beginReordering(item, value: value)
                }
                guard draggingItemID == item.id else { return }

                pressedCheckboxID = nil
                dragTranslationY = value.translation.height
                reorderIfNeeded(item, pointerY: value.location.y)
            }
            .onEnded { value in
                let wasDragging = draggingItemID == item.id
                pressedCheckboxID = nil

                if wasDragging {
                    finishReordering()
                }

                // A Button may deliver its action just after the simultaneous
                // drag ends. Keep suppression through this event turn, then
                // clear it whether or not the pointer was released over it.
                if togglesOnTap {
                    DispatchQueue.main.async {
                        if suppressCheckboxToggleID == item.id {
                            suppressCheckboxToggleID = nil
                        }
                    }
                }
            }
    }

    private func beginReordering(_ item: TodoItem, value: DragGesture.Value) {
        guard rowFrames[item.id] != nil else { return }
        focusedID = nil
        titleFocused = false
        draggingItemID = item.id
        if item.id == pressedCheckboxID {
            suppressCheckboxToggleID = item.id
        }
        dragTranslationY = value.translation.height
        dragLayoutCompensationY = 0
    }

    private func reorderIfNeeded(_ item: TodoItem, pointerY: CGFloat) {
        let visible = displayedItems
        guard let currentIndex = visible.firstIndex(where: { $0.id == item.id }),
              let sourceFrame = rowFrames[item.id]
        else { return }

        let target: TodoItem?
        if currentIndex + 1 < visible.count,
           let nextFrame = rowFrames[visible[currentIndex + 1].id],
           pointerY > nextFrame.midY {
            target = visible[currentIndex + 1]
        } else if currentIndex > 0,
                  let previousFrame = rowFrames[visible[currentIndex - 1].id],
                  pointerY < previousFrame.midY {
            target = visible[currentIndex - 1]
        } else {
            target = nil
        }

        guard let target, let targetFrame = rowFrames[target.id] else { return }
        let layoutDelta: CGFloat
        if targetFrame.midY > sourceFrame.midY {
            layoutDelta = targetFrame.maxY - sourceFrame.maxY
        } else {
            layoutDelta = targetFrame.minY - sourceFrame.minY
        }
        dragLayoutCompensationY += layoutDelta

        let animation: Animation? = accessibilityReduceMotion
            ? nil
            : .interactiveSpring(response: 0.3, dampingFraction: 1, blendDuration: 0)
        withAnimation(animation) {
            model.moveItem(item.id, relativeTo: target.id)
        }
    }

    private func finishReordering() {
        let animation: Animation? = accessibilityReduceMotion
            ? nil
            : .interactiveSpring(response: 0.3, dampingFraction: 1, blendDuration: 0)
        withAnimation(animation) {
            draggingItemID = nil
            dragTranslationY = 0
            dragLayoutCompensationY = 0
        }
    }

    /// VoiceOver exposes the same ordering operation without requiring a
    /// precision drag. Keep keyboard/accessibility moves immediate; repeated
    /// commands should never make the interface wait for an animation.
    private func moveVisibleItem(_ item: TodoItem, by offset: Int) {
        let visible = displayedItems
        guard let sourceIndex = visible.firstIndex(where: { $0.id == item.id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard visible.indices.contains(destinationIndex) else { return }
        model.moveItem(item.id, relativeTo: visible[destinationIndex].id)
    }

    private func toggleDone(_ item: TodoItem) {
        let wasDone = item.isDone
        controller.toggleDone(item.id)

        guard !wasDone, !showsDoneTasks, focusedID == item.id else { return }
        moveFocusAfterHiding(item.id)
    }

    /// Completion keeps the editor continuous: prefer the next unfinished row,
    /// then the previous one, and finally the title when the checklist is empty.
    /// Update the two FocusStates in one turn instead of clearing focus first so
    /// AppKit never spends a run-loop iteration without an insertion point.
    private func moveFocusAfterHiding(_ completedID: UUID) {
        let ordered = model.orderedItems
        guard let completedIndex = ordered.firstIndex(where: { $0.id == completedID }) else { return }

        let next = ordered[(completedIndex + 1)...].first(where: { !$0.isDone })
        let previous = ordered[..<completedIndex].last(where: { !$0.isDone })
        if let destination = next ?? previous {
            model.isTitleFocused = false
            model.focusedItemID = destination.id
            controller.placeCaretOnNextItemFocus(destination.id, atUTF16Offset: 0)
            titleFocused = false
            focusedID = destination.id
        } else {
            model.focusedItemID = nil
            model.isTitleFocused = true
            controller.placeCaretOnNextTitleFocus(atUTF16Offset: (model.title as NSString).length)
            focusedID = nil
            titleFocused = true
        }
    }

    private func prepareDoneTransition(id: UUID, isDone: Bool) {
        completionExitTasks[id]?.cancel()
        completionExitTasks[id] = nil
        completionExitGenerations[id] = nil

        let suppressesTransition = controller.isReplayingCompletionHistory
        guard isDone, !showsDoneTasks, !suppressesTransition else {
            retainedCompletionIDs.remove(id)
            return
        }

        retainedCompletionIDs.insert(id)
        let generation = UUID()
        let retentionMilliseconds: Int64
        if !completionAnimationsEnabled {
            retentionMilliseconds = 0
        } else if reduceMotionEnabled {
            retentionMilliseconds = 120
        } else {
            retentionMilliseconds = CompletionMotion.strikeMilliseconds(
                for: completionLineCounts[id] ?? 1
            )
        }
        completionExitGenerations[id] = generation
        completionExitTasks[id] = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(retentionMilliseconds))
            } catch {
                return
            }

            guard completionExitGenerations[id] == generation else { return }
            guard model.items.first(where: { $0.id == id })?.isDone == true else {
                retainedCompletionIDs.remove(id)
                completionExitTasks[id] = nil
                completionExitGenerations[id] = nil
                return
            }

            if reduceMotionEnabled || !completionAnimationsEnabled {
                retainedCompletionIDs.remove(id)
            } else {
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)) {
                    _ = retainedCompletionIDs.remove(id)
                }
            }
            guard completionExitGenerations[id] == generation else { return }
            completionExitTasks[id] = nil
            completionExitGenerations[id] = nil
        }
    }

    private func cancelCompletionExitTasks() {
        for task in completionExitTasks.values {
            task.cancel()
        }
        completionExitTasks.removeAll()
        completionExitGenerations.removeAll()
        retainedCompletionIDs.removeAll()
    }

    // MARK: - Color picker

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(22)), count: 5), spacing: 10) {
            ForEach(StickyColor.allCases) { c in
                colorSwatchButton(c)
            }
        }
        .padding(12)
    }

    private func colorSwatchButton(_ c: StickyColor) -> some View {
        Button {
            model.setColor(c)
            showColors = false
        } label: {
            Circle()
                .fill(c.paper)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                .overlay(
                    Circle().stroke(color.ink, lineWidth: c == model.color ? 2 : 0)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom hover toolbar

    private func toggleDoneTaskVisibility() {
        if accessibilityReduceMotion {
            AppSettings.shared.showsDoneTasks.toggle()
        } else {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) {
                AppSettings.shared.showsDoneTasks.toggle()
            }
        }
    }

    private var bottomToolbar: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Button { toggleDoneTaskVisibility() } label: {
                        Image(systemName: showsDoneTasks ? "eye" : "eye.slash")
                    }
                    .hoverFeedback(scale: 1.1, darkening: -0.05)
                    .accessibilityLabel(showsDoneTasks ? "Hide done items" : "Show done items")
                    .help(showsDoneTasks ? "Hide done items (⌘S)" : "Show \(doneTaskCount) done items (⌘S)")

                    Menu {
                        ForEach(DoneItemsFilter.allCases) { filter in
                            Button {
                                doneItemsFilter = filter
                            } label: {
                                if doneItemsFilter == filter {
                                    Label(filter.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(filter.rawValue)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 12, height: 28)
                            .contentShape(Rectangle())
                    }
                    .disabled(doneTaskCount == 0)
                    .opacity(doneTaskCount == 0 ? 0.25 : 1)
                    .hoverFeedback(scale: 1.1, darkening: -0.05, isEnabled: doneTaskCount > 0)
                    .accessibilityLabel("Filter done items")
                    .help("Filter done items: \(doneItemsFilter.rawValue)")
                }

                Button { showColors.toggle() } label: { Image(systemName: "paintpalette") }
                    .hoverFeedback(scale: 1.1, darkening: -0.05)
                    .popover(isPresented: $showColors, arrowEdge: .top) {
                        colorPicker
                    }

                Button { AppSettings.shared.showsStickyTimers.toggle() } label: {
                    Image(systemName: "timer")
                }
                .opacity(showsTimer ? 1 : 0.55)
                .hoverFeedback(scale: 1.1, darkening: -0.05)
                .accessibilityLabel(showsTimer ? "Hide timer" : "Show timer")
                .help(showsTimer ? "Hide timer" : "Show timer")

                Button { controller.requestClose() } label: {
                    Image(systemName: "archivebox")
                }
                .hoverFeedback(scale: 1.1, darkening: -0.05)
                .accessibilityLabel("Archive or delete sticky")
                .help("Archive or delete sticky")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color.ink.opacity(0.5))
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                Capsule().fill(color.paper.opacity(0.6))
            )
            .padding(.bottom, 16)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .animation(.easeInOut(duration: 0.15), value: hovering)
        }
    }

    // MARK: - Context menu

    @ViewBuilder private var contextMenu: some View {
        Menu("Color") {
            ForEach(StickyColor.allCases) { c in
                Button(c.displayName) { model.setColor(c) }
            }
        }
        Divider()
        Button("New Sticky") { controller.requestNewSticky() }
        Button("Archive or Delete Sticky…", role: .destructive) { controller.requestClose() }
    }

    // MARK: - Editing helpers

    private func submit(_ item: TodoItem) {
        guard !isBlank(bindingValue(item)) else { return }
        let newID = model.addItem(after: item)
        focusItem(newID, atUTF16Offset: 0)
    }

    /// Crosses title/item boundaries after AppKit has exhausted the wrapped
    /// visual lines within the current field. The controller restores the
    /// caret at the closest screen-space x on the destination edge.
    private func moveCaretVertically(from sourceID: UUID?, direction: Int, screenX: CGFloat) {
        let ordered = displayedItems
        if sourceID == nil {
            guard direction > 0, let first = ordered.first else { return }
            focusItem(first.id, alignedToScreenX: screenX, entering: .top)
            return
        }

        guard let sourceID, let index = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        if direction < 0 {
            if index == 0 {
                focusTitle(alignedToScreenX: screenX, entering: .bottom)
            } else {
                focusItem(ordered[index - 1].id, alignedToScreenX: screenX, entering: .bottom)
            }
        } else if index + 1 < ordered.count {
            focusItem(ordered[index + 1].id, alignedToScreenX: screenX, entering: .top)
        }
    }

    /// Left/Right at a field boundary continues into the adjacent text block,
    /// exactly as if the title and checklist were one continuous document.
    private func moveCaretHorizontally(from sourceID: UUID?, direction: Int) {
        let ordered = displayedItems
        if sourceID == nil {
            guard direction > 0, let first = ordered.first else { return }
            focusItem(first.id, atUTF16Offset: 0)
            return
        }

        guard let sourceID, let index = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        if direction < 0 {
            if index == 0 {
                focusTitle(atUTF16Offset: (model.title as NSString).length)
            } else {
                let previous = ordered[index - 1]
                focusItem(previous.id, atUTF16Offset: (previous.text as NSString).length)
            }
        } else if index + 1 < ordered.count {
            focusItem(ordered[index + 1].id, atUTF16Offset: 0)
        }
    }

    private func captureTimerReturnFocus() {
        let caret = controller.currentCaretUTF16Offset()
        if titleFocused || model.isTitleFocused {
            timerReturnFocus = .title(offset: caret ?? (model.title as NSString).length)
        } else if let id = focusedID ?? model.focusedItemID,
                  let item = model.items.first(where: { $0.id == id }) {
            timerReturnFocus = .item(id, offset: caret ?? (item.text as NSString).length)
        } else {
            timerReturnFocus = nil
        }
    }

    private func restoreFocusAfterTimerEdit() {
        let destination = timerReturnFocus
        timerReturnFocus = nil
        switch destination {
        case .title(let offset):
            focusTitle(atUTF16Offset: offset)
        case .item(let id, let offset)
            where displayedItems.contains(where: { $0.id == id }):
            focusItem(id, atUTF16Offset: offset)
        default:
            focusLastItemForTyping()
        }
    }

    private func focusTitle(atUTF16Offset offset: Int) {
        focusedID = nil
        titleFocused = false
        DispatchQueue.main.async {
            model.focusedItemID = nil
            model.isTitleFocused = true
            controller.placeCaretOnNextTitleFocus(atUTF16Offset: offset)
            titleFocused = true
        }
    }

    private func focusTitle(alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        focusedID = nil
        titleFocused = false
        DispatchQueue.main.async {
            model.focusedItemID = nil
            model.isTitleFocused = true
            controller.placeCaretOnNextTitleFocus(alignedToScreenX: screenX, entering: edge)
            titleFocused = true
        }
    }

    private func focusItem(_ id: UUID, atUTF16Offset offset: Int) {
        titleFocused = false
        focusedID = nil
        DispatchQueue.main.async {
            model.isTitleFocused = false
            model.focusedItemID = id
            controller.placeCaretOnNextItemFocus(id, atUTF16Offset: offset)
            focusedID = id
        }
    }

    private func focusItem(_ id: UUID, alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        titleFocused = false
        focusedID = nil
        DispatchQueue.main.async {
            model.isTitleFocused = false
            model.focusedItemID = id
            controller.placeCaretOnNextItemFocus(id, alignedToScreenX: screenX, entering: edge)
            focusedID = id
        }
    }

    /// Restores the text-editing flow when Return is pressed while the sticky
    /// window, rather than one of its fields, owns keyboard focus.
    private func focusLastItemForTyping() {
        let targetID: UUID
        let caret: Int
        if let last = displayedItems.last {
            targetID = last.id
            caret = (last.text as NSString).length
        } else {
            targetID = model.addItem()
            caret = 0
        }

        focusItem(targetID, atUTF16Offset: caret)
    }

    /// Return in the title creates the first checklist line. If the sticky's
    /// existing invitation row is empty, reuse it instead of creating two
    /// blank rows. Text after the caret moves into the new line.
    private func splitTitle(atUTF16Offset offset: Int) {
        let title = model.title as NSString
        let split = min(max(offset, 0), title.length)
        let prefix = title.substring(to: split)
        let suffix = title.substring(from: split)

        model.setTitle(prefix)
        let targetID: UUID
        if let first = model.orderedItems.first, isBlank(bindingValue(first)) {
            model.setText(first.id, suffix)
            targetID = first.id
        } else {
            let item = TodoItem(text: suffix)
            model.items.insert(item, at: 0)
            model.onChange?()
            targetID = item.id
        }

        // The first row is commonly still stored in `focusedID` from when
        // the sticky appeared. Assigning that same ID while the title owns
        // first responder does not trigger a SwiftUI focus change, so clear
        // it first and restore it on the next run-loop turn. Arm the caret
        // immediately before that restoration so an outgoing title
        // selection notification cannot consume it.
        focusItem(targetID, atUTF16Offset: 0)
    }

    /// Backspace at column zero joins an item to its preceding text block.
    /// The first row joins the title; every other row joins the prior item.
    private func mergeBackward(_ item: TodoItem) {
        let visible = displayedItems
        guard let visibleIndex = visible.firstIndex(where: { $0.id == item.id }) else { return }
        let itemText = bindingValue(item)

        if visibleIndex == 0 {
            let join = (model.title as NSString).length
            model.setTitle(model.title + itemText)
            model.delete(item.id)
            focusTitle(atUTF16Offset: join)
        } else {
            let previous = visible[visibleIndex - 1]
            let join = (previous.text as NSString).length
            model.setText(previous.id, previous.text + itemText)
            model.delete(item.id)
            focusItem(previous.id, atUTF16Offset: join)
        }
    }

    /// Forward Delete at the end of a row joins the next visible row into it.
    /// The current row keeps its identity and the caret stays at the join.
    private func mergeForward(_ id: UUID) {
        let visible = displayedItems
        guard let index = visible.firstIndex(where: { $0.id == id }),
              index + 1 < visible.count,
              let join = model.mergeItemForward(id, with: visible[index + 1].id)
        else { return }

        controller.restoreCaretInCurrentEditor(atUTF16Offset: join)
    }

    // MARK: - Task date assignment

    private func syncDateCommand(for itemID: UUID, text: String) {
        let caret = controller.currentCaretUTF16Offset() ?? (text as NSString).length
        guard focusedID == itemID, let command = TaskDateCommand.active(in: text, caretUTF16Offset: caret) else {
            if dateDraft?.itemID == itemID, TaskDateCommand.active(in: text, caretUTF16Offset: caret) == nil {
                closeDatePicker(restoreFocus: false)
            }
            return
        }

        if let parsedDate = TaskDateExpression.date(from: command.query) {
            DispatchQueue.main.async {
                guard let currentText = model.items.first(where: { $0.id == itemID })?.text,
                      TaskDateCommand.active(in: currentText, caretUTF16Offset: caret)?.query == command.query
                else { return }
                commitDate(parsedDate, includesTime: true, for: itemID)
            }
            return
        }

        highlightedDateSuggestion = 0
        if dateDraft?.itemID == itemID {
            dateDraft?.query = command.query
            dateDraft?.commandRange = NSRange(command.range, in: text)
        } else {
            let selected = model.items.first(where: { $0.id == itemID })?.dueDate
                ?? Date().roundedToNearestFiveMinutes()
            let commandRange = NSRange(command.range, in: text)
            presentDatePicker(
                TaskDateDraft(
                    itemID: itemID,
                    query: command.query,
                    selectedDate: selected,
                    commandRange: commandRange,
                    includesTime: false
                )
            )
            // Opening a suggestion surface is observational: it must not move
            // the insertion point away from the task. The time field becomes
            // editable only after an explicit click inside the popover.
            DispatchQueue.main.async {
                focusItem(itemID, atUTF16Offset: caret)
            }
        }
    }

    private func openDatePicker(for itemID: UUID, selectedDate: Date) {
        highlightedDateSuggestion = 0
        let includesTime = model.items.first(where: { $0.id == itemID })?.dateTokenHasTime ?? false
        presentDatePicker(TaskDateDraft(
            itemID: itemID,
            query: "",
            selectedDate: selectedDate,
            includesTime: includesTime
        ))
    }

    private func presentDatePicker(_ draft: TaskDateDraft) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dateDraft = draft
        }
    }

    private func datePopoverPresented(for itemID: UUID) -> Binding<Bool> {
        Binding(
            get: { dateDraft?.itemID == itemID },
            set: { presented in
                if !presented, dateDraft?.itemID == itemID {
                    closeDatePicker()
                }
            }
        )
    }

    private func dateDraftBinding(for itemID: UUID) -> Binding<TaskDateDraft> {
        Binding(
            get: {
                dateDraft ?? TaskDateDraft(
                    itemID: itemID,
                    query: "",
                    selectedDate: Date().roundedToNearestFiveMinutes()
                )
            },
            set: { updated in
                guard updated.itemID == itemID else { return }
                dateDraft = updated
            }
        )
    }

    private func handleDatePickerKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let draft = dateDraft, modifiers.isEmpty else { return false }
        let suggestions = TaskDateSuggestion.matching(draft.query)

        switch keyCode {
        case 53: // Escape
            closeDatePicker()
            return true
        case 125 where !suggestions.isEmpty: // Down
            highlightedDateSuggestion = min(highlightedDateSuggestion + 1, suggestions.count - 1)
            return true
        case 126 where !suggestions.isEmpty: // Up
            highlightedDateSuggestion = max(highlightedDateSuggestion - 1, 0)
            return true
        case 48: // Tab accepts the highlighted suggestion; otherwise it still indents.
            guard suggestions.indices.contains(highlightedDateSuggestion) else { return false }
            let suggestion = suggestions[highlightedDateSuggestion]
            commitDate(suggestion.date, includesTime: suggestion.includesTime, for: draft.itemID)
            return true
        case 36, 76: // Return / keypad Enter
            if suggestions.indices.contains(highlightedDateSuggestion) {
                let suggestion = suggestions[highlightedDateSuggestion]
                commitDate(suggestion.date, includesTime: suggestion.includesTime, for: draft.itemID)
            } else {
                commitDate(draft.selectedDate, includesTime: draft.includesTime, for: draft.itemID)
            }
            return true
        default:
            return false
        }
    }

    private func handleDateTokenKey(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        selection: NSRange
    ) -> Bool {
        guard let itemID = focusedID,
              let item = model.items.first(where: { $0.id == itemID }),
              let tokenRange = item.dueDateRange,
              let dateRange = item.dueDateDateRange
        else { return false }

        let segments = [dateRange, item.dueDateTimeRange].compactMap { $0 }
        let isLeft = keyCode == 123
        let isRight = keyCode == 124
        if modifiers.isEmpty, selection.length == 0, isLeft || isRight {
            if isLeft, let segment = segments.last(where: { NSMaxRange($0) == selection.location }) {
                controller.restoreCaretInCurrentEditor(atUTF16Offset: segment.location)
                return true
            }
            if isRight, let segment = segments.first(where: { $0.location == selection.location }) {
                controller.restoreCaretInCurrentEditor(atUTF16Offset: NSMaxRange(segment))
                return true
            }
        }

        // Shift-arrow selects one semantic unit at a time: date first, then
        // the optional time. Command-Shift-arrow remains the native line edit.
        if modifiers == .shift, isLeft || isRight {
            if selection.length == 0 {
                if isRight, let segment = segments.first(where: { $0.location == selection.location }) {
                    controller.restoreSelectionInCurrentEditor(segment)
                    return true
                }
                if isLeft, let segment = segments.last(where: { NSMaxRange($0) == selection.location }) {
                    controller.restoreSelectionInCurrentEditor(segment)
                    return true
                }
            } else if selection == dateRange, isRight, let timeRange = item.dueDateTimeRange {
                controller.restoreSelectionInCurrentEditor(NSUnionRange(dateRange, timeRange))
                return true
            } else if let timeRange = item.dueDateTimeRange, selection == timeRange, isLeft {
                controller.restoreSelectionInCurrentEditor(tokenRange)
                return true
            }
        }

        guard modifiers.isEmpty else { return false }
        let tokenEnd = NSMaxRange(tokenRange)

        let isBackwardDelete = keyCode == 51
        let isForwardDelete = keyCode == 117
        let selectionTouchesToken = selection.length > 0 && NSIntersectionRange(selection, tokenRange).length > 0
        let timeRange = item.dueDateTimeRange
        let deletesAtBoundary = selection.length == 0 && (
            (isBackwardDelete && selection.location == tokenEnd) ||
            (isForwardDelete && (
                selection.location == tokenRange.location || selection.location == timeRange?.location
            ))
        )
        guard (isBackwardDelete || isForwardDelete), selectionTouchesToken || deletesAtBoundary else {
            return false
        }

        let removesOnlyTime = timeRange.map { time in
            selection == time ||
            (selection.length == 0 && isBackwardDelete && selection.location == NSMaxRange(time)) ||
            (selection.length == 0 && isForwardDelete && selection.location == time.location)
        } ?? false

        if removesOnlyTime, let timeRange {
            let mutable = NSMutableString(string: item.text)
            mutable.deleteCharacters(in: timeRange)
            let dateText = (item.text as NSString).substring(with: dateRange)
            controller.setDateToken(
                itemID,
                text: mutable as String,
                dueDate: item.dueDate,
                tokenText: dateText,
                offset: dateRange.location,
                hasTime: false
            )
            focusItem(itemID, atUTF16Offset: timeRange.location)
            return true
        }

        let deletionRange: NSRange
        if selectionTouchesToken {
            let start = min(selection.location, tokenRange.location)
            let end = max(NSMaxRange(selection), tokenEnd)
            deletionRange = NSRange(location: start, length: end - start)
        } else {
            deletionRange = tokenRange
        }
        let mutable = NSMutableString(string: item.text)
        mutable.deleteCharacters(in: deletionRange)
        controller.setDateToken(
            itemID,
            text: mutable as String,
            dueDate: nil,
            tokenText: nil,
            offset: nil,
            hasTime: nil
        )
        dateDraft = nil
        focusItem(itemID, atUTF16Offset: deletionRange.location)
        return true
    }

    private func normalizeDateTokenSelection(_ selection: NSRange) -> NSRange? {
        guard selection.length > 0,
              let itemID = focusedID,
              let item = model.items.first(where: { $0.id == itemID }),
              let dateRange = item.dueDateDateRange
        else { return nil }

        var normalized = selection
        for segment in [dateRange, item.dueDateTimeRange].compactMap({ $0 }) {
            guard NSIntersectionRange(normalized, segment).length > 0 else { continue }
            normalized = NSUnionRange(normalized, segment)
        }
        return normalized == selection ? nil : normalized
    }

    private func commitDate(_ date: Date, includesTime: Bool, for itemID: UUID) {
        guard let item = model.items.first(where: { $0.id == itemID }) else { return }
        let tokenText = TaskDatePresentation.string(from: date, includesTime: includesTime)
        let sourceRange = dateDraft?.commandRange ?? item.dueDateRange
        let mutable = NSMutableString(string: item.text)
        let replacementRange: NSRange
        if let sourceRange, NSMaxRange(sourceRange) <= mutable.length {
            replacementRange = sourceRange
        } else {
            let separator = item.text.isEmpty || item.text.last?.isWhitespace == true ? "" : " "
            mutable.append(separator)
            replacementRange = NSRange(location: mutable.length, length: 0)
        }
        mutable.replaceCharacters(in: replacementRange, with: tokenText)
        controller.setDateToken(
            itemID,
            text: mutable as String,
            dueDate: date,
            tokenText: tokenText,
            offset: replacementRange.location,
            hasTime: includesTime
        )
        model.isDateTimeFieldEditing = false
        dateDraft = nil
        let caret = replacementRange.location + (tokenText as NSString).length
        focusItem(itemID, atUTF16Offset: caret)
    }

    private func clearDate(for itemID: UUID) {
        guard let item = model.items.first(where: { $0.id == itemID }) else { return }
        let mutable = NSMutableString(string: item.text)
        let range = item.dueDateRange ?? dateDraft?.commandRange
        if let range, NSMaxRange(range) <= mutable.length {
            mutable.deleteCharacters(in: range)
        }
        controller.setDateToken(
            itemID,
            text: mutable as String,
            dueDate: nil,
            tokenText: nil,
            offset: nil,
            hasTime: nil
        )
        model.isDateTimeFieldEditing = false
        dateDraft = nil
        focusItem(itemID, atUTF16Offset: min(range?.location ?? mutable.length, mutable.length))
    }

    private func closeDatePicker(restoreFocus: Bool = true) {
        let itemID = dateDraft?.itemID
        model.isDateTimeFieldEditing = false
        dateDraft = nil
        guard restoreFocus, let itemID,
              let text = model.items.first(where: { $0.id == itemID })?.text
        else { return }
        focusItem(itemID, atUTF16Offset: (text as NSString).length)
    }

    private func handleDash(_ item: TodoItem, _ value: String) {
        if value == "-" {
            model.setText(item.id, "")
            let newID = model.addItem(after: item)
            focusItem(newID, atUTF16Offset: 0)
        }
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func bindingValue(_ item: TodoItem) -> String {
        model.items.first { $0.id == item.id }?.text ?? ""
    }

    private func textBinding(_ item: TodoItem) -> Binding<String> {
        Binding(
            get: { model.items.first { $0.id == item.id }?.text ?? "" },
            set: { updateTaskText(item.id, to: $0) }
        )
    }

    private func updateTaskText(_ itemID: UUID, to newText: String) {
        guard let item = model.items.first(where: { $0.id == itemID }),
              let tokenRange = item.dueDateRange
        else {
            model.setText(itemID, newText)
            return
        }
        let old = item.text as NSString
        let new = newText as NSString
        var prefix = 0
        while prefix < min(old.length, new.length), old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        let delta = new.length - old.length
        if prefix <= tokenRange.location {
            model.setDateToken(
                itemID,
                text: newText,
                dueDate: item.dueDate,
                tokenText: item.dueDateText,
                offset: max(0, tokenRange.location + delta),
                hasTime: item.dueDateHasTime
            )
        } else {
            model.setDateToken(
                itemID,
                text: newText,
                dueDate: item.dueDate,
                tokenText: item.dueDateText,
                offset: tokenRange.location,
                hasTime: item.dueDateHasTime
            )
        }
    }

    /// The first blank row should look and behave like an invitation to
    /// type, rather than an invisible one-character click target.
    private func rowPrompt(_ item: TodoItem) -> Text? {
        guard item.id == displayedItems.first?.id,
              bindingValue(item).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return Text("Add a to-do…").foregroundStyle(color.ink.opacity(0.32))
    }

    private func inlineTaskText(_ item: TodoItem, dateRange: NSRange) -> Text {
        let dateColor = item.isDone ? color.inkSecondary.opacity(0.6) : color.ink.opacity(0.6)
        let nsText = item.text as NSString
        let prefix = Text(nsText.substring(to: dateRange.location))
            .foregroundColor(item.isDone ? color.inkSecondary : color.ink.opacity(0.8))
        let date = Text(nsText.substring(with: dateRange)).foregroundColor(dateColor)
        let suffix = Text(nsText.substring(from: NSMaxRange(dateRange)))
            .foregroundColor(item.isDone ? color.inkSecondary : color.ink.opacity(0.8))
        return prefix + date + suffix
    }

    private func bodyFont(_ size: CGFloat) -> Font {
        model.font.body(size)
    }

    private func bodyNSFont(_ size: CGFloat) -> NSFont {
        let pointSize = size + model.font.sizeAdjustment
        if model.font == .helvetica {
            return .systemFont(ofSize: pointSize)
        }
        return NSFont(name: model.font.fontName, size: pointSize)
            ?? .systemFont(ofSize: pointSize)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM dd, yyyy"
        return f
    }()
}
