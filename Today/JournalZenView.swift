import SwiftUI

/// The distraction-free writing mode — opened from the pen button on Home,
/// not shown inline on the dashboard. The prompt (editable in Settings, not
/// a daily-rotating one) doubles as the write area's own placeholder text —
/// it's what you see in the empty page, and it's gone the moment you start
/// typing, rather than sitting above as a separate permanent heading.
/// "Last updated" + location shown quietly once there's actually something
/// written, and refreshes on every edit (not frozen at the entry's original
/// creation time).
struct JournalZenView: View {
    let journal: JournalStore
    var onDone: () -> Void

    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.dateFormatter.string(from: Date()))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 22)

            ZStack(alignment: .topLeading) {
                if journal.todaysText.isEmpty {
                    Text(AppSettings.shared.journalPrompt)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: textBinding)
                    .font(.system(size: 17))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .focused($bodyFocused)
            }

            HStack(spacing: 10) {
                if let entry = journal.todaysEntry, !entry.text.isEmpty {
                    Text(metaLine(for: entry))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
        }
        .padding(48)
        .frame(width: 640, height: 520)
        .background(Color(hex: 0xFEFCF6))
        .onAppear { bodyFocused = true }
    }

    private var textBinding: Binding<String> {
        Binding(get: { journal.todaysText }, set: { journal.updateTodaysText($0) })
    }

    private func metaLine(for entry: JournalEntry) -> String {
        let time = Self.timeFormatter.string(from: entry.updatedAt)
        if let location = entry.locationLabel { return "Last updated \(time) · \(location)" }
        return "Last updated \(time)"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
