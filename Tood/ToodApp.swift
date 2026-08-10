import SwiftUI

@main
struct ToodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No WindowGroup — the sticky windows are created imperatively by the
        // AppDelegate/StickyManager. `Settings` is an empty scene that keeps
        // SwiftUI's App lifecycle happy without auto-opening a window.
        Settings {
            EmptyView()
        }
    }
}
