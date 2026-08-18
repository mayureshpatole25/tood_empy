import SwiftUI

/// Shared sizing so the fan layout math and the card itself never drift
/// apart. Narrower/taller than the first pass — closer to the real
/// floating sticky's portrait proportions (378×490-ish) instead of the
/// landscape-ish 200×178 it started as. Not private — ArchivedStickiesView
/// reuses these same numbers so its grid of mini stickies matches exactly.
enum DeskCardMetrics {
    static let width: CGFloat = 178
    static let height: CGFloat = 200
    static let cornerRadius: CGFloat = 5
}

/// The Home screen: greeting up top, today's completion ring opposite it,
/// the intentionally messy sticky fan bottom-left, and a direct new-list
/// action bottom-right. No chrome at all — settings lives in the status-bar
/// menu set up during onboarding.
///
/// Reads directly off `StickyManager`/`JournalStore` (the same source of
/// truth the floating stickies and journal itself use), so it updates live.
struct HomeView: View {
    let manager: StickyManager
    let journal: JournalStore

    @State private var locationLabel: String?
    @State private var showingArchive = false

    private let desk = Color(hex: 0xFBF8F1)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // These two paint the full window, including behind the
            // (hidden) title bar. Without ignoresSafeArea they stop short
            // of that region and the window's own white backing shows
            // through as a strip across the top.
            desk.ignoresSafeArea()
            PaperDotsBackground().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                announcementBanner
                topRow
                Spacer(minLength: 24)
                bottomRow
            }
            .animation(.easeInOut(duration: 0.25), value: AnnouncementService.shared.current)
            .padding(.horizontal, 44)
            .padding(.top, 30)
            .padding(.bottom, 44)

            // Floats independently of the fan/pill column below so the
            // primary creation action always stays in the same corner.
            newToDoListButton
                .padding(.horizontal, 44)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // Same floating treatment, opposite corner.
            archiveButton
                .padding(.horizontal, 44)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(minWidth: 820, minHeight: 600)
        .sheet(isPresented: $showingArchive) {
            ArchivedStickiesView(manager: manager, onDone: { showingArchive = false })
        }
        .onAppear {
            LocationStamper.shared.requestLabel { locationLabel = $0 }
        }
    }

    // MARK: - Announcement banner (see AnnouncementService)

    @ViewBuilder
    private var announcementBanner: some View {
        if let announcement = AnnouncementService.shared.current {
            HStack(spacing: 12) {
                Text(announcement.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x20211E))
                    .fixedSize(horizontal: false, vertical: true)
                if let urlString = announcement.url, let url = URL(string: urlString) {
                    Link(announcement.linkLabel ?? "Learn more", destination: url)
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer(minLength: 12)
                Button { AnnouncementService.shared.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0x94F48F).opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.bottom, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Top: greeting (+ quiet location) and daily progress

    private var topRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(.system(size: 40, weight: .medium))
                Text(dateLine)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            dailyProgressRing
        }
    }

    private var completedCount: Int { manager.tasksCompletedToday }
    private var totalTaskCount: Int { completedCount + manager.unfinishedTaskCount }
    private var completionProgress: Double {
        guard totalTaskCount > 0 else { return 0 }
        return min(1, Double(completedCount) / Double(totalTaskCount))
    }

    /// The full track is the day's total workload; the green arc is the
    /// completed share. The numbers remain explicit so progress is never
    /// communicated by color alone.
    private var dailyProgressRing: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: 0x20211E).opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: completionProgress)
                .stroke(
                    Color(hex: 0x17C862),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text("\(completedCount)")
                    .font(.custom("HelveticaNeue-Medium", size: 22))
                Text("of \(totalTaskCount)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 82, height: 82)
        .animation(.easeInOut(duration: 0.25), value: completionProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedCount) of \(totalTaskCount) to-do items done")
    }

    /// Quiet, always-there — finished stickies you archived (instead of
    /// deleted) from the close confirmation live here. Floats in the
    /// bottom-left corner, mirroring the journal button's bottom-right spot.
    private var archiveButton: some View {
        Button { showingArchive = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                Text("Archive")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : (hour < 18 ? "afternoon" : "evening")
        return "Good \(part), \(Self.firstName)."
    }

    /// "Friday, July 31 · Noe Valley" — quiet, only appears once Location
    /// Services actually resolves something (never blocks or shows an error).
    private var dateLine: String {
        let date = Self.dateFormatter.string(from: Date())
        guard let locationLabel else { return date }
        return "\(date) · \(locationLabel)"
    }

    private static var firstName: String {
        let override = AppSettings.shared.userName
        if !override.isEmpty { return override }
        let full = NSFullUserName()
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    // MARK: - Bottom: stickies, then the focus pill centered underneath
    // (the new-list button floats independently, see `body`)

    private var bottomRow: some View {
        VStack(spacing: 14) {
            stickiesFan
            FocusSoundControl()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// No scroll view, no clipping, no fade — the fan just gets denser as
    /// more stickies are added (see `fanPositions`), always fitting the
    /// available width instead of needing to scroll past an edge. That also
    /// means shadows render in full; nothing's there to cut them off.
    private var stickiesFan: some View {
        Group {
            if manager.order.isEmpty {
                emptyStickyState
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        let count = manager.order.count
                        let positions = fanPositions(count: count, availableWidth: proxy.size.width)
                        ForEach(Array(manager.order.enumerated()), id: \.element) { index, id in
                            if let controller = manager.controllers[id] {
                                StickyDeskCard(model: controller.model) { manager.bringToFront(id) }
                                    .rotationEffect(.degrees(rotation(for: index)))
                                    .offset(x: positions[index], y: verticalOffset(for: index))
                                    .zIndex(Double(index))
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: DeskCardMetrics.height + 45) // card height + rotation/hover/shadow headroom
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: manager.order)
    }

    /// Zero stickies — a real sticky (same paper/title look as
    /// `StickyDeskCard`, in whatever the default color is), not a generic
    /// dashed placeholder, with its own invitation to create the first one.
    private var emptyStickyState: some View {
        let color = StickyColor.defaultColor ?? .pink
        return Button { manager.newSticky() } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("To Do")
                    .font(.custom("HelveticaNeue", size: 17))
                    .foregroundStyle(color.titleInk)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(color.ink.opacity(0.6))
                    Text("Create your first")
                        .font(.system(size: 12.5))
                        .foregroundStyle(color.ink.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(width: DeskCardMetrics.width, height: DeskCardMetrics.height, alignment: .topLeading)
            .background(color.paper, in: RoundedRectangle(cornerRadius: DeskCardMetrics.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 13, y: 8)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Left-to-right x offsets for each card. Starts at a comfortable,
    /// mostly-unoverlapped spacing and each gap decays geometrically — fanned
    /// out on the left, progressively closer/"stuck together" toward the
    /// right. If that natural sequence would still run past the available
    /// width (many stickies), the whole sequence is scaled down uniformly so
    /// everything fits — cards compress into a tighter stack rather than
    /// ever needing to scroll.
    private func fanPositions(count: Int, availableWidth: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let cardWidth = DeskCardMetrics.width
        let baseStep: CGFloat = 105
        let decay: CGFloat = 0.8

        let deltas: [CGFloat] = (0..<(count - 1)).map { i in
            baseStep * CGFloat(pow(Double(decay), Double(i)))
        }
        let rawSpan = deltas.reduce(0, +)
        let maxSpan = max(0, availableWidth - cardWidth)
        let scale = (rawSpan > maxSpan && rawSpan > 0) ? maxSpan / rawSpan : 1

        var positions: [CGFloat] = [0]
        var x: CGFloat = 0
        for delta in deltas {
            x += delta * scale
            positions.append(x)
        }
        return positions
    }

    private func rotation(for index: Int) -> Double {
        [-3, 1.5, -1.5, 2.5, -2][index % 5]
    }

    private func verticalOffset(for index: Int) -> Double {
        [8, 16, 4, 12, 6][index % 5] // modest stagger
    }

    private var newToDoListButton: some View {
        Button { manager.newSticky() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("New To Do List")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(desk)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(Color(hex: 0x20211E), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .help("Create a new to-do list")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}

/// One sticky on the desk — same paper color/type as the real sticky, sized
/// up to be the clear focal point, with a hover hint that appears when
/// hovering its corner specifically (not the whole card). Defaults to "Pop
/// out", foreshadowing the floating window it becomes when clicked — but
/// ArchivedStickiesView reuses this exact card for its grid of memories,
/// where clicking opens a read-only viewer instead, hence the override.
struct StickyDeskCard: View {
    let model: StickyModel
    var hoverHint: String = "Pop out"
    var onShow: () -> Void

    @State private var hovering = false
    @State private var hoveringCorner = false

    var body: some View {
        Button(action: onShow) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.title.isEmpty ? "To Do" : model.title)
                        .font(.custom("HelveticaNeue", size: 17))
                        .foregroundStyle(model.color.titleInk)
                        .lineLimit(1)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.items.prefix(3)) { item in
                            HStack(spacing: 8) {
                                // Same shape/values as the real sticky's checkbox
                                // (StickyRootView.checkbox), just not interactive here.
                                ZStack {
                                    if item.isDone {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(model.color.ink.opacity(0.3))
                                            .frame(width: 11, height: 11)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(model.color.paper)
                                    } else {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .stroke(model.color.ink.opacity(0.3), lineWidth: 1.1)
                                            .frame(width: 11, height: 11)
                                    }
                                }
                                .frame(width: 11, height: 11)
                                Text(item.text.isEmpty ? " " : item.text)
                                    .font(model.font.body(12.5))
                                    .foregroundStyle(item.isDone ? model.color.inkSecondary : model.color.ink.opacity(0.8))
                                    .strikethrough(item.isDone, color: model.color.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(width: DeskCardMetrics.width, height: DeskCardMetrics.height, alignment: .topLeading)
                .background(model.color.paper, in: RoundedRectangle(cornerRadius: DeskCardMetrics.cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(hovering ? 0.28 : 0.2), radius: hovering ? 20 : 13, y: hovering ? 12 : 8)
                .scaleEffect(hovering ? 1.02 : 1)
                .offset(y: hovering ? -9 : 0)

                if hoveringCorner {
                    Text(hoverHint)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.8), in: Capsule())
                        .foregroundStyle(.white)
                        .offset(x: -10, y: 10)
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(alignment: .topTrailing) {
            // A dedicated hover target just for the corner, matching the
            // request that "Pop out" only appears there, not the whole card.
            Color.clear
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .onHover { hoveringCorner = $0 }
                .offset(y: hovering ? -9 : 0)
        }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}
