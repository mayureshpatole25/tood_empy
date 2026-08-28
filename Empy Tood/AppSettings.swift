import Foundation
import Observation

enum TimerCompletionSound: String, CaseIterable, Identifiable {
    case glass, ping, pop, tink, none

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var systemSoundName: String? { self == .none ? nil : displayName }
}

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

    /// Controls the completion checkmark, strikethrough, and particle burst.
    /// Other interface motion continues to follow the system Reduce Motion
    /// preference independently.
    var completionAnimationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                completionAnimationsEnabled,
                forKey: Keys.completionAnimationsEnabled
            )
        }
    }

    /// Shared presentation state for every open sticky. Timer countdowns stay
    /// per-sticky; only whether their timer UI is visible is global.
    var showsStickyTimers: Bool {
        didSet { UserDefaults.standard.set(showsStickyTimers, forKey: Keys.showsStickyTimers) }
    }

    var showsDoneTasks: Bool {
        didSet { UserDefaults.standard.set(showsDoneTasks, forKey: Keys.showsDoneTasks) }
    }

    /// Starting duration for every newly opened sticky timer. Individual
    /// timers remain intentionally ephemeral and reset to this value when
    /// their sticky closes.
    var defaultTimerSeconds: Int {
        didSet {
            defaultTimerSeconds = min(max(defaultTimerSeconds, 1), 359_999)
            UserDefaults.standard.set(defaultTimerSeconds, forKey: Keys.defaultTimerSeconds)
        }
    }

    var timerCompletionSound: TimerCompletionSound {
        didSet { UserDefaults.standard.set(timerCompletionSound.rawValue, forKey: Keys.timerCompletionSound) }
    }

    var showStickyShortcut: KeyCombo {
        didSet { UserDefaults.standard.set(showStickyShortcut.rawValue, forKey: Keys.showShortcut) }
    }

    var newStickyShortcut: KeyCombo {
        didSet { UserDefaults.standard.set(newStickyShortcut.rawValue, forKey: Keys.newShortcut) }
    }

    var quickCaptureShortcut: KeyCombo {
        didSet { UserDefaults.standard.set(quickCaptureShortcut.rawValue, forKey: Keys.quickCaptureShortcut) }
    }

    /// Retained only so existing on-disk journal data remains compatible if
    /// this legacy model is decoded. Journal is no longer exposed in the UI.
    var journalPrompt: String {
        didSet { UserDefaults.standard.set(journalPrompt, forKey: Keys.journalPrompt) }
    }

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

    /// What closing a sticky does (ask, or skip straight to archive/delete).
    /// Settable here in Settings/the status menu, or from the close dialog's
    /// own "Don't ask me again" checkbox.
    var closeBehavior: StickyCloseBehavior {
        didSet { UserDefaults.standard.set(closeBehavior.rawValue, forKey: Keys.closeBehavior) }
    }

    private init() {
        let d = UserDefaults.standard
        onboardingCompleted = d.bool(forKey: Keys.onboardingCompleted)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        completionAnimationsEnabled = d.object(forKey: Keys.completionAnimationsEnabled) as? Bool ?? true
        showsStickyTimers = d.object(forKey: Keys.showsStickyTimers) as? Bool ?? false
        showsDoneTasks = d.object(forKey: Keys.showsDoneTasks) as? Bool ?? false
        defaultTimerSeconds = min(max(d.object(forKey: Keys.defaultTimerSeconds) as? Int ?? 300, 1), 359_999)
        timerCompletionSound = d.string(forKey: Keys.timerCompletionSound)
            .flatMap(TimerCompletionSound.init(rawValue:)) ?? .glass
        showStickyShortcut = d.string(forKey: Keys.showShortcut).flatMap(KeyCombo.init(rawValue:)) ?? .defaultShowSticky
        newStickyShortcut = d.string(forKey: Keys.newShortcut).flatMap(KeyCombo.init(rawValue:)) ?? .defaultNewSticky
        quickCaptureShortcut = d.string(forKey: Keys.quickCaptureShortcut).flatMap(KeyCombo.init(rawValue:)) ?? .defaultQuickCapture
        journalPrompt = d.string(forKey: Keys.journalPrompt) ?? "What's actually on your mind today?"
        journalLocationEnabled = d.object(forKey: Keys.journalLocation) as? Bool ?? true
        userName = d.string(forKey: Keys.userName) ?? ""
        titleSize = d.string(forKey: Keys.titleSize).flatMap(StickyTitleSize.init(rawValue:)) ?? .medium
        closeBehavior = d.string(forKey: Keys.closeBehavior).flatMap(StickyCloseBehavior.init(rawValue:)) ?? .alwaysAsk
    }

    private enum Keys {
        static let onboardingCompleted = "today.onboardingCompleted"
        static let launchAtLogin = "today.launchAtLogin"
        static let completionAnimationsEnabled = "today.completionAnimationsEnabled"
        static let showsStickyTimers = "today.showsStickyTimers"
        static let showsDoneTasks = "today.showsDoneTasks"
        static let defaultTimerSeconds = "today.defaultTimerSeconds"
        static let timerCompletionSound = "today.timerCompletionSound"
        static let showShortcut = "today.showStickyShortcut"
        static let newShortcut = "today.newStickyShortcut"
        static let quickCaptureShortcut = "today.quickCaptureShortcut"
        static let journalPrompt = "today.journalPrompt"
        static let journalLocation = "today.journalLocationEnabled"
        static let userName = "today.userName"
        static let titleSize = "today.titleSize"
        static let closeBehavior = "today.closeBehavior"
    }
}
