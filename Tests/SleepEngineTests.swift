import XCTest
@testable import SensorTrack

/// Tests for the pure, I/O-free sleep engine: epoch aggregation, Cole-Kripke scoring,
/// Webster rescoring, and metric computation.
final class SleepEngineTests: XCTestCase {

    // MARK: EpochAggregator

    func testAggregatorBucketsByEpochLength() {
        let agg = EpochAggregator(epochLength: 10, deadband: 0)
        var finalized: [EpochAggregator.Epoch] = []
        for t in 0..<10 { finalized += agg.ingest(magnitude: 1, at: Double(t)) }
        XCTAssertTrue(finalized.isEmpty, "no epoch completes before the boundary")

        finalized += agg.ingest(magnitude: 1, at: 10)   // crosses into epoch 1
        XCTAssertEqual(finalized.count, 1)
        XCTAssertEqual(finalized[0].index, 0)
        XCTAssertEqual(finalized[0].activity, 10, accuracy: 1e-9, "ten samples of 1.0")
    }

    func testAggregatorDeadbandIgnoresJitter() {
        let agg = EpochAggregator(epochLength: 10, deadband: 0.5)
        _ = agg.ingest(magnitude: 0.4, at: 0)   // below deadband -> contributes 0
        _ = agg.ingest(magnitude: 1.0, at: 1)   // 0.5 above deadband
        let last = agg.finish()
        XCTAssertEqual(last?.activity ?? -1, 0.5, accuracy: 1e-9)
    }

    func testAggregatorEmitsZeroEpochsAcrossGaps() {
        let agg = EpochAggregator(epochLength: 10, deadband: 0)
        _ = agg.ingest(magnitude: 5, at: 0)
        let finalized = agg.ingest(magnitude: 5, at: 35)  // jumped ~3 epochs ahead
        XCTAssertEqual(finalized.map(\.index), [0, 1, 2])
        XCTAssertEqual(finalized[1].activity, 0, "the skipped epoch had no movement")
    }

    // MARK: ColeKripkeClassifier

    func testColeKripkeStillnessIsAsleep() {
        let states = ColeKripkeClassifier().classify([Double](repeating: 0, count: 20))
        XCTAssertTrue(states.allSatisfy { $0 == .asleep })
    }

    func testColeKripkeHighActivityIsAwake() {
        let states = ColeKripkeClassifier().classify([Double](repeating: 1000, count: 20))
        XCTAssertTrue(states.allSatisfy { $0 == .awake })
    }

    // MARK: SleepRescorer

    func testRescorerFlipsShortSleepAfterLongWake() {
        // 15 min of wake (rule threshold) then 2 min of "sleep" -> both flip to wake.
        var states = [SleepState](repeating: .awake, count: 15)
        states += [.asleep, .asleep]
        let out = SleepRescorer(epochsPerMinute: 1).rescore(states)
        XCTAssertEqual(out[15], .awake)
        XCTAssertEqual(out[16], .awake)
    }

    func testRescorerLeavesSustainedSleepAlone() {
        // Short wake (1 min) then long sleep -> sleep untouched.
        var states: [SleepState] = [.awake]
        states += [SleepState](repeating: .asleep, count: 20)
        let out = SleepRescorer(epochsPerMinute: 1).rescore(states)
        XCTAssertEqual(out[1...].filter { $0 == .asleep }.count, 20)
    }

    // MARK: SleepMetricsCalculator

    func testMetricsEfficiencyAndTotals() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let epochs = (0..<10).map { i in
            SleepEpoch(index: i, start: start.addingTimeInterval(Double(i) * 60),
                       activity: 0, state: i < 8 ? .asleep : .awake)
        }
        let m = SleepMetricsCalculator.metrics(epochs: epochs, epochLength: 60, soundEvents: [])
        XCTAssertEqual(m.timeInBed, 600, accuracy: 1e-9)
        XCTAssertEqual(m.totalSleepTime, 480, accuracy: 1e-9)
        XCTAssertEqual(m.sleepEfficiency, 0.8, accuracy: 1e-9)
    }

    func testMetricsWasoAndAwakenings() {
        // asleep, awake, awake, asleep -> onset at 0, one awakening, 2 min WASO.
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let pattern: [SleepState] = [.asleep, .awake, .awake, .asleep]
        let epochs = pattern.enumerated().map { i, s in
            SleepEpoch(index: i, start: start.addingTimeInterval(Double(i) * 60),
                       activity: 0, state: s)
        }
        let m = SleepMetricsCalculator.metrics(epochs: epochs, epochLength: 60, soundEvents: [])
        XCTAssertEqual(m.sleepOnsetLatency, 0, accuracy: 1e-9)
        XCTAssertEqual(m.wakeAfterSleepOnset, 120, accuracy: 1e-9)
        XCTAssertEqual(m.awakenings, 1)
    }
}
