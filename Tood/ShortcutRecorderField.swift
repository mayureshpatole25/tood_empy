import Carbon.HIToolbox
import SwiftUI

/// Click, then press a key combo (must include at least one modifier) to
/// set a global shortcut. Built on `.onKeyPress` rather than a raw AppKit
/// event monitor since this only needs to work while its own field is
/// focused, inside a normal titled window (unlike the borderless sticky
/// panels, `.onKeyPress` behaves normally here).
struct ShortcutRecorderField: View {
    @Binding var combo: KeyCombo
    @State private var isRecording = false
    @FocusState private var focused: Bool

    var body: some View {
        Button {
            isRecording = true
            focused = true
        } label: {
            Text(isRecording ? "Press keys…" : combo.displayString)
                .frame(minWidth: 130)
                .foregroundStyle(isRecording ? .secondary : .primary)
        }
        .buttonStyle(.bordered)
        .focusable()
        .focused($focused)
        .onKeyPress(phases: .down) { press in
            guard isRecording else { return .ignored }
            var mods: UInt32 = 0
            if press.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
            if press.modifiers.contains(.option) { mods |= UInt32(optionKey) }
            if press.modifiers.contains(.control) { mods |= UInt32(controlKey) }
            if press.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
            guard mods != 0, let keyCode = KeyCombo.keyCode(for: press.key) else { return .ignored }
            combo = KeyCombo(keyCode: keyCode, modifiers: mods)
            isRecording = false
            return .handled
        }
    }
}
