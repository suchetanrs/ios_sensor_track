import Foundation

/// Derives the night's summary statistics from the classified epochs. Pure function —
/// no I/O, fully testable.
enum SleepMetricsCalculator {

    static func metrics(epochs: [SleepEpoch],
                        epochLength: TimeInterval,
                        soundEvents: [SoundEvent]) -> SleepMetrics {
        var m = SleepMetrics()
        guard !epochs.isEmpty else { return m }

        m.timeInBed = Double(epochs.count) * epochLength
        let asleepCount = epochs.filter { $0.state == .asleep }.count
        m.totalSleepTime = Double(asleepCount) * epochLength
        m.sleepEfficiency = m.timeInBed > 0 ? m.totalSleepTime / m.timeInBed : 0

        if let first = epochs.firstIndex(where: { $0.state == .asleep }),
           let last = epochs.lastIndex(where: { $0.state == .asleep }) {
            // Latency: time from lights-out to the first sleep epoch.
            m.sleepOnsetLatency = Double(first) * epochLength

            // WASO: wake epochs between the first and last sleep epoch.
            let waso = epochs[first...last].filter { $0.state == .awake }.count
            m.wakeAfterSleepOnset = Double(waso) * epochLength

            // Awakenings: number of wake runs that start after sleep onset.
            var count = 0
            var prev: SleepState = .asleep
            for e in epochs[first...last] {
                if e.state == .awake, prev == .asleep { count += 1 }
                prev = e.state
            }
            m.awakenings = count
        } else {
            // Never fell asleep.
            m.sleepOnsetLatency = m.timeInBed
        }

        // Distinct minutes containing a snore (avoids double-counting overlapping windows).
        let snoreMinutes = Set(
            soundEvents
                .filter { $0.kind == .snoring }
                .map { Int($0.date.timeIntervalSinceReferenceDate / 60) }
        ).count
        m.snoreMinutes = Double(snoreMinutes)

        return m
    }
}
