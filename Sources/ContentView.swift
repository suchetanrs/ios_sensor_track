import SwiftUI
import UniformTypeIdentifiers

/// Home screen: lists every functionality the app offers. Each row pushes its feature.
struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink {
                    ObsidianSyncView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Obsidian Sync")
                            Text("Two-way sync your vault with a GitHub repo")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }

                NavigationLink {
                    SleepTrackerView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sleep Tracker")
                            Text("Track sleep from movement + sound")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bed.double")
                    }
                }
            }
            .navigationTitle("SensorTrack")
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Obsidian Sync

/// Container for the Obsidian-sync functionality: the live sync screen plus its settings.
struct ObsidianSyncView: View {
    var body: some View {
        TabView {
            SyncView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

struct SyncView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isRunning ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(state.status).font(.headline)
                    Spacer()
                }
                if let d = state.lastSync {
                    HStack {
                        Text("Last sync: \(d.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                }
                HStack {
                    if state.isRunning {
                        Button(role: .destructive) { state.stop() } label: {
                            Text("Stop").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button { state.start() } label: {
                            Text("Start syncing").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button { state.syncNow() } label: { Text("Sync now") }
                        .buttonStyle(.bordered)
                        .disabled(state.isSyncing)
                }
            }
            .padding()

            Divider()

            List(state.log) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text).font(.system(.footnote, design: .monospaced))
                    Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Obsidian Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") { state.clearLog() }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showPicker = false

    var body: some View {
        Form {
            Section("GitHub") {
                TextField("Username", text: $state.settings.username)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("Personal access token", text: $state.token)
                TextField("Repo (owner/repo or URL)", text: $state.settings.repoInput)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("Branch", text: $state.settings.branch)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }

            Section("Vault folder") {
                Button { showPicker = true } label: {
                    Label("Choose vault folder", systemImage: "folder")
                }
                if !state.settings.vaultPath.isEmpty {
                    Text(state.settings.vaultPath)
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section {
                Button { state.saveSettings() } label: { Text("Save settings") }
            }

            Section(footer: Text("Everything is stored on this device — the token in the Keychain, the rest in app storage. Syncing runs every 30s while the app is open; in the background it relies on the location keep-alive (grant \u{201C}Always\u{201D} location and keep the phone charging).")) {
                EmptyView()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                state.setVault(url)
            }
        }
    }
}
