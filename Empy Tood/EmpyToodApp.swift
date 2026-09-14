import SwiftUI

@main
struct EmpyToodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // AppKit owns all windows and the visible status item. Keep a scene
        // without a restorable Settings window or an additional menu bar item.
        MenuBarExtra("Empy Tood", isInserted: .constant(false)) {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Achievements") { appDelegate.showAchievements() }
            }
        }
    }
}
