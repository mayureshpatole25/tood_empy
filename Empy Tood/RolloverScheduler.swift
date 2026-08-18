import Foundation
import AppKit

/// Fires an (idempotent) rollover at local midnight, plus catch-up on launch
/// and on wake/clock-change. Robust to sleep and DST because it always
/// recomputes the next boundary rather than adding 24h.
@MainActor
final class RolloverScheduler {
    private let onRollover: () -> Void
    private var timer: Timer?
    private let defaultsKey = "today.lastRolloverDay"

    init(onRollover: @escaping () -> Void) {
        self.onRollover = onRollover
    }

    func start() {
        // Catch up if the day changed while we were closed/asleep.
        runIfNeeded()
        scheduleNextMidnight()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(wakeOrClockChanged),
                       name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(wakeOrClockChanged),
            name: .NSSystemClockDidChange, object: nil)
    }

    @objc private func wakeOrClockChanged() {
        runIfNeeded()
        scheduleNextMidnight()
    }

    /// Runs the rollover only if we haven't already rolled over today.
    private func runIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        let last = (UserDefaults.standard.object(forKey: defaultsKey) as? Date)
            .map { Calendar.current.startOfDay(for: $0) }
        if last == today { return }
        onRollover()
        UserDefaults.standard.set(today, forKey: defaultsKey)
    }

    private func scheduleNextMidnight() {
        timer?.invalidate()
        // A few seconds past midnight to avoid boundary ambiguity.
        guard let next = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime) else { return }

        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runIfNeeded()
                self?.scheduleNextMidnight() // never assume +24h
            }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
