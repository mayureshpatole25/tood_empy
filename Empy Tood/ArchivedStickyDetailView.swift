import SwiftUI

/// A full-size, read-only look at an archived sticky — same paper, grain,
/// date/title layout, and checkbox styling as the real thing (StickyRootView),
/// just static: no editable fields, no color/font pickers, nothing that
/// mutates it. Opened by tapping a card in ArchivedStickiesView's grid.
struct ArchivedStickyDetailView: View {
    let model: StickyModel
    var onRestore: () -> Void
    var onDone: () -> Void

    private let corner: CGFloat = 4
    private var color: StickyColor { model.color }

    var body: some View {
        ZStack(alignment: .top) {
            paperBackground
            content
            actions
        }
        .frame(width: 378, height: 490)
    }

    private var paperBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color.paper)
            GrainOverlay()
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.dateFormatter.string(from: model.day))
                .font(model.font.body(14))
                .foregroundStyle(color.ink.opacity(0.3))

            Text(model.title.isEmpty ? "To Do" : model.title)
                .font(.custom("HelveticaNeue", size: 34))
                .tracking(34 * -0.06)
                .foregroundStyle(color.titleInk)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.items.filter { !$0.text.isEmpty }) { item in
                    row(item)
                }
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ item: TodoItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 19) {
                ZStack {
                    if item.isDone {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color.ink.opacity(0.3))
                            .frame(width: 13, height: 13)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(color.paper)
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(color.ink.opacity(0.3), lineWidth: 1.1)
                            .frame(width: 13, height: 13)
                    }
                }
                .frame(width: 24, height: 34)
                Text(item.text)
                    .font(model.font.body(14))
                    .foregroundStyle(item.isDone ? color.inkSecondary : color.ink.opacity(0.8))
                    .strikethrough(item.isDone, color: color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            Rectangle()
                .fill(color.divider)
                .frame(height: 1)
        }
    }

    private var actions: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onRestore) {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(color.ink.opacity(0.6))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(color.ink.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onDone) {
                    Text("X")
                        .font(.custom("ABCStefanTrial-Simple", size: 16))
                        .foregroundStyle(color.ink.opacity(0.3))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 14)
        .padding(.trailing, 14)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM dd, yyyy"
        return f
    }()
}
