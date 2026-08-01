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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only agent: no Dock icon, no app menu bar takeover.
        NSApp.setActivationPolicy(.accessory)

        registerBundledFonts()
        manager = StickyManager()
        journal = JournalStore()
        statusMenu = StatusMenuController(manager: manager, appDelegate: self)
        manager.restoreAll()

        GlobalHotKeyManager.shared.onShowSticky = { [weak self] in self?.manager.showActiveSticky() }
        GlobalHotKeyManager.shared.onNewSticky = { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.manager.newSticky()
        }
        GlobalHotKeyManager.shared.reregister()

        if !AppSettings.shared.onboardingCompleted {
            showIntro()
        }
    }

    // Re-launching the app (e.g. from Finder) reveals the notes again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        manager.showAll()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.saveNow()
    }

    // MARK: - Windows

    func showHome() {
        if homeWindow == nil {
            homeWindow = HostedWindowController(
                title: "Today",
                size: NSSize(width: 900, height: 640),
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
            title: "Today",
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
            title: "Welcome to Today",
            size: NSSize(width: 640, height: 520),
            resizable: false,
            hidesTitleBar: true,
            content: OnboardingView(manager: manager, settings: AppSettings.shared, onFinish: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
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
