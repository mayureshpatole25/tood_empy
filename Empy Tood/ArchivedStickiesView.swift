import AppKit
import SwiftUI

/// A quiet, read-only browse of finished stickies — archived instead of
/// deleted from the close confirmation, kept as a memory rather than living
/// on your desktop. Shown as the exact same mini-sticky cards as the Home
/// dashboard's fan (StickyDeskCard, reused as-is), so a memory looks like
/// what it was. Tapping one opens a full-size, read-only view; each card also
/// offers direct Restore and Delete actions.
struct ArchivedStickiesView: View {
    let manager: StickyManager
    var onDone: () -> Void

    @State private var entries: [ArchivedSticky] = []
    @State private var viewing: ArchivedSticky?

    private let desk = Color(hex: 0xFBF8F1)
    private let sheetWidth: CGFloat = 640
    private let columnCount = 3
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)

    /// A ScrollView's ideal height is flexible by design (it's built to
    /// absorb overflow, not report a natural size), so left alone the sheet
    /// always claimed a fixed, mostly-empty 640×560 regardless of how many
    /// stickies were actually archived. Sizing to the real row count instead
    /// (capped, so a big archive still scrolls) makes a couple of memories
    /// look like a couple of memories instead of two cards adrift in a mostly
    /// blank sheet.
    private var rows: Int { max(1, Int(ceil(Double(entries.count) / Double(columnCount)))) }
    private var gridContentHeight: CGFloat {
        let rowHeight: CGFloat = DeskCardMetrics.height + 28 + 28 // card + action row + row spacing
        return min(CGFloat(rows) * rowHeight + 20, 480) // caps out and scrolls past ~2 rows
    }
    private var sheetHeight: CGFloat { 68 + (entries.isEmpty ? 220 : gridContentHeight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if entries.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(width: sheetWidth, height: sheetHeight)
        .background(desk)
        .onAppear { reload() }
        .sheet(item: $viewing) { entry in
            ArchivedStickyDetailView(
                model: StickyModel(data: entry.data),
                onRestore: {
                    manager.restoreArchived(entry)
                    viewing = nil
                    reload()
                },
                onDone: { viewing = nil }
            )
        }
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

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(entries) { entry in
                    card(entry)
                }
            }
            .padding(20)
        }
    }

    private func card(_ entry: ArchivedSticky) -> some View {
        // Each entry gets its own throwaway StickyModel purely for display —
        // StickyDeskCard already renders exactly what a real sticky looks
        // like, so reusing it here guarantees a memory actually looks like
        // one instead of a second, drifting copy of the same styling.
        let model = StickyModel(data: entry.data)
        return VStack(spacing: 6) {
            StickyDeskCard(model: model, hoverHint: "View") { viewing = entry }
            HStack(spacing: 8) {
                Text(Self.dateFormatter.string(from: entry.archivedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    manager.restoreArchived(entry)
                    if viewing?.id == entry.id { viewing = nil }
                    reload()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button { requestDelete(entry) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete permanently")
            }
            .frame(width: DeskCardMetrics.width)
        }
    }

    private func requestDelete(_ entry: ArchivedSticky) {
        let alert = NSAlert()
        alert.messageText = "Delete this memory for good?"
        let title = entry.data.title.isEmpty ? "To Do" : entry.data.title
        alert.informativeText = "\"\(title)\" will be gone for good, and can't be undone."
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
