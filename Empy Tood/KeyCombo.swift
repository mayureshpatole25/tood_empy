import Carbon.HIToolbox
import SwiftUI

/// A keyboard shortcut (Carbon virtual keycode + Carbon modifier mask), used
/// by both the global hotkey manager (which needs Carbon's representation)
/// and the settings/onboarding recorder UI (which captures via SwiftUI's
/// `.onKeyPress`).
struct KeyCombo: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += KeyCombo.name(forKeyCode: keyCode)
        return s
    }

    static let defaultShowSticky = KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | controlKey))
    static let defaultNewSticky = KeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | controlKey))

    // MARK: - Codable (stored as a single string in UserDefaults)

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    /// "keyCode:modifiers" — simple enough not to need a JSON round-trip.
    var rawValue: String { "\(keyCode):\(modifiers)" }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let k = UInt32(parts[0]), let m = UInt32(parts[1]) else { return nil }
        self.keyCode = k
        self.modifiers = m
    }

    // MARK: - Keycode <-> letter/digit mapping (covers what a shortcut recorder realistically needs)

    private static let codeToName: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F", UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_Tab): "Tab",
    ]

    private static let nameToCode: [Character: UInt32] = Dictionary(
        uniqueKeysWithValues: codeToName.compactMap { code, name in
            name.count == 1 ? (Character(name.lowercased()), code) : nil
        }
    )

    static func name(forKeyCode code: UInt32) -> String { codeToName[code] ?? "Key\(code)" }

    /// SwiftUI's `.onKeyPress` reports the pressed key as a `KeyEquivalent`
    /// (character-based), so the recorder needs this direction too.
    static func keyCode(for key: KeyEquivalent) -> UInt32? {
        nameToCode[Character(key.character.lowercased())]
    }
}
