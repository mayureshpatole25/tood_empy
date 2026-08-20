import AppKit
import SwiftUI
import CoreText

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: StickyManager!
    private var journal: JournalStore!
    private var statusMenu: StatusMenuController!

    private var homeWindow: HostedWindowController<HomeView>?
    private var settingsWindow: HostedWindowController<SettingsView>?
    private var onboardingWindow: HostedWindowController<OnboardingView>?
    private var introWindow: HostedWindowController<IntroFallView>?
    private var applicationShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app: Dock icon visible, matches LSUIElement=false in
        // Info.plist. (This call is what actually governs it at runtime —
        // Info.plist's LSUIElement alone isn't enough once the app is
        // already running.)
        NSApp.setActivationPolicy(.regular)

        // The whole design (cream paper, dark ink text) is deliberately
        // light-only — there's no dark palette for it. Without this, macOS
        // Dark Mode flips every semantic/system color (.primary, .secondary,
        // system backgrounds, etc.) to their dark-mode values while the
        // hardcoded cream/paper backgrounds stay put, producing white text
        // on a light background. Forcing light appearance for the whole app
        // keeps it looking the same regardless of the system setting.
        NSApp.appearance = NSAppearance(named: .aqua)

        registerBundledFonts()
        manager = StickyManager()
        journal = JournalStore()
        manager.onOpenHome = { [weak self] in self?.showHome() }
        statusMenu = StatusMenuController(manager: manager, appDelegate: self)
        manager.restoreAll()

        // These two commands must remain available even after the final
        // sticky has been closed, when there is no key sticky window to
        // receive the next keystroke.
        applicationShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, AppSettings.shared.onboardingCompleted else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            guard modifiers == [.command, .shift] else { return event }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "t":
                self.manager.reopenLastClosedSticky()
                return nil
            case "h":
                self.manager.openHome()
                return nil
            default:
                return event
            }
        }

        GlobalHotKeyManager.shared.onShowSticky = { [weak self] in self?.manager.showActiveSticky() }
        GlobalHotKeyManager.shared.onNewSticky = { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.manager.newSticky()
        }
        GlobalHotKeyManager.shared.reregister()

        if !AppSettings.shared.onboardingCompleted {
            // Don't let real floating stickies (a true first run's
            // auto-created one, or any left over from previous use while
            // testing) appear behind/around the onboarding windows — the
            // "Sticky" step reveals its one sticky deliberately, and
            // `onFinish` below reveals the rest once onboarding is done.
            manager.hideAll()
            showIntro()
        } else {
            // Normal launches go straight back to the one sticky that was
            // open and active. Home is intentionally available only from
            // the menu-bar command.
            manager.focusLastOpenSticky()
        }
    }

    // Re-launching the app while it's already running (e.g. opening it
    // again from Finder/Spotlight) returns to the already-open sticky. It
    // must not open Home or resurrect a sticky the user closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Guard against the Dock icon (now always visible) being clicked
        // mid-onboarding — that shouldn't reveal every sticky and Home
        // before onboarding's own "Sticky" step gets to do that itself.
        guard AppSettings.shared.onboardingCompleted else { return true }
        manager.focusLastOpenSticky()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.saveNow()
    }

    deinit {
        if let applicationShortcutMonitor { NSEvent.removeMonitor(applicationShortcutMonitor) }
    }

    // MARK: - Windows

    func showHome() {
        if homeWindow == nil {
            homeWindow = HostedWindowController(
                title: AppIdentity.displayName,
                size: NSSize(width: 900, height: 640),
                minimumSize: HomeView.minimumSize,
                hidesTitleBar: true,
                content: HomeView(manager: manager, journal: journal)
            )
        }
        homeWindow?.present()
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = HostedWindowController(
                title: "Settings",
                size: NSSize(width: 460, height: 480),
                resizable: false,
                content: SettingsView(settings: AppSettings.shared)
            )
        }
        settingsWindow?.present()
    }

    private func showIntro() {
        let controller = HostedWindowController(
            title: AppIdentity.displayName,
            size: NSSize(width: 640, height: 520),
            resizable: false,
            hidesTitleBar: true,
            content: IntroFallView(onContinue: { [weak self] in
                self?.introWindow?.close()
                self?.introWindow = nil
                self?.showOnboarding()
            })
        )
        introWindow = controller
        controller.present()
    }

    private func showOnboarding() {
        let controller = HostedWindowController(
            title: "Welcome to \(AppIdentity.displayName)",
            size: NSSize(width: 640, height: 520),
            resizable: false,
            hidesTitleBar: true,
            content: OnboardingView(manager: manager, settings: AppSettings.shared, onFinish: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.manager.focusLastOpenSticky()
            }, onExitToIntro: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.showIntro()
            })
        )
        onboardingWindow = controller
        controller.present()
    }

    /// Register any fonts bundled in the app (e.g. ABC Stefan Trial) so they
    /// work regardless of what's installed on the machine.
    private func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil)
        else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
