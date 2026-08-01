import SwiftUI

/// The quiet, right-aligned "Today" agenda — no card chrome, just a label
/// and a short list, sized to sit above the stickies without competing
/// with them. Real Google Calendar events (via EventKit) are the next
/// phase of work; until then this is an honest empty state.
struct AgendaTimeline: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text("Today")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.75))
            Text("No calendar connected")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(width: 230, alignment: .trailing)
    }
}
