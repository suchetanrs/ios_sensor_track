import Foundation
import CoreMotion

/// Drives the accelerometer at a low rate and forwards gravity-removed movement
/// magnitudes. It uses Core Motion's device-motion `userAcceleration` (gravity already
/// subtracted) so a still phone reads ~0. Runs on a background queue and retains no raw
/// samples — they go straight into the epoch aggregator.
final class AccelerometerFeeder {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    let sampleRate: Double   // Hz

    /// (movement magnitude in g, monotonic timestamp in seconds). Called off the main thread.
    var onSample: ((Double, TimeInterval) -> Void)?

    init(sampleRate: Double = 10) {
        self.sampleRate = sampleRate
        queue.name = "com.example.sensortrack.sleep.accelerometer"
        queue.maxConcurrentOperationCount = 1
    }

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / sampleRate
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.userAcceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            self.onSample?(magnitude, data.timestamp)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
