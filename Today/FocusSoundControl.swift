import SwiftUI

/// The focus-sound control for Home: one pill, two looks. At rest it's a
/// quiet outlined capsule inviting a tap; tapping it opens a picker of
/// ambient sounds (see `FocusSound`). Once one's chosen, that same pill
/// becomes a dark "now playing" bar with a small live waveform and the
/// sound's name — tapping it again stops playback and it settles back to
/// quiet. Explored as "variant D" in the placement-comparison artifact
/// before landing here, next to the journal button.
struct FocusSoundControl: View {
    @Bindable private var player = FocusSoundPlayer.shared

    @State private var showingPicker = false
    @State private var hovering = false

    private let quietText = Color(hex: 0x8A8578)
    private let darkBg = Color(hex: 0x20211E)
    private let cream = Color(hex: 0xFBF8F1)
    private let accent = Color(hex: 0x3AE28C)

    var body: some View {
        Button {
            if player.isPlaying {
                player.stop()
            } else {
                showingPicker.toggle()
            }
        } label: {
            HStack(spacing: 9) {
                if player.isPlaying {
                    FocusWaveformView(color: accent)
                        .frame(width: 18, height: 12)
                } else {
                    Image(systemName: "headphones")
                        .font(.system(size: 12.5))
                        .foregroundStyle(quietText.opacity(hovering ? 0.95 : 0.7))
                }

                Text(player.currentSound?.displayName ?? "Focus sound")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(player.isPlaying ? cream : quietText.opacity(hovering ? 0.95 : 0.7))

                if player.isPlaying {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(cream.opacity(0.45))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, player.isPlaying ? 14 : 12)
            .background(
                Capsule().fill(player.isPlaying ? darkBg : Color.black.opacity(hovering ? 0.1 : 0.06))
            )
            .shadow(color: .black.opacity(player.isPlaying ? 0.22 : 0), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(player.isPlaying ? "Stop \(player.currentSound?.displayName ?? "")" : "Focus sounds")
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            picker
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(FocusSound.allCases) { sound in
                Button {
                    player.play(sound)
                    showingPicker = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: sound.icon)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(sound.displayName)
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .foregroundStyle(Color(hex: 0x3A3A33))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 6)

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .padding(.vertical, 8)
        .frame(width: 180)
    }
}

/// Five thin bars pulsing at staggered offsets, standing in for a live
/// waveform on the "now playing" pill. Purely decorative, not driven by
/// the actual audio signal.
private struct FocusWaveformView: View {
    let color: Color

    @State private var animate = false
    private let heights: [CGFloat] = [5, 11, 7, 12, 4]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(color)
                    .frame(width: 2, height: height)
                    .scaleEffect(x: 1, y: animate ? 1.15 : 0.55, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 0.85)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
