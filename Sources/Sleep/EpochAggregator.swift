import Foundation

/// Buckets a stream of movement samples into fixed-length epochs, keeping only the
/// per-epoch *activity count* (the sum of above-threshold movement). Raw samples are
/// discarded the moment they are folded in — this is what keeps memory and battery
/// flat across a whole night.
///
/// Pure and deterministic: it never reads the clock itself. The feeder supplies each
/// sample's timestamp, so identical inputs always produce identical epochs, which is
/// what makes the whole pipeline unit-testable.
final class EpochAggregator {

    /// A finalized epoch handed back to the caller.
    struct Epoch {
        let index: Int
        let activity: Double
    }

    let epochLength: TimeInterval
    let deadband: Double            // ignore jitter below this (gravity-removed |accel|, in g)

    private(set) var startTime: TimeInterval?
    private var currentIndex = 0
    private var currentSum = 0.0
    private var started = false

    init(epochLength: TimeInterval = 60, deadband: Double = 0.02) {
        self.epochLength = epochLength
        self.deadband = deadband
    }

    /// Fold one movement magnitude (e.g. |userAcceleration|) sampled at `timestamp`
    /// (monotonic seconds — `CMDeviceMotion.timestamp` works) into the current epoch.
    /// Returns any epochs that this sample completed (usually none; more than one only
    /// if there was a gap with no samples, e.g. the app was suspended).
    @discardableResult
    func ingest(magnitude: Double, at timestamp: TimeInterval) -> [Epoch] {
        if startTime == nil { startTime = timestamp }
        started = true

        let elapsed = timestamp - startTime!
        let target = max(0, Int(elapsed / epochLength))

        var finalized: [Epoch] = []
        while target > currentIndex {
            finalized.append(Epoch(index: currentIndex, activity: currentSum))
            currentSum = 0
            currentIndex += 1
        }

        currentSum += max(0, magnitude - deadband)
        return finalized
    }

    /// Finalize the in-progress epoch when the session ends. Returns nil if nothing
    /// was ever ingested.
    func finish() -> Epoch? {
        guard started else { return nil }
        let epoch = Epoch(index: currentIndex, activity: currentSum)
        currentSum = 0
        return epoch
    }
}
