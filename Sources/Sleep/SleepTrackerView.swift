import SwiftUI

/// Entry point for the Sleep Tracker feature (pushed from the home screen). The
/// `SleepTracker` is owned at the app level (see `SensorTrackApp`) and read from the
/// environment, so a session survives navigating away and back.
struct SleepTrackerView: View {
    @EnvironmentObject var tracker: SleepTracker

    var body: some View {
        SleepLiveView()
            .navigationTitle("Sleep Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SleepHistoryView()
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
    }
}

/// Live tracking screen: big sleep/wake state, running stats, mic opt-in, start/stop.
struct SleepLiveView: View {
    @EnvironmentObject var tracker: SleepTracker

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: stateIcon)
                    .font(.system(size: 68))
                    .foregroundColor(tracker.isTracking ? .indigo : .secondary)
                Text(stateLabel)
                    .font(.title2).bold()
            }
            .padding(.top, 28)

            if tracker.isTracking {
                VStack(spacing: 12) {
                    row("Elapsed", timeString(tracker.elapsed))
                    row("Movement", String(format: "%.3f g", tracker.currentActivity))
                    if tracker.micEnabled { row("Snores detected", "\(tracker.snoreCount)") }
                }
            }

            Toggle(isOn: Binding(get: { tracker.micEnabled },
                                 set: { tracker.setMic($0) })) {
                Label("Detect snoring (microphone)", systemImage: "waveform")
            }
            .disabled(tracker.isTracking)
            .padding(.horizontal, 24)

            Button {
                tracker.isTracking ? tracker.stop() : tracker.start()
            } label: {
                Text(tracker.isTracking ? "Stop & save" : "Start tracking")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(tracker.isTracking ? .red : .indigo)
            .padding(.horizontal, 24)

            Spacer()

            Text("Put the phone face-down on the mattress near your pillow and keep it plugged in. With the mic off, leave the app open (the screen stays on); with the mic on, the screen can lock.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private var stateIcon: String {
        guard tracker.isTracking else { return "bed.double.fill" }
        return tracker.liveState == .asleep ? "moon.zzz.fill" : "moon.fill"
    }

    private var stateLabel: String {
        guard tracker.isTracking else { return tracker.statusMessage }
        return tracker.liveState == .asleep ? "Asleep" : "Awake"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .padding(.horizontal, 44)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
