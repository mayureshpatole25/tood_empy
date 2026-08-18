import ServiceManagement

/// Thin wrapper around `SMAppService` (the modern, sandbox-safe launch-at-login
/// API — no helper-app target or deprecated `SMLoginItemSetEnabled` needed).
enum LaunchAtLoginService {
    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Non-fatal — the toggle just won't have taken effect; the
            // Settings screen reflects actual status via `isEnabled` below.
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
