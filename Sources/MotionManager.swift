import Foundation
import CoreMotion

/// Reads the three raw motion sensors and publishes one formatted line each.
final class MotionManager: ObservableObject {
    private let manager = CMMotionManager()

    @Published var accelerometer = "Accelerometer: waiting…"
    @Published var gyroscope     = "Gyroscope: waiting…"
    @Published var magnetometer  = "Magnetometer: waiting…"

    func start() {
        if manager.isAccelerometerAvailable {
            manager.accelerometerUpdateInterval = 0.1
            manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let a = data?.acceleration else { return }
                self?.accelerometer = String(format: "Accelerometer:  x %.2f   y %.2f   z %.2f", a.x, a.y, a.z)
            }
        }
        if manager.isGyroAvailable {
            manager.gyroUpdateInterval = 0.1
            manager.startGyroUpdates(to: .main) { [weak self] data, _ in
                guard let g = data?.rotationRate else { return }
                self?.gyroscope = String(format: "Gyroscope:      x %.2f   y %.2f   z %.2f", g.x, g.y, g.z)
            }
        }
        if manager.isMagnetometerAvailable {
            manager.magnetometerUpdateInterval = 0.1
            manager.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
                guard let m = data?.magneticField else { return }
                self?.magnetometer = String(format: "Magnetometer:   x %.2f   y %.2f   z %.2f", m.x, m.y, m.z)
            }
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        manager.stopMagnetometerUpdates()
    }
}
