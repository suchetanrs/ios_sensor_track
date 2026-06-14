import SwiftUI

@main
struct VaultSyncApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(state)
        }
    }
}
