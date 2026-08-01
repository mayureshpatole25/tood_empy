import Foundation

/// Reads/writes journal entries as JSON in the same Application Support
/// directory as the stickies — local storage only, same pattern as
/// `PersistenceService`.
struct JournalPersistenceService {
    private let fileName = "journal.json"

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.renee.Today", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    func load() -> [JournalEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([JournalEntry].self, from: data)) ?? []
    }

    func save(_ entries: [JournalEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
