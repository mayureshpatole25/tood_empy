import AppKit
import SwiftUI

/// A quiet, read-only browse of finished stickies — archived instead of
/// deleted from the close confirmation, kept as a memory rather than living
/// on your desktop. Each entry can still be permanently deleted from here,
/// for actually cleaning up old ones.
struct ArchivedStickiesView: View {
    let manager: StickyManager
    var onDone: () -> Void

    @State private var entries: [ArchivedSticky] = []

    private let desk = Color(hex: 0xFBF8F1)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 480, height: 560)
        .background(desk)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack {
            Text("Archived Stickies")
                .font(.system(size: 20, weight: .medium))
            Spacer()
            Button("Done") { onDone() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Nothing archived yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Archive a finished sticky (instead of deleting it) and it'll show up here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func row(_ entry: ArchivedSticky) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(entry.data.colorID.paper)
                .frame(width: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.data.title.isEmpty ? "To Do" : entry.data.title)
                    .font(.system(size: 15, weight: .medium))
                Text(itemsSummary(entry))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: entry.archivedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))
            }

            Spacer()

            Button { requestDelete(entry) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.03)))
    }

    private func itemsSummary(_ entry: ArchivedSticky) -> String {
        let items = entry.data.items.filter { !$0.text.isEmpty }
        guard !items.isEmpty else { return "No items" }
        let done = items.filter { $0.isDone }.count
        return "\(done)/\(items.count) done"
    }

    private func requestDelete(_ entry: ArchivedSticky) {
        let alert = NSAlert()
        alert.messageText = "Delete this memory for good?"
        let title = entry.data.title.isEmpty ? "To Do" : entry.data.title
        alert.informativeText = "\"\(title)\" will be gone for good — this can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        manager.stickyArchive.delete(entry.id)
        reload()
    }

    private func reload() {
        entries = manager.stickyArchive.load().sorted { $0.archivedAt > $1.archivedAt }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
