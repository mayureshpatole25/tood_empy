import AppKit
import Observation
import SwiftUI

struct QuickCaptureDestination: Identifiable {
    let id: UUID
    let title: String
    let color: StickyColor
}

enum QuickCaptureMode {
    case capture
    case openSticky
}

@MainActor
@Observable
final class QuickCaptureModel {
    var mode: QuickCaptureMode = .capture
    var text = ""
    var selectedStickyID: UUID?
    var isCreatingSticky = false
    var newStickyTitle = ""
    var taskFocusRequest = 0
    var isStickyPaletteVisible = false
    var stickyQuery = ""
    var highlightedStickyIndex = 0
    private(set) var hashtagRange: NSRange?
    private var assignmentGeneration = UUID()

    func reset(stickies: [QuickCaptureDestination], preferredID: UUID?, mode: QuickCaptureMode) {
        self.mode = mode
        text = ""
        newStickyTitle = ""
        isCreatingSticky = mode == .capture && stickies.isEmpty
        isStickyPaletteVisible = mode == .openSticky
        stickyQuery = ""
        highlightedStickyIndex = 0
        hashtagRange = nil
        selectedStickyID = preferredID.flatMap { preferred in
            stickies.contains(where: { $0.id == preferred }) ? preferred : nil
        } ?? stickies.first?.id
    }

    func requestTaskFocus() { taskFocusRequest += 1 }

    func showAllStickies() {
        guard !isCreatingSticky else { return }
        assignmentGeneration = UUID()
        hashtagRange = nil
        stickyQuery = ""
        highlightedStickyIndex = 0
        isStickyPaletteVisible = true
    }

    func syncHashtagCommand() {
        guard !isCreatingSticky else { return }
        let string = text as NSString
        let wholeRange = NSRange(location: 0, length: string.length)
        let expression = try? NSRegularExpression(pattern: #"(?:^|\s)#([^\s#]*)$"#)
        guard let match = expression?.firstMatch(in: text, range: wholeRange),
              match.numberOfRanges == 2 else {
            if hashtagRange != nil { hideStickyPalette() }
            return
        }

        let fullRange = match.range(at: 0)
        let queryRange = match.range(at: 1)
        // Keep a preceding space in the task; remove only the # command.
        let hashLocation = fullRange.location + fullRange.length - queryRange.length - 1
        hashtagRange = NSRange(location: hashLocation, length: queryRange.length + 1)
        stickyQuery = string.substring(with: queryRange)
        highlightedStickyIndex = 0
        isStickyPaletteVisible = true
    }

    func filteredStickies(from stickies: [QuickCaptureDestination]) -> [QuickCaptureDestination] {
        let query = stickyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return stickies }
        return stickies.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    func moveHighlight(by offset: Int, in stickies: [QuickCaptureDestination]) {
        let matches = filteredStickies(from: stickies)
        guard !matches.isEmpty else { return }
        highlightedStickyIndex = (highlightedStickyIndex + offset + matches.count) % matches.count
    }

    func chooseHighlighted(from stickies: [QuickCaptureDestination]) -> Bool {
        guard let sticky = highlightedSticky(from: stickies) else { return false }
        chooseSticky(sticky.id)
        return true
    }

    func highlightedSticky(from stickies: [QuickCaptureDestination]) -> QuickCaptureDestination? {
        let matches = filteredStickies(from: stickies)
        guard matches.indices.contains(highlightedStickyIndex) else { return nil }
        return matches[highlightedStickyIndex]
    }

    func chooseSticky(_ id: UUID) {
        let generation = UUID()
        assignmentGeneration = generation
        selectedStickyID = id
        if let hashtagRange,
           let range = Range(NSRange(location: hashtagRange.location, length: 1), in: text) {
            // The # invokes assignment but the words the user typed remain
            // their task text. Removing anything else causes the caret and
            // sentence to jump at the moment of confirmation.
            text.removeSubrange(range)
        }
        hashtagRange = nil

        // Let the assignment chip begin its swap first; collapse the menu a
        // beat later so the two state changes don't land on the same frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.assignmentGeneration == generation else { return }
            self.hideStickyPalette()
            self.requestTaskFocus()
        }
    }

    func hideStickyPalette() {
        isStickyPaletteVisible = false
        stickyQuery = ""
        highlightedStickyIndex = 0
        hashtagRange = nil
    }
}

/// A non-activating Spotlight-style panel. It can become key for text input
/// without bringing Tood's other windows forward or stealing the current
/// application's place in the app switcher.
private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickCaptureController: NSWindowController {
    private static let compactSize = NSSize(width: 560, height: 126)
    private static let expandedHeight: CGFloat = 328
    private static let pickerOnlyHeight: CGFloat = 256
    private let manager: StickyManager
    private let capture = QuickCaptureModel()
    private let lastStickyKey = "today.quickCaptureLastStickyID"
    private var keyMonitor: Any?

    init(manager: StickyManager) {
        self.manager = manager

        let size = Self.compactSize
        let panel = QuickCapturePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true

        super.init(window: panel)

        let view = QuickCaptureView(
            model: capture,
            stickies: { manager.quickCaptureDestinations() },
            onSubmit: { [weak self] in self?.submit() },
            onDismiss: { [weak self] in self?.dismiss() },
            onChooseSticky: { [weak self] id in self?.chooseSticky(id) },
            onCreateSticky: { [weak self] title in self?.createAndOpenSticky(named: title) },
            onPaletteVisibilityChange: { [weak self] visible in
                self?.setPaletteVisible(visible)
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.keyCode == 53 {
                if self.capture.isStickyPaletteVisible, self.capture.mode == .capture {
                    self.capture.hideStickyPalette()
                    return nil
                }
                self.dismiss()
                return nil
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if self.capture.mode == .capture,
               modifiers.contains(.command),
               event.keyCode == 36 || event.keyCode == 76 {
                self.submit(openDestination: true)
                return nil
            }
            if self.capture.isStickyPaletteVisible {
                if event.keyCode == 125 {
                    self.capture.moveHighlight(by: 1, in: self.manager.quickCaptureDestinations())
                    return nil
                }
                if event.keyCode == 126 {
                    self.capture.moveHighlight(by: -1, in: self.manager.quickCaptureDestinations())
                    return nil
                }
                if event.keyCode == 48 || event.keyCode == 36 || event.keyCode == 76 {
                    let stickies = self.manager.quickCaptureDestinations()
                    if self.capture.mode == .openSticky {
                        if let sticky = self.capture.highlightedSticky(from: stickies) {
                            self.openSticky(sticky.id)
                            return nil
                        }
                        if self.createAndOpenSticky(named: self.capture.stickyQuery) {
                            return nil
                        }
                    } else if self.capture.chooseHighlighted(from: stickies) {
                        return nil
                    }
                }
            } else if event.keyCode == 48, !self.capture.isCreatingSticky {
                self.capture.showAllStickies()
                return nil
            }
            return event
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func present(mode: QuickCaptureMode = .capture) {
        let stickies = manager.quickCaptureDestinations()
        let preferredID = UserDefaults.standard
            .string(forKey: lastStickyKey)
            .flatMap(UUID.init(uuidString:))
        capture.reset(stickies: stickies, preferredID: preferredID, mode: mode)

        guard let panel = window else { return }
        panel.setContentSize(NSSize(
            width: Self.compactSize.width,
            height: mode == .openSticky ? Self.pickerOnlyHeight : Self.compactSize.height
        ))
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen {
            var frame = panel.frame
            frame.origin.x = screen.visibleFrame.midX - frame.width / 2
            frame.origin.y = screen.visibleFrame.midY - frame.height / 2 + 80
            panel.setFrame(frame, display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            self?.capture.requestTaskFocus()
        }
    }

    private func submit(openDestination: Bool = false) {
        let id = manager.captureItem(
            capture.text,
            in: capture.isCreatingSticky ? nil : capture.selectedStickyID,
            newStickyTitle: capture.isCreatingSticky ? capture.newStickyTitle : nil
        )
        guard let id else { return }
        UserDefaults.standard.set(id.uuidString, forKey: lastStickyKey)
        NSSound(named: "Tink")?.play()
        dismiss()
        if openDestination { manager.bringToFront(id) }
    }

    private func chooseSticky(_ id: UUID) {
        if capture.mode == .openSticky {
            openSticky(id)
        } else {
            capture.chooseSticky(id)
        }
    }

    private func openSticky(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: lastStickyKey)
        dismiss()
        manager.bringToFront(id)
    }

    @discardableResult
    private func createAndOpenSticky(named title: String) -> Bool {
        guard let id = manager.createNamedSticky(title) else { return false }
        openSticky(id)
        return true
    }

    private func dismiss() {
        capture.hideStickyPalette()
        window?.orderOut(nil)
    }

    private func setPaletteVisible(_ visible: Bool) {
        guard let panel = window else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = capture.mode == .openSticky
            ? Self.pickerOnlyHeight
            : (visible ? Self.expandedHeight : Self.compactSize.height)
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: true)
    }
}

private struct QuickCaptureView: View {
    @Bindable var model: QuickCaptureModel
    let stickies: () -> [QuickCaptureDestination]
    let onSubmit: () -> Void
    let onDismiss: () -> Void
    let onChooseSticky: (UUID) -> Void
    let onCreateSticky: (String) -> Void
    let onPaletteVisibilityChange: (Bool) -> Void

    @FocusState private var field: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var baseStickyColor: StickyColor?
    @State private var revealStickyColor: StickyColor?
    @State private var revealProgress: CGFloat = 0.02
    @State private var revealCorner = RevealCorner.topLeading
    @State private var revealGeneration = UUID()

    private enum Field { case task, newSticky, stickySearch }

    var body: some View {
        Group {
            if model.mode == .openSticky {
                openStickyContent
            } else {
                captureContent
            }
        }
        .background(
            spotlightBackground
        )
        .padding(1)
        .onChange(of: model.taskFocusRequest) { _, _ in
            DispatchQueue.main.async {
                field = model.mode == .openSticky ? .stickySearch : .task
            }
        }
        .onChange(of: model.isStickyPaletteVisible) { _, visible in
            onPaletteVisibilityChange(visible)
        }
        .onChange(of: model.selectedStickyID) { oldID, newID in
            guard oldID != newID, let color = color(for: newID) else { return }
            revealAssignment(color)
        }
        .onAppear {
            baseStickyColor = color(for: model.selectedStickyID)
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private var openStickyContent: some View {
        VStack(spacing: 0) {
            TextField("Open or create a sticky…", text: $model.stickyQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .focused($field, equals: .stickySearch)
                .padding(.horizontal, 20)
                .frame(height: 53)
                .onChange(of: model.stickyQuery) { _, _ in
                    model.highlightedStickyIndex = 0
                }

            Rectangle()
                .fill(.black.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 18)

            stickyPalette
        }
    }

    private var captureContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                TextField("What do you need to remember?", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .regular, design: .rounded))
                    .focused($field, equals: .task)
                    .onSubmit(onSubmit)
                    .onChange(of: model.text) { _, _ in model.syncHashtagCommand() }
            }
            .padding(.horizontal, 22)
            .frame(height: 72)

            Rectangle()
                .fill(.black.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 18)

            if model.isStickyPaletteVisible {
                stickyPalette

                Rectangle()
                    .fill(.black.opacity(0.10))
                    .frame(height: 1)
                    .padding(.horizontal, 18)
            }

            HStack(spacing: 10) {
                if model.isCreatingSticky {
                    TextField("Name the new sticky", text: $model.newStickyTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($field, equals: .newSticky)
                        .onSubmit(onSubmit)

                    Button("Cancel") {
                        model.isCreatingSticky = false
                        model.selectedStickyID = stickies().first?.id
                        field = .task
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        model.showAllStickies()
                    } label: {
                        AssignmentChipLabel(title: selectedTitle, reduceMotion: reduceMotion)
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.black.opacity(0.065))
                            )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }

                Spacer()

                Text("↵  Add")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(canSubmit ? 0.56 : 0.24))
                    .frame(height: 28)
            }
            .padding(.horizontal, 22)
            .frame(height: 51)
        }
    }

    private var spotlightBackground: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.98, green: 0.96, blue: 0.91))

                if let baseStickyColor {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(baseStickyColor.paper.opacity(0.22))
                }

                if let revealStickyColor {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(revealStickyColor.paper.opacity(0.22))
                        .mask(
                            assignmentRevealMask(
                                size: proxy.size,
                                corner: revealCorner,
                                progress: revealProgress
                            )
                        )
                }

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.black.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func assignmentRevealMask(
        size: CGSize,
        corner: RevealCorner,
        progress: CGFloat
    ) -> some View {
        let diameter = hypot(size.width, size.height) * 2
        return Circle()
            .fill(.white)
            .frame(width: diameter, height: diameter)
            .blur(radius: reduceMotion ? 0 : 16)
            .scaleEffect(reduceMotion ? 1 : progress)
            .position(corner.position(in: size))
            .opacity(reduceMotion ? progress : 1)
    }

    private func revealAssignment(_ color: StickyColor) {
        let generation = UUID()
        revealGeneration = generation
        revealStickyColor = color
        revealCorner = .topLeading
        revealProgress = reduceMotion ? 0 : 0.02

        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: reduceMotion ? 0.2 : 1.2)) {
                revealProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 1.2)) {
            guard revealGeneration == generation else { return }
            baseStickyColor = color
            revealStickyColor = nil
        }
    }

    private func color(for id: UUID?) -> StickyColor? {
        stickies().first(where: { $0.id == id })?.color
    }


    private var stickyPalette: some View {
        let matches = model.filteredStickies(from: stickies())
        return VStack(alignment: .leading, spacing: 0) {
            Text(model.mode == .openSticky ? "Open sticky" : "Assigned to")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.black.opacity(0.42))
                .padding(.horizontal, 20)
                .padding(.top, 11)
                .padding(.bottom, 5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        if matches.isEmpty {
                            if model.mode == .openSticky,
                               !model.stickyQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    onCreateSticky(model.stickyQuery)
                                } label: {
                                    Text("Create “\(model.stickyQuery.trimmingCharacters(in: .whitespacesAndNewlines))”")
                                        .lineLimit(1)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(.black.opacity(0.76))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .frame(height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(.black.opacity(0.075))
                                        )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("No matching stickies")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                        } else {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, sticky in
                                Button {
                                    onChooseSticky(sticky.id)
                                } label: {
                                    HStack {
                                        Text(sticky.title)
                                            .lineLimit(1)
                                        Spacer()
                                        if model.mode == .capture, sticky.id == model.selectedStickyID {
                                            Text("Assigned")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.system(size: 13.5, weight: index == model.highlightedStickyIndex ? .semibold : .regular))
                                    .foregroundStyle(.black.opacity(0.76))
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(index == model.highlightedStickyIndex ? .black.opacity(0.075) : .clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(sticky.id)
                            }
                        }

                        if model.mode == .capture {
                            Button("Create new sticky…") {
                                model.hideStickyPalette()
                                model.isCreatingSticky = true
                                DispatchQueue.main.async { field = .newSticky }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.black.opacity(0.52))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: model.highlightedStickyIndex) { _, index in
                    guard matches.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(matches[index].id, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 201)
    }

    private var selectedTitle: String {
        stickies().first(where: { $0.id == model.selectedStickyID })?.title ?? "Choose sticky"
    }

    private var canSubmit: Bool {
        !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!model.isCreatingSticky
                || !model.newStickyTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private struct AssignmentChipLabel: View {
    let title: String
    let reduceMotion: Bool

    @State private var visibleTitle = ""
    @State private var outgoingTitle: String?
    @State private var swapComplete = true
    @State private var swapGeneration = UUID()

    var body: some View {
        ZStack {
            // The current value owns the capsule's intrinsic width while both
            // copies move inside a clipped one-line viewport.
            Text(title).hidden()

            if let outgoingTitle {
                Text(outgoingTitle)
                    .offset(y: reduceMotion ? 0 : (swapComplete ? -12 : 0))
                    .opacity(swapComplete ? 0 : 1)
            }

            Text(visibleTitle)
                .offset(y: reduceMotion ? 0 : (swapComplete ? 0 : 12))
                .opacity(swapComplete ? 1 : 0)
        }
        .lineLimit(1)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.black.opacity(0.68))
        .frame(height: 15)
        .clipped()
        .onAppear { visibleTitle = title }
        .onChange(of: title) { _, newTitle in
            let generation = UUID()
            swapGeneration = generation
            outgoingTitle = visibleTitle
            visibleTitle = newTitle
            swapComplete = false

            DispatchQueue.main.async {
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: reduceMotion ? 0.12 : 0.2)) {
                    swapComplete = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.12 : 0.2)) {
                guard swapGeneration == generation else { return }
                outgoingTitle = nil
            }
        }
    }
}

private enum RevealCorner {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    func position(in size: CGSize) -> CGPoint {
        switch self {
        case .topLeading: return CGPoint(x: 0, y: 0)
        case .topTrailing: return CGPoint(x: size.width, y: 0)
        case .bottomLeading: return CGPoint(x: 0, y: size.height)
        case .bottomTrailing: return CGPoint(x: size.width, y: size.height)
        }
    }
}
