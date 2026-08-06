import SwiftUI

/// Read-only browse of past entries — the write surface (`JournalZenView`)
/// only ever edits today's; this is just for looking back. Opened from a
/// small history icon there.
struct JournalHistoryView: View {
    let journal: JournalStore
    var onDone: () -> Void

    @State private var selectedID: UUID?

    private var sortedEntries: [JournalEntry] {
        journal.entries.filter { !$0.text.isEmpty }.sorted { $0.day > $1.day }
    }

    private var selected: JournalEntry? {
        sortedEntries.first { $0.id == selectedID } ?? sortedEntries.first
    }

    var body: some View {
        HStack(spacing: 0) {
            list
            Divider()
            detail
        }
        .frame(width: 660, height: 460)
        .background(Color(hex: 0xFEFCF6))
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sortedEntries) { entry in
                    Button { selectedID = entry.id } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Self.dayFormatter.string(from: entry.day))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: 0x20211E))
                            Text(entry.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(entry.id == selected?.id ? Color.black.opacity(0.06) : .clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 220)
        .background(Color.black.opacity(0.02))
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            if let selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Self.dayFormatter.string(from: selected.day))
                            .font(.system(size: 17, weight: .semibold))
                        if let location = selected.locationLabel {
                            Text(location)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Text(selected.text)
                            .font(.system(size: 15))
                            .lineSpacing(5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            } else {
                Spacer()
                Text("No journal entries yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}
