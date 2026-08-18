import Foundation
import Observation

/// A way to tell people something without shipping a new version —
/// Sparkle's release notes only show up when there's an actual update to
/// offer. This is just a static JSON file, fetched once per launch; no
/// backend, no auth, nothing to build server-side.
///
/// Authored by editing `docs/announcement.json` and deploying: pick a new
/// `id` to show something new (any id already-seen users haven't seen
/// gets shown once), clear `id`/`message` to show nothing.
struct Announcement: Codable, Equatable {
    var id: String
    var message: String
    var url: String?
    var linkLabel: String?
}

@MainActor
@Observable
final class AnnouncementService {
    static let shared = AnnouncementService()

    private(set) var current: Announcement?

    private let feedURL = URL(string: "https://toodapp.com/announcement.json")!
    private let defaultsKey = "today.lastSeenAnnouncementID"

    private init() {}

    /// Fire-and-forget — a failed/offline fetch just means no banner this
    /// launch, never an error the user sees.
    func checkForAnnouncement() {
        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: feedURL),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let announcement = try? JSONDecoder().decode(Announcement.self, from: data),
                  !announcement.id.isEmpty, !announcement.message.isEmpty
            else { return }

            let lastSeen = UserDefaults.standard.string(forKey: defaultsKey)
            guard announcement.id != lastSeen else { return }
            current = announcement
        }
    }

    func dismiss() {
        if let id = current?.id {
            UserDefaults.standard.set(id, forKey: defaultsKey)
        }
        current = nil
    }
}
