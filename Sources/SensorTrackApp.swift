import SwiftUI

@main
struct SensorTrackApp: App {
    @StateObject private var state = AppState()
    @StateObject private var sleepTracker = SleepTracker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .environmentObject(sleepTracker)
        }
    }
}
