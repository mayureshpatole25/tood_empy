import Foundation

/// Reads/writes the sticky collection as JSON inside the sandboxed app
/// container's Application Support directory. No extra entitlement required.
struct PersistenceService {
    private let fileName = "stickies.json"

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.renee.Today", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    /// Distinguishes a true first run (no file) from an intentionally empty
    /// list (file exists, all stickies deleted).
    var hasSavedFile: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    func load() -> [StickyData] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([StickyData].self, from: data)) ?? []
    }

    func save(_ stickies: [StickyData]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(stickies) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
