import SwiftUI

struct ContentView: View {
    @StateObject private var motion = MotionManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(motion.accelerometer)
            Text(motion.gyroscope)
            Text(motion.magnetometer)
        }
        .font(.system(size: 15, weight: .medium, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }
}
