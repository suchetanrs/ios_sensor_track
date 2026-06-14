import Foundation

/// Cole-Kripke automatic sleep/wake scoring from per-epoch activity counts
/// (Cole et al., 1992, "Automatic sleep/wake identification from wrist activity").
///
/// For each minute epoch:  D = P · Σ wᵢ · Aᵢ   over a window of neighboring epochs.
/// `D < threshold` → asleep, otherwise awake.
///
/// IMPORTANT: the published weights were tuned for research-grade wrist "counts". A
/// phone's accelerometer-derived counts live on a different scale, so `scale` (P) and
/// the activity normalization need calibration on real nights. Those knobs are exposed
/// here so they can be tuned without touching the algorithm itself.
struct ColeKripkeClassifier {
    /// Weights for epochs [-4, -3, -2, -1, 0, +1, +2] relative to the scored epoch.
    var weights: [Double] = [106, 54, 58, 76, 230, 74, 67]
    /// Index within `weights` of the epoch being scored (the "0" position).
    var centerIndex = 4
    /// Overall scale factor P.
    var scale = 0.001
    /// `D` below this is scored asleep.
    var threshold = 1.0

    func classify(_ activity: [Double]) -> [SleepState] {
        guard !activity.isEmpty else { return [] }
        var states = [SleepState](repeating: .awake, count: activity.count)
        for i in 0..<activity.count {
            var d = 0.0
            for (w, weight) in weights.enumerated() {
                let j = i + (w - centerIndex)
                guard j >= 0, j < activity.count else { continue }
                d += weight * activity[j]
            }
            d *= scale
            states[i] = d < threshold ? .asleep : .awake
        }
        return states
    }
}
