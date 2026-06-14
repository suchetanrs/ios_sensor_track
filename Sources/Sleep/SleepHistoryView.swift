import SwiftUI

/// List of recorded nights; each row pushes the detailed summary.
struct SleepHistoryView: View {
    @EnvironmentObject var tracker: SleepTracker

    var body: some View {
        List {
            if tracker.sessions.isEmpty {
                Text("No nights recorded yet.")
                    .foregroundColor(.secondary)
            }
            ForEach(tracker.sessions) { session in
                NavigationLink {
                    SleepSummaryView(session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.start.formatted(date: .abbreviated, time: .shortened))
                            .font(.body).bold()
                        HStack(spacing: 14) {
                            Label(timeString(session.metrics.totalSleepTime), systemImage: "moon.zzz")
                            Label("\(Int(session.metrics.sleepEfficiency * 100))%", systemImage: "chart.bar")
                            if session.metrics.snoreMinutes > 0 {
                                Label("\(Int(session.metrics.snoreMinutes))m", systemImage: "waveform")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { tracker.sessions[$0] }.forEach(tracker.delete)
            }
        }
        .navigationTitle("Sleep History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60
        return "\(h)h \(m)m"
    }
}
