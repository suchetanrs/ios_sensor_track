import SwiftUI
import Charts

/// Morning report for one night: headline metrics, a sleep/wake hypnogram, and a
/// snore timeline if the mic was on.
struct SleepSummaryView: View {
    let session: SleepSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                metrics
                hypnogram
                if !session.soundEvents.isEmpty { sounds }
            }
            .padding()
        }
        .navigationTitle(session.start.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Metrics

    private var metrics: some View {
        let m = session.metrics
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            stat("Time asleep", timeString(m.totalSleepTime), "moon.zzz.fill")
            stat("Time in bed", timeString(m.timeInBed), "bed.double.fill")
            stat("Efficiency", "\(Int(m.sleepEfficiency * 100))%", "chart.bar.fill")
            stat("Onset latency", timeString(m.sleepOnsetLatency), "hourglass")
            stat("Awake after onset", timeString(m.wakeAfterSleepOnset), "eye")
            stat("Awakenings", "\(m.awakenings)", "arrow.up.circle")
            if m.snoreMinutes > 0 {
                stat("Snoring", "\(Int(m.snoreMinutes)) min", "waveform")
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3).bold()
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Hypnogram

    private var hypnogram: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep / Wake").font(.headline)
            Chart(session.epochs) { epoch in
                LineMark(
                    x: .value("Time", epoch.start),
                    y: .value("State", epoch.state == .asleep ? 0.0 : 1.0)
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(.indigo)
            }
            .chartYScale(domain: -0.2...1.2)
            .chartYAxis {
                AxisMarks(values: [0.0, 1.0]) { value in
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(d == 0 ? "Asleep" : "Awake")
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    // MARK: - Sounds

    private var sounds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snoring & breathing").font(.headline)
            Chart(session.soundEvents) { event in
                PointMark(
                    x: .value("Time", event.date),
                    y: .value("Type", event.kind.rawValue)
                )
                .foregroundStyle(event.kind == .snoring ? Color.orange : Color.teal)
                .symbolSize(40)
            }
            .frame(height: 120)
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
