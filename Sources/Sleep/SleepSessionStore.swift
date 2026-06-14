import Foundation

/// Persists finished nights as one JSON file each under Documents/SleepSessions/.
/// Independent of the Obsidian sync's UserDefaults storage.
final class SleepSessionStore {
    private let dir: URL
    private let fm = FileManager.default

    /// Single file holding the in-progress session (if any), separate from finished nights.
    private var activeURL: URL { dir.appendingPathComponent("active-session.json") }

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("SleepSessions", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - In-progress session checkpoint

    func saveActive(_ session: ActiveSleepSession) {
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: activeURL)
        }
    }

    func loadActive() -> ActiveSleepSession? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        return try? JSONDecoder().decode(ActiveSleepSession.self, from: data)
    }

    func clearActive() {
        try? fm.removeItem(at: activeURL)
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
