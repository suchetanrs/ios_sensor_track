import Foundation

/// Persists finished nights as one JSON file each under Documents/SleepSessions/.
/// Independent of the Obsidian sync's UserDefaults storage.
final class SleepSessionStore {
    private let dir: URL
    private let fm = FileManager.default

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("SleepSessions", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func save(_ session: SleepSession) {
        let url = dir.appendingPathComponent("\(session.id.uuidString).json")
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: url)
        }
    }

    func loadAll() -> [SleepSession] {
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(SleepSession.self, from: data)
            }
            .sorted { $0.start > $1.start }
    }

    func delete(_ session: SleepSession) {
        let url = dir.appendingPathComponent("\(session.id.uuidString).json")
        try? fm.removeItem(at: url)
    }
}
