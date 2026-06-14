import Foundation

/// Coarse sleep/wake state for one epoch. Phone-on-mattress actigraphy can reliably
/// separate sleep from wake but *not* sleep stages (REM/deep), so the model never
/// claims more than this.
enum SleepState: String, Codable {
    case asleep
    case awake
}

/// One fixed-length window of the night with its accumulated movement and — after
/// classification — its sleep/wake label.
struct SleepEpoch: Codable, Identifiable {
    var id = UUID()
    var index: Int          // 0-based epoch number from session start
    var start: Date
    var activity: Double    // accumulated movement "count" for the epoch
    var state: SleepState = .awake
}

enum SoundEventKind: String, Codable {
    case snoring
    case breathing
    case other
}

/// A relevant sound the classifier flagged during the night.
struct SoundEvent: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var kind: SoundEventKind
    var confidence: Double
}

/// Summary statistics for a night, all derived from the classified epochs.
struct SleepMetrics: Codable {
    var timeInBed: TimeInterval = 0       // total session length
    var totalSleepTime: TimeInterval = 0  // epochs scored asleep
    var sleepEfficiency: Double = 0       // TST / TIB, 0...1
    var sleepOnsetLatency: TimeInterval = 0
    var wakeAfterSleepOnset: TimeInterval = 0
    var awakenings: Int = 0
    var snoreMinutes: Double = 0
}

/// One recorded night.
struct SleepSession: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var epochLength: TimeInterval     // seconds per epoch (e.g. 60)
    var epochs: [SleepEpoch]
    var soundEvents: [SoundEvent]
    var metrics: SleepMetrics

    var duration: TimeInterval { end.timeIntervalSince(start) }
}
