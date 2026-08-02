import SwiftUI

/// First-run only. Reuses the exact same defaults `SettingsView` edits later
/// (same `StickyColor`/`StickyFont` statics, same `AppSettings` shortcuts) —
/// onboarding just front-loads the choices, it isn't a separate settings
/// store.
struct OnboardingView: View {
    let manager: StickyManager
    @Bindable var settings: AppSettings
    var onFinish: () -> Void
    /// Steps back past this wizard's first step (color) to the falling-
    /// stickies intro page it followed from.
    var onExitToIntro: () -> Void

    @State private var step = 0
    @State private var color: StickyColor? = StickyColor.defaultColor
    @State private var font: StickyFont = StickyFont.defaultFont
    @State private var previewSticky: StickyModel?
    @State private var connectingCalendar = false
    @FocusState private var itemFieldFocused: Bool

    private let auth = GoogleAuthService.shared

    // "Welcome" no longer lives here — `IntroFallView` (the falling-stickies
    // page shown right before this) already carries that greeting, so this
    // wizard starts straight at the first real choice instead of repeating it.
    private let steps = ["Color", "Font", "Sticky", "Shortcuts", "Calendar"]

    /// Same cream desk + dotted paper texture as `IntroFallView`, and the
    /// same 640×520 window size — the wizard should feel like the next page
    /// of the same moment, not a jump to a different, smaller app window.
    private let desk = Color(hex: 0xFBF8F1)

    /// Orange instead of the app's usual coral accent (`AccentColor` in
    /// Assets) — just for this wizard, since it reads as more distinct.
    /// Applied directly (not just `.tint`, which only affects real controls
    /// like buttons — a plain `Color.accentColor.fill()` ignores `.tint`
    /// entirely and reads the shared asset regardless, which is why the
    /// progress dots stayed coral even after the button went orange).
    private let accent = StickyColor.orange.paper

    var body: some View {
        ZStack {
            desk.ignoresSafeArea()
            PaperDotsBackground().ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 0)
                Group {
                    switch step {
                    case 0: colorStep
                    case 1: fontStep
                    case 2: stickyStep
                    case 3: shortcutStep
                    default: calendarStep
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                navigation
            }
            .padding(40)
        }
        .frame(width: 640, height: 520)
        .tint(accent)
    }

    private var colorStep: some View {
        VStack(spacing: 20) {
            stepHeading("Pick a default color", "You can always change an individual sticky's color later.")
            HStack(spacing: 14) {
                swatchButton(nil, label: "Random")
                ForEach(StickyColor.allCases) { c in
                    swatchButton(c, label: c.displayName)
                }
            }
        }
    }

    private func swatchButton(_ c: StickyColor?, label: String) -> some View {
        Button { color = c } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(c.map { AnyShapeStyle($0.paper) }
                        ?? AnyShapeStyle(.conicGradient(colors: StickyColor.allCases.map(\.paper), center: .center)))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(.primary, lineWidth: color == c ? 2 : 0).padding(-3))
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var fontStep: some View {
        VStack(spacing: 20) {
            stepHeading("Pick a default font", "For your checklist text — the big title always stays Helvetica Neue.")
            HStack(spacing: 14) {
                ForEach(StickyFont.allCases) { f in
                    Button { font = f } label: {
                        VStack(spacing: 8) {
                            Text("Aa")
                                .font(.custom(f == .helvetica ? "HelveticaNeue" : f.fontName, size: 22))
                            Text(f.displayName).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(width: 90)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(font == f ? accent.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The reveal: the sticky they just styled, live, with a field for their
    /// first real to-do. Typing here edits the actual sticky already sitting
    /// on the desktop (created up front in `restoreAll()` for a true first
    /// run) — same object, so it appears on screen and in the Home fan as
    /// they type, rather than a fake mockup they'll never see again.
    private var stickyStep: some View {
        VStack(spacing: 20) {
            stepHeading("Add your first to-do", "It's already sitting on your desktop — try typing something.")
            if let sticky = previewSticky {
                previewStickyCard(sticky)
            }
        }
        .onAppear {
            if manager.order.isEmpty { manager.newSticky() }
            guard let id = manager.order.first else { return }
            let model = manager.controllers[id]?.model
            model?.setColor(color ?? .pink)
            model?.setFont(font)
            manager.controllers[id]?.bringToFront()
            previewSticky = model
            itemFieldFocused = true
        }
    }

    private func previewStickyCard(_ sticky: StickyModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("To Do")
                .font(.custom("HelveticaNeue", size: 22))
                .foregroundStyle(sticky.color.titleInk)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(sticky.color.ink.opacity(0.3), lineWidth: 1.1)
                    .frame(width: 13, height: 13)
                TextField("e.g. Buy groceries", text: firstItemBinding(sticky))
                    .textFieldStyle(.plain)
                    .font(sticky.font.body(14))
                    .foregroundStyle(sticky.color.ink.opacity(0.8))
                    .focused($itemFieldFocused)
            }
        }
        .padding(20)
        .frame(width: 300, height: 130, alignment: .topLeading)
        .background(sticky.color.paper, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
    }

    private func firstItemBinding(_ sticky: StickyModel) -> Binding<String> {
        Binding(
            get: { sticky.items.first?.text ?? "" },
            set: { newValue in
                if let id = sticky.items.first?.id {
                    sticky.setText(id, newValue)
                } else {
                    sticky.addItem()
                    if let id = sticky.items.first?.id { sticky.setText(id, newValue) }
                }
            }
        )
    }

    private var shortcutStep: some View {
        VStack(spacing: 20) {
            stepHeading("Set your shortcuts", "Global — these work from anywhere, even while another app is active.")
            VStack(spacing: 12) {
                HStack {
                    Text("Show Active Sticky").frame(width: 160, alignment: .leading)
                    ShortcutRecorderField(combo: $settings.showStickyShortcut)
                }
                HStack {
                    Text("New Sticky").frame(width: 160, alignment: .leading)
                    ShortcutRecorderField(combo: $settings.newStickyShortcut)
                }
            }
        }
    }

    /// Last step, and optional — skippable via "Get Started" same as any
    /// other step. Reuses `GoogleAuthService` directly (same connect flow
    /// as Settings), so finishing this step here or later from Settings
    /// leaves the app in the same state either way.
    private var calendarStep: some View {
        VStack(spacing: 20) {
            stepHeading("Connect your calendar", "See today's events on your Home screen, right next to your stickies.")
            if auth.isConnected {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green)
                    Text(auth.connectedEmail ?? "Connected")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(connectingCalendar ? "Connecting…" : "Connect Google Calendar") {
                    connectCalendar()
                }
                .buttonStyle(.borderedProminent)
                .disabled(connectingCalendar)
                Text("Optional — you can always connect later from Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func connectCalendar() {
        connectingCalendar = true
        Task {
            defer { connectingCalendar = false }
            try? await auth.connect()
        }
    }

    private func stepHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var navigation: some View {
        HStack {
            ForEach(steps.indices, id: \.self) { i in
                Circle()
                    .fill(i == step ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
            Spacer()
            Button("Back") {
                if step > 0 { step -= 1 } else { onExitToIntro() }
            }
            Button(step == steps.count - 1 ? "Get Started" : "Continue") {
                if step == steps.count - 1 {
                    finish()
                } else {
                    step += 1
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func finish() {
        StickyColor.defaultColor = color
        StickyFont.defaultFont = font
        GlobalHotKeyManager.shared.reregister()
        settings.onboardingCompleted = true
        onFinish()
    }
}
