import AppKit
import SwiftUI

/// The quiet, right-aligned "Today" agenda — no card chrome, just a label
/// and a short list, sized to sit above the stickies without competing
/// with them. Reads live off `GoogleCalendarService` (direct Google OAuth,
/// not EventKit — see `GoogleAuthService` for why).
struct AgendaTimeline: View {
    private let auth = GoogleAuthService.shared
    private let calendar = GoogleCalendarService.shared

    @State private var connecting = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text("Today")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.75))

            content
        }
        .frame(width: 230, alignment: .trailing)
        .task(id: auth.isConnected) {
            await calendar.refreshToday()
        }
        // This app runs for days without relaunching, so a one-time fetch on
        // connect goes stale — wrong day after midnight, edited meeting
        // times never picked up. Keep refreshing periodically for as long
        // as this view is actually on screen.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await calendar.refreshToday()
            }
        }
        // A quiet manual override for the impatient case — just mousing
        // over the agenda re-syncs immediately rather than waiting on the
        // 5-minute background loop. No visible refresh button needed.
        .onHover { isHovering in
            guard isHovering, auth.isConnected, !calendar.isLoading else { return }
            Task { await calendar.refreshToday() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isConnected {
            Button(action: connect) {
                Text(connecting ? "Connecting…" : "Connect Google Calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(connecting)
        } else if calendar.isLoading && calendar.todaysEvents.isEmpty {
            Text("Loading…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.6))
        } else if calendar.lastError != nil {
            Text("Couldn't load your calendar")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else if calendar.todaysEvents.isEmpty {
            Text("Nothing on your calendar today")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(calendar.todaysEvents) { event in
                    eventRow(event)
                }
            }
        }
    }

    /// Taps through to the event's own page on Google Calendar's site
    /// (`htmlLink`, straight from the API — not a hand-built URL). If
    /// Calendar's already open in a browser tab, most browsers reuse that
    /// tab for a same-origin navigation rather than opening a new one.
    private func eventRow(_ event: CalendarEvent) -> some View {
        Button {
            if let url = event.htmlLink { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                Text(event.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                Text(timeLabel(for: event))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .disabled(event.htmlLink == nil)
    }

    private func timeLabel(for event: CalendarEvent) -> String {
        event.isAllDay ? "All day" : Self.timeFormatter.string(from: event.start)
    }

    private func connect() {
        connecting = true
        Task {
            defer { connecting = false }
            try? await auth.connect()
            await calendar.refreshToday()
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
