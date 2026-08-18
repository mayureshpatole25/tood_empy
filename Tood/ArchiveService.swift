import Foundation

/// A completed task moved out of a sticky at the end of the day. Kept for
/// history and, later, analytics ("how many tasks completed").
struct ArchivedItem: Codable, Identifiable {
    var id: UUID
    var text: String
    var stickyID: UUID
    var stickyTitle: String
    var completedAt: Date?
    var archivedOn: Date
    /// The sticky's color at archive time, for the Home insight card's
    /// colored task dots. Optional so older archive files without this
    /// field still decode fine — those just show as `nil`.
    var stickyColor: StickyColor?
}

/// Append-only JSON archive alongside the sticky store.
struct ArchiveService {
    private let fileName = "archive.json"

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(AppIdentity.storageDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    func load() -> [ArchivedItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ArchivedItem].self, from: data)) ?? []
    }

    func append(_ items: [ArchivedItem]) {
        guard !items.isEmpty else { return }
        var all = load()
        all.append(contentsOf: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(all) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var count: Int { load().count }
}
