import AppKit
import SwiftUI

/// A quiet, read-only browse of finished stickies — archived instead of
/// deleted from the close confirmation, kept as a memory rather than living
/// on your desktop. Shown as the exact same mini-sticky cards as the Home
/// dashboard's fan (StickyDeskCard, reused as-is), so a memory looks like
/// what it was. Tapping one opens a full-size, read-only view; hovering
/// reveals a trash icon to permanently delete it, for actually cleaning up.
struct ArchivedStickiesView: View {
    let manager: StickyManager
    var onDone: () -> Void

    @State private var entries: [ArchivedSticky] = []
    @State private var viewing: ArchivedSticky?

    private let desk = Color(hex: 0xFBF8F1)
    private let columns = [GridItem(.adaptive(minimum: DeskCardMetrics.width + 24), spacing: 24)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if entries.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(width: 640, height: 560)
        .background(desk)
        .onAppear { reload() }
        .sheet(item: $viewing) { entry in
            ArchivedStickyDetailView(model: StickyModel(data: entry.data), onDone: { viewing = nil })
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
            Text(Self.dateFormatter.string(from: entry.archivedAt))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .overlay(alignment: .topLeading) {
            Button { requestDelete(entry) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .opacity(cardHover[entry.id] == true ? 1 : 0)
        }
        .onHover { cardHover[entry.id] = $0 }
    }

    // Keyed on id rather than a single shared @State so each card's trash
    // icon only reveals on its own hover, not whichever was hovered last.
    @State private var cardHover: [UUID: Bool] = [:]

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
