import Foundation
import SwiftUI

/// User-entered configuration, persisted on the device (token lives in the Keychain, not here).
struct SyncSettings: Codable {
    var username = ""
    var repoInput = ""        // "owner/repo" or a full github.com URL
    var branch = "main"
    var vaultBookmark: Data?  // security-scoped bookmark to the chosen vault folder
    var vaultPath = ""        // human-readable path, for display only

    /// Extracts (owner, repo) from either "owner/repo" or a GitHub URL.
    func parsed() -> (String, String) {
        var s = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "github.com") {
            s = String(s[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ":/ "))
        }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        let parts = s.split(separator: "/").map(String.init)
        if parts.count >= 2 { return (parts[parts.count - 2], parts[parts.count - 1]) }
        return ("", "")
    }

    var owner: String { parsed().0 }
    var repo: String { parsed().1 }
    var resolvedBranch: String { branch.isEmpty ? "main" : branch }
    var isValid: Bool { !username.isEmpty && !owner.isEmpty && !repo.isEmpty && vaultBookmark != nil }
}

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var text: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var settings = SyncSettings()
    @Published var token = ""
    @Published var log: [LogEntry] = []
    @Published var status = "Idle"
    @Published var isRunning = false
    @Published var isSyncing = false
    @Published var lastSync: Date?

    private var manifest: [String: String] = [:]   // last-synced state: path -> git blob SHA
    private var head: String?                       // last-synced commit SHA
    private var timer: Timer?
    private let location = LocationKeepAlive()
    private let engine = SyncEngine()

    init() {
        load()
        token = Keychain.get() ?? ""
    }

    // MARK: - Persistence

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "settings"),
           let s = try? JSONDecoder().decode(SyncSettings.self, from: data) { settings = s }
        if let data = d.data(forKey: "manifest"),
           let m = try? JSONDecoder().decode([String: String].self, from: data) { manifest = m }
        head = d.string(forKey: "head")
        if let data = d.data(forKey: "log"),
           let l = try? JSONDecoder().decode([LogEntry].self, from: data) { log = l }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "settings")
        }
        Keychain.set(token)
        addLog("Settings saved.")
    }

    private func saveState() {
        let d = UserDefaults.standard
        if let m = try? JSONEncoder().encode(manifest) { d.set(m, forKey: "manifest") }
        d.set(head, forKey: "head")
    }

    private func saveLog() {
        if let data = try? JSONEncoder().encode(Array(log.prefix(500))) {
            UserDefaults.standard.set(data, forKey: "log")
        }
    }

    func addLog(_ text: String) {
        log.insert(LogEntry(date: Date(), text: text), at: 0)
        if log.count > 500 { log.removeLast(log.count - 500) }
        saveLog()
    }

    func clearLog() { log.removeAll(); saveLog() }

    // MARK: - Vault folder

    func setVault(_ url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            settings.vaultBookmark = try url.bookmarkData(options: [],
                                                          includingResourceValuesForKeys: nil,
                                                          relativeTo: nil)
            settings.vaultPath = url.path
            saveSettings()
            addLog("Vault folder set: \(url.lastPathComponent)")
        } catch {
            addLog("Failed to bookmark folder: \(error.localizedDescription)")
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard settings.isValid, !token.isEmpty else {
            status = "Fill in all settings first"
            addLog("Cannot start: missing username, token, repo, or vault folder.")
            return
        }
        Notifier.requestAuth()
        location.requestAuth()
        location.start()
        isRunning = true
        status = "Running"
        addLog("Sync started (every 30s; background via location keep-alive).")
        scheduleTimer()
        syncNow()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        location.stop()
        isRunning = false
        status = "Stopped"
        addLog("Sync stopped.")
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func syncNow() {
        guard settings.isValid, !token.isEmpty else { return }
        guard !isSyncing else { return }
        isSyncing = true
        status = "Syncing…"

        let config = SyncConfig(owner: settings.owner,
                                repo: settings.repo,
                                branch: settings.resolvedBranch,
                                token: token,
                                vaultBookmark: settings.vaultBookmark!)
        let m = manifest
        let h = head

        Task {
            do {
                let result = try await engine.sync(config: config, manifest: m, head: h)
                manifest = result.manifest
                head = result.head
                saveState()
                for line in result.logs { addLog(line) }
                if !result.conflicts.isEmpty {
                    let list = result.conflicts.joined(separator: ", ")
                    addLog("⚠️ Merge conflict: \(list)")
                    Notifier.notify(title: "SensorTrack — merge conflict",
                                    body: "Conflicts in: \(list). Remote copies were saved alongside your files.")
                }
                lastSync = Date()
                status = isRunning ? "Running" : "Idle"
            } catch {
                addLog("Error: \(error)")
                status = isRunning ? "Running (last sync failed)" : "Idle"
            }
            isSyncing = false
        }
    }
}
