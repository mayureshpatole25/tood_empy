import Foundation
import Observation

/// Tracks which paid color packs this Mac has unlocked. `@Observable` so
/// swatch pickers update live the moment a redemption succeeds.
@MainActor
@Observable
final class ColorPackStore {
    static let shared = ColorPackStore()

    private(set) var unlockedPackIDs: Set<String>

    private init() {
        unlockedPackIDs = Set(UserDefaults.standard.stringArray(forKey: Keys.unlocked) ?? [])
    }

    func isUnlocked(_ pack: ColorPack) -> Bool { unlockedPackIDs.contains(pack.id) }

    /// Redeems a pasted license key for a specific pack. Which pack is
    /// known from context (whichever paywall card the user redeemed from),
    /// not parsed out of Polar's response.
    func redeem(licenseKey: String, for pack: ColorPack) async throws {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PolarLicenseService.LicenseError.invalidKey }

        let activationID = try await PolarLicenseService.activate(key: trimmed)
        UserDefaults.standard.set(activationID, forKey: Keys.activationID(pack))
        unlockedPackIDs.insert(pack.id)
        UserDefaults.standard.set(Array(unlockedPackIDs), forKey: Keys.unlocked)
    }

    private enum Keys {
        static let unlocked = "today.unlockedColorPacks"
        static func activationID(_ pack: ColorPack) -> String { "today.colorPackActivation.\(pack.id)" }
    }
}
