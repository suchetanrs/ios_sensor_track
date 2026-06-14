import Foundation
import HealthKit

/// Writes a finished night to Apple Health as `sleepAnalysis` samples. Phone-only
/// actigraphy can't stage sleep, so it only writes inBed / asleepUnspecified / awake.
///
/// NOTE: HealthKit needs the HealthKit entitlement, which a *free* (7-day) sideload
/// signing profile cannot grant. Everything here fails gracefully (no crash) when the
/// entitlement or permission is missing. To actually write to Health you need a paid
/// Apple Developer account and to add the HealthKit capability to the target.
final class HealthKitWriter {
    private let store = HKHealthStore()
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        store.requestAuthorization(toShare: [sleepType], read: [sleepType]) { ok, _ in
            DispatchQueue.main.async { completion?(ok) }
        }
    }

    func write(session: SleepSession, completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }

        var samples: [HKCategorySample] = [
            // The whole session counts as "in bed".
            HKCategorySample(type: sleepType,
                             value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                             start: session.start, end: session.end)
        ]

        // Merge consecutive same-state epochs into runs, one sample each.
        for run in runs(session.epochs, epochLength: session.epochLength) {
            let value: HKCategoryValueSleepAnalysis = run.state == .asleep ? .asleepUnspecified : .awake
            samples.append(HKCategorySample(type: sleepType, value: value.rawValue,
                                            start: run.start, end: run.end))
        }

        store.save(samples) { ok, _ in
            DispatchQueue.main.async { completion?(ok) }
        }
    }

    private struct Run { let state: SleepState; let start: Date; let end: Date }

    private func runs(_ epochs: [SleepEpoch], epochLength: TimeInterval) -> [Run] {
        var out: [Run] = []
        var i = 0
        while i < epochs.count {
            let state = epochs[i].state
            var j = i
            while j < epochs.count, epochs[j].state == state { j += 1 }
            let start = epochs[i].start
            let end = epochs[j - 1].start.addingTimeInterval(epochLength)
            out.append(Run(state: state, start: start, end: end))
            i = j
        }
        return out
    }
}
