import SwiftUI

/// Every persisted preference in one place — the default-color/font/position
/// pickers reuse the exact same `StickyColor`/`StickyFont`/`StickyCorner`
/// statics the status-bar menu already reads and writes, so changing them
/// here or from the menu stays in sync automatically (same UserDefaults keys).
///
/// Color and font use a custom button + popover rather than a native
/// `Picker` — macOS's `Picker` renders its *collapsed* selection through
/// AppKit's `NSPopUpButton`, which silently drops custom `.foregroundStyle`/
/// `.font` on the selected item (that's why the color swatch showed up
/// black and every font option rendered in the system font). A plain
/// SwiftUI popover doesn't go through that conversion, so it just works —
/// same pattern the sticky's own color/font pickers already use.
struct SettingsView: View {
    @State private var color: StickyColor? = StickyColor.defaultColor
    @State private var font: StickyFont = StickyFont.defaultFont
    @State private var corner: StickyCorner = StickyCorner.startCorner
    @State private var showColorPicker = false
    @State private var showFontPicker = false
    @State private var connectingCalendar = false
    @State private var paywallPack: ColorPack?
    @Bindable var settings: AppSettings
    private var packStore: ColorPackStore { ColorPackStore.shared }

    private let auth = GoogleAuthService.shared

    var body: some View {
        Form {
            Section("General") {
                TextField("Your Name", text: $settings.userName, prompt: Text(placeholderName))
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            Section("Journal") {
                TextField("Prompt", text: $settings.journalPrompt)
                Toggle("Stamp entries with your location", isOn: $settings.journalLocationEnabled)
                Text("Journal entries are stored locally only, never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calendar") {
                if auth.isConnected {
                    LabeledContent("Google Calendar") {
                        Text(auth.connectedEmail ?? "Connected")
                            .foregroundStyle(.secondary)
                    }
                    Button("Disconnect", role: .destructive) { auth.disconnect() }
                } else {
                    Button(connectingCalendar ? "Connecting…" : "Connect Google Calendar") {
                        connectCalendar()
                    }
                    .disabled(connectingCalendar)
                }
                Text("Only reads today's events to show on your Home screen — nothing is written back to your calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("New Sticky Defaults") {
                LabeledContent("Color") { colorButton }
                LabeledContent("Font") { fontButton }
                Picker("Title Size", selection: $settings.titleSize) {
                    ForEach(StickyTitleSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Screen Position", selection: $corner) {
                    ForEach(StickyCorner.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .onChange(of: corner) { _, new in StickyCorner.startCorner = new }
            }

            Section("Global Shortcuts") {
                LabeledContent("Show Active Sticky") {
                    ShortcutRecorderField(combo: $settings.showStickyShortcut)
                }
                LabeledContent("New Sticky") {
                    ShortcutRecorderField(combo: $settings.newStickyShortcut)
                }
                Text("Works anywhere, even while another app is frontmost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: settings.showStickyShortcut) { _, _ in GlobalHotKeyManager.shared.reregister() }
            .onChange(of: settings.newStickyShortcut) { _, _ in GlobalHotKeyManager.shared.reregister() }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 480)
        .sheet(item: $paywallPack) { pack in
            ColorPackPaywallView(pack: pack) { }
        }
    }

    // MARK: - Color

    private var colorButton: some View {
        Button { showColorPicker.toggle() } label: {
            HStack(spacing: 7) {
                colorSwatch(color)
                Text(color?.displayName ?? "Random")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showColorPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    swatchButton(nil)
                    ForEach(StickyColor.allCases.filter { $0.pack == nil }) { c in swatchButton(c) }
                }
                ForEach(ColorPack.allCases) { pack in
                    HStack(spacing: 10) {
                        if packStore.isUnlocked(pack) {
                            ForEach(pack.colors) { c in swatchButton(c) }
                        } else {
                            Button { paywallPack = pack } label: {
                                HStack(spacing: 6) {
                                    ForEach(pack.colors) { c in
                                        Circle().fill(c.paper).frame(width: 14, height: 14)
                                    }
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func swatchButton(_ c: StickyColor?) -> some View {
        Button {
            color = c
            StickyColor.defaultColor = c
            showColorPicker = false
        } label: {
            colorSwatch(c, size: 22)
                .overlay(Circle().stroke(.primary, lineWidth: color == c ? 2 : 0).padding(-3))
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ c: StickyColor?, size: CGFloat = 14) -> some View {
        Group {
            if let c {
                Circle().fill(c.paper)
            } else {
                Circle().fill(AngularGradient(colors: StickyColor.allCases.filter { $0.pack == nil }.map(\.paper), center: .center))
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Font

    private var fontButton: some View {
        Button { showFontPicker.toggle() } label: {
            HStack(spacing: 7) {
                Text(font.displayName).font(fontPreview(font, size: 13))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFontPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(StickyFont.allCases) { f in
                    Button {
                        font = f
                        StickyFont.defaultFont = f
                        showFontPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(f.displayName).font(fontPreview(f, size: 14))
                            if f == font {
                                Spacer(minLength: 12)
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                }
            }
            .padding(8)
            .frame(width: 180)
        }
    }

    private func fontPreview(_ f: StickyFont, size: CGFloat) -> Font {
        f.body(size) // includes each font's sizeAdjustment, so they all read as the same visual size
    }

    private var placeholderName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? NSFullUserName()
    }

    private func connectCalendar() {
        connectingCalendar = true
        Task {
            defer { connectingCalendar = false }
            try? await auth.connect()
        }
    }
}
