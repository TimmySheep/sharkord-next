import SwiftUI

@main
struct SharkordWatchApp: App {
    @StateObject private var model = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
                .environmentObject(model.radio)
        }
    }
}
