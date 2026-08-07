import SwiftUI

/// A quiet week-of-squares GitHub activity strip for the Home insight card
/// — same shape as GitHub's own contribution graph, recolored with
/// whichever sticky color is set as the default instead of GitHub's green,
/// so it actually looks like it belongs on this desk. Hidden entirely
/// whenever no username is set in Settings or the fetch comes back empty
/// (see `GitHubContributionsService` for why this can silently fail).
struct GitHubActivityStrip: View {
    let username: String

    @State private var days: [GitHubContributionDay] = []
    @State private var loaded = false

    private var tint: Color {
        (StickyColor.defaultColor ?? .green).paper
    }

    var body: some View {
        Group {
            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GITHUB ACTIVITY")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color(hex: 0xA39D8C))

                    HStack(spacing: 4) {
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(tint.opacity(opacity(for: day.level)))
                                .frame(width: 14, height: 14)
                                .help("\(Self.dayFormatter.string(from: day.date)): level \(day.level) of 4")
                        }
                        Spacer(minLength: 0)
                        Text("@\(username)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0xA39D8C))
                    }
                }
            }
        }
        .task(id: username) { await load() }
    }

    private func opacity(for level: Int) -> Double {
        switch level {
        case 0: return 0.08
        case 1: return 0.32
        case 2: return 0.55
        case 3: return 0.78
        default: return 1.0
        }
    }

    private func load() async {
        guard !username.isEmpty else {
            days = []
            return
        }
        let result = await GitHubContributionsService.fetchRecentDays(username: username)
        days = result ?? []
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}
