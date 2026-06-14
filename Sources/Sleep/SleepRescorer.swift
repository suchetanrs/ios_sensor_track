import Foundation

/// Webster's rescoring rules. Raw actigraphy over-detects brief "sleep" inside long
/// stretches of wakefulness, so after a sustained wake bout the next few minutes of
/// "sleep" are flipped back to wake (Webster et al., 1982). Thresholds are in minutes.
struct SleepRescorer {
    /// How many epochs make up one minute (= 60 / epochLength).
    var epochsPerMinute: Double

    /// (minutes of preceding wake required) → (minutes of following sleep to flip).
    var rules: [(wakeMinutes: Double, sleepMinutes: Double)] = [
        (4, 1), (10, 3), (15, 4)
    ]

    func rescore(_ states: [SleepState]) -> [SleepState] {
        guard epochsPerMinute > 0 else { return states }
        var s = states
        var i = 0
        while i < s.count {
            guard s[i] == .awake else { i += 1; continue }

            // Measure the contiguous wake run [i, j).
            var j = i
            while j < s.count, s[j] == .awake { j += 1 }
            let wakeMinutes = Double(j - i) / epochsPerMinute

            // Strongest matching rule wins.
            var flipMinutes = 0.0
            for r in rules where wakeMinutes >= r.wakeMinutes {
                flipMinutes = max(flipMinutes, r.sleepMinutes)
            }
            if flipMinutes > 0 {
                let flipEpochs = Int((flipMinutes * epochsPerMinute).rounded())
                var k = j
                while k < s.count, k < j + flipEpochs, s[k] == .asleep {
                    s[k] = .awake
                    k += 1
                }
            }
            i = j
        }
        return s
    }
}
