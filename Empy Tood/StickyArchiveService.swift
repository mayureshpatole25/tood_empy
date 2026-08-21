import Foundation

/// A whole sticky, archived when the user picks "Archive" over "Delete" from
/// the close confirmation — a full snapshot (title, items, color, day) kept
/// as a browsable memory of finished stickies, distinct from
/// `ArchiveService`'s `ArchivedItem`s (individual completed tasks swept out
/// nightly for the stats, not whole stickies).
struct ArchivedSticky: Codable, Identifiable {
    var id: UUID
    var data: StickyData
    var archivedAt: Date
}

/// Append-mostly JSON archive alongside the sticky store. "Mostly" — the
/// archive view also allows permanently deleting an entry to actually clean
/// up, unlike `ArchiveService`'s append-only item log.
struct StickyArchiveService {
    private let fileName = "archived_stickies.json"

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(AppIdentity.storageDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    func load() -> [ArchivedSticky] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ArchivedSticky].self, from: data)) ?? []
    }

    @discardableResult
    private func save(_ all: [ArchivedSticky]) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(all) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Returns false without changing the live sticky when the archive cannot
    /// be persisted.
    @discardableResult
    func append(_ sticky: ArchivedSticky) -> Bool {
        var all = load()
        all.append(sticky)
        return save(all)
    }

    /// Removes an archived sticky for good — the archive view's own
    /// "Delete" action, for actually cleaning up old memories.
    @discardableResult
    func delete(_ id: UUID) -> Bool {
        var all = load()
        all.removeAll { $0.id == id }
        return save(all)
    }

    var count: Int { load().count }
}
