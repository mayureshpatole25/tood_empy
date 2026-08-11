import Foundation
import Observation

/// Settings not already owned by `StickyColor`/`StickyFont`/`StickyCorner`
/// (which keep their own UserDefaults-backed statics — reused as-is here,
/// not duplicated) — onboarding completion, launch at login, and the two
/// global shortcuts. `@Observable` so the onboarding/settings SwiftUI screens
/// can bind directly and react live.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var onboardingCompleted: Bool {
        didSet { UserDefaults.standard.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LaunchAtLoginService.set(launchAtLogin)
        }
    }

    var showStickyShortcut: KeyCombo {
        didSet { UserDefaults.standard.set(showStickyShortcut.rawValue, forKey: Keys.showShortcut) }
    }

    var newStickyShortcut: KeyCombo {
        didSet { UserDefaults.standard.set(newStickyShortcut.rawValue, forKey: Keys.newShortcut) }
    }

    /// The journal's one user-set prompt — deliberately not a daily-rotating
    /// one. Shown quietly above the write area; editable any time.
    var journalPrompt: String {
        didSet { UserDefaults.standard.set(journalPrompt, forKey: Keys.journalPrompt) }
    }

    /// Whether saving today's first journal entry also asks Location
    /// Services for a rough "neighborhood, city" stamp.
    var journalLocationEnabled: Bool {
        didSet { UserDefaults.standard.set(journalLocationEnabled, forKey: Keys.journalLocation) }
    }

    /// Overrides the Home screen greeting's name. Empty means "use the
    /// Mac account's name" (`NSFullUserName()`) — no onboarding step needed
    /// to get a real name into "Good morning, Renee" on first launch.
    var userName: String {
        didSet { UserDefaults.standard.set(userName, forKey: Keys.userName) }
    }

    /// The ceiling a sticky's title renders at before the shrink-to-fit
    /// logic in `StickyRootView` ever kicks in — not everyone wants the
    /// title quite as big as the default.
    var titleSize: StickyTitleSize {
        didSet { UserDefaults.standard.set(titleSize.rawValue, forKey: Keys.titleSize) }
    }

    private init() {
        let d = UserDefaults.standard
        onboardingCompleted = d.bool(forKey: Keys.onboardingCompleted)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        showStickyShortcut = d.string(forKey: Keys.showShortcut).flatMap(KeyCombo.init(rawValue:)) ?? .defaultShowSticky
        newStickyShortcut = d.string(forKey: Keys.newShortcut).flatMap(KeyCombo.init(rawValue:)) ?? .defaultNewSticky
        journalPrompt = d.string(forKey: Keys.journalPrompt) ?? "What's actually on your mind today?"
        journalLocationEnabled = d.object(forKey: Keys.journalLocation) as? Bool ?? true
        userName = d.string(forKey: Keys.userName) ?? ""
        titleSize = d.string(forKey: Keys.titleSize).flatMap(StickyTitleSize.init(rawValue:)) ?? .medium
    }

    private enum Keys {
        static let onboardingCompleted = "today.onboardingCompleted"
        static let launchAtLogin = "today.launchAtLogin"
        static let showShortcut = "today.showStickyShortcut"
        static let newShortcut = "today.newStickyShortcut"
        static let journalPrompt = "today.journalPrompt"
        static let journalLocation = "today.journalLocationEnabled"
        static let userName = "today.userName"
        static let titleSize = "today.titleSize"
    }
}
