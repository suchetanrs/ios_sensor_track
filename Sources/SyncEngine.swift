import Foundation
import CryptoKit

enum SyncError: Error, CustomStringConvertible {
    case message(String)
    case http(Int, String)

    var description: String {
        switch self {
        case .message(let m): return m
        case .http(let code, let body):
            let short = body.count > 200 ? String(body.prefix(200)) : body
            return "HTTP \(code): \(short)"
        }
    }
}

struct SyncConfig {
    let owner: String
    let repo: String
    let branch: String
    let token: String
    let vaultBookmark: Data
}

struct SyncResult {
    var manifest: [String: String]
    var head: String?
    var conflicts: [String]
    var logs: [String]
}

/// Git's blob object id: sha1("blob <len>\0<bytes>"). Matches the SHAs GitHub returns in trees.
func gitBlobSHA(_ data: Data) -> String {
    var payload = Data("blob \(data.count)\u{0}".utf8)
    payload.append(data)
    return Insecure.SHA1.hash(data: payload).map { String(format: "%02x", $0) }.joined()
}

// MARK: - GitHub Git Data API client

struct GitHubClient {
    let owner: String
    let repo: String
    let token: String

    private func request(_ method: String, _ path: String, json: Any? = nil) async throws -> Data {
        guard let url = URL(string: "https://api.github.com" + path) else {
            throw SyncError.message("Bad URL: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("SensorTrack", forHTTPHeaderField: "User-Agent")
        if let json = json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SyncError.message("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw SyncError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.message("Unexpected JSON")
        }
        return o
    }

    /// HEAD commit SHA of the branch, or nil if the repo/branch is empty.
    func headSHA(branch: String) async throws -> String? {
        do {
            let o = try object(await request("GET", "/repos/\(owner)/\(repo)/git/ref/heads/\(branch)"))
            return (o["object"] as? [String: Any])?["sha"] as? String
        } catch SyncError.http(let code, _) where code == 404 || code == 409 {
            return nil
        }
    }

    func treeSHA(ofCommit sha: String) async throws -> String {
        let o = try object(await request("GET", "/repos/\(owner)/\(repo)/git/commits/\(sha)"))
        guard let t = (o["tree"] as? [String: Any])?["sha"] as? String else {
            throw SyncError.message("Commit has no tree")
        }
        return t
    }

    /// All blob entries of a tree as [path: blobSHA].
    func tree(_ sha: String) async throws -> [String: String] {
        let o = try object(await request("GET", "/repos/\(owner)/\(repo)/git/trees/\(sha)?recursive=1"))
        var map: [String: String] = [:]
        if let arr = o["tree"] as? [[String: Any]] {
            for e in arr where (e["type"] as? String) == "blob" {
                if let p = e["path"] as? String, let s = e["sha"] as? String { map[p] = s }
            }
        }
        return map
    }

    func blob(_ sha: String) async throws -> Data {
        let o = try object(await request("GET", "/repos/\(owner)/\(repo)/git/blobs/\(sha)"))
        guard let content = o["content"] as? String else { throw SyncError.message("Blob has no content") }
        guard let d = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: "")) else {
            throw SyncError.message("Bad base64 in blob")
        }
        return d
    }

    func createBlob(_ data: Data) async throws -> String {
        let body: [String: Any] = ["content": data.base64EncodedString(), "encoding": "base64"]
        let o = try object(await request("POST", "/repos/\(owner)/\(repo)/git/blobs", json: body))
        guard let s = o["sha"] as? String else { throw SyncError.message("Create blob: no sha") }
        return s
    }

    func createTree(base: String?, entries: [[String: Any]]) async throws -> String {
        var body: [String: Any] = ["tree": entries]
        if let base = base { body["base_tree"] = base }
        let o = try object(await request("POST", "/repos/\(owner)/\(repo)/git/trees", json: body))
        guard let s = o["sha"] as? String else { throw SyncError.message("Create tree: no sha") }
        return s
    }

    func createCommit(message: String, tree: String, parents: [String]) async throws -> String {
        let body: [String: Any] = ["message": message, "tree": tree, "parents": parents]
        let o = try object(await request("POST", "/repos/\(owner)/\(repo)/git/commits", json: body))
        guard let s = o["sha"] as? String else { throw SyncError.message("Create commit: no sha") }
        return s
    }

    /// Fast-forward the branch. Returns false if the remote moved (non-fast-forward).
    func updateRef(branch: String, sha: String) async throws -> Bool {
        do {
            _ = try await request("PATCH", "/repos/\(owner)/\(repo)/git/refs/heads/\(branch)",
                                  json: ["sha": sha, "force": false])
            return true
        } catch SyncError.http(let code, _) where code == 422 {
            return false
        }
    }

    func createRef(branch: String, sha: String) async throws {
        _ = try await request("POST", "/repos/\(owner)/\(repo)/git/refs",
                              json: ["ref": "refs/heads/\(branch)", "sha": sha])
    }
}

// MARK: - Sync engine

/// File-level two-way sync between the local vault and a GitHub branch via the Git Data API.
/// Pulls remote changes, flags real conflicts (saving a remote copy + notifying), then pushes.
struct SyncEngine {

    func sync(config: SyncConfig, manifest base: [String: String], head: String?) async throws -> SyncResult {
        var logs: [String] = []

        var stale = false
        let root = try URL(resolvingBookmarkData: config.vaultBookmark, options: [],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        guard root.startAccessingSecurityScopedResource() else {
            throw SyncError.message("Cannot access the vault folder. Re-pick it in Settings.")
        }
        defer { root.stopAccessingSecurityScopedResource() }

        let client = GitHubClient(owner: config.owner, repo: config.repo, token: config.token)
        let branch = config.branch

        let localFiles = listFiles(root: root)
        let localSHA = shaMap(localFiles)

        // --- Empty repo / branch: push everything as the initial commit ---
        guard let remoteHead = try await client.headSHA(branch: branch) else {
            logs.append("Remote branch '\(branch)' is empty — creating initial commit.")
            var entries: [[String: Any]] = []
            for (path, url) in localFiles {
                guard let d = try? Data(contentsOf: url) else { continue }
                entries.append(["path": path, "mode": "100644", "type": "blob",
                                "sha": try await client.createBlob(d)])
            }
            if entries.isEmpty {
                logs.append("Vault is empty — nothing to push.")
                return SyncResult(manifest: [:], head: nil, conflicts: [], logs: logs)
            }
            let tree = try await client.createTree(base: nil, entries: entries)
            let commit = try await client.createCommit(message: commitMessage(), tree: tree, parents: [])
            try await client.createRef(branch: branch, sha: commit)
            logs.append("Pushed initial commit (\(entries.count) file(s)).")
            return SyncResult(manifest: localSHA, head: commit, conflicts: [], logs: logs)
        }

        let remoteTreeSHA = try await client.treeSHA(ofCommit: remoteHead)
        let remote = try await client.tree(remoteTreeSHA)

        var conflicts: [String] = []
        var deleteRemote: [String] = []
        var pulled = 0

        // --- Reconcile each path using the last-synced manifest as the merge base ---
        for path in Set(base.keys).union(remote.keys).union(localSHA.keys) {
            let b = base[path]
            let r = remote[path]
            let l = localSHA[path]
            if r == l { continue }                       // already identical (incl. both absent)

            let localChanged = (l != b)
            let remoteChanged = (r != b)

            if remoteChanged && !localChanged {
                // Pure remote change → apply to local (add / modify / delete).
                let dest = root.appendingPathComponent(path)
                if let r = r {
                    try writeFile(dest, await client.blob(r))
                } else {
                    try? FileManager.default.removeItem(at: dest)
                }
                pulled += 1
            } else if remoteChanged && localChanged {
                // Both sides changed → conflict. Keep local; save remote as a copy.
                if let r = r {
                    try writeFile(conflictCopyURL(root: root, path: path), await client.blob(r))
                }
                conflicts.append(path)
            } else if localChanged && l == nil {
                // Local deletion, remote unchanged → delete on remote.
                deleteRemote.append(path)
            }
            // (local add/modify with remote unchanged is handled by the push diff below)
        }

        // --- Build the push from the post-merge local state ---
        let finalFiles = listFiles(root: root)
        let finalSHA = shaMap(finalFiles)

        var entries: [[String: Any]] = []
        for (path, sha) in finalSHA where remote[path] != sha {
            guard let url = finalFiles[path], let d = try? Data(contentsOf: url) else { continue }
            entries.append(["path": path, "mode": "100644", "type": "blob",
                            "sha": try await client.createBlob(d)])
        }
        for path in deleteRemote where finalSHA[path] == nil {
            entries.append(["path": path, "mode": "100644", "type": "blob", "sha": NSNull()])
        }

        if entries.isEmpty {
            logs.append(pulled > 0 ? "Pulled \(pulled) change(s); nothing to push." : "Up to date.")
            return SyncResult(manifest: finalSHA, head: remoteHead, conflicts: conflicts, logs: logs)
        }

        let newTree = try await client.createTree(base: remoteTreeSHA, entries: entries)
        let newCommit = try await client.createCommit(message: commitMessage(), tree: newTree,
                                                      parents: [remoteHead])
        guard try await client.updateRef(branch: branch, sha: newCommit) else {
            logs.append("Push rejected (remote moved mid-sync) — will retry next cycle.")
            return SyncResult(manifest: base, head: remoteHead, conflicts: conflicts, logs: logs)
        }

        if pulled > 0 { logs.append("Pulled \(pulled) change(s).") }
        logs.append("Pushed \(entries.count) change(s).")
        return SyncResult(manifest: finalSHA, head: newCommit, conflicts: conflicts, logs: logs)
    }

    // MARK: - Local filesystem helpers

    /// All regular files under the vault as [relativePath: URL], skipping hidden files
    /// (.git, .obsidian, .DS_Store, .trash …).
    private func listFiles(root: URL) -> [String: URL] {
        var result: [String: URL] = [:]
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        guard let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return result }
        for case let url as URL in en {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            var rel = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            if !rel.isEmpty { result[rel] = url }
        }
        return result
    }

    private func shaMap(_ files: [String: URL]) -> [String: String] {
        var m: [String: String] = [:]
        for (path, url) in files {
            if let d = try? Data(contentsOf: url) { m[path] = gitBlobSHA(d) }
        }
        return m
    }

    private func writeFile(_ url: URL, _ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func conflictCopyURL(root: URL, path: String) -> URL {
        let url = root.appendingPathComponent(path)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? "\(stem) (conflict \(Self.stamp()))"
                               : "\(stem) (conflict \(Self.stamp())).\(ext)"
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func commitMessage() -> String { "SensorTrack \(Self.stamp())" }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f.string(from: Date())
    }
}
