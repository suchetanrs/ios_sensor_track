import SwiftUI

@main
struct SensorTrackApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(state)
        }
    }
}
