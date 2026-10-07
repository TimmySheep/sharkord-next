import SwiftUI
import SharkordCore

@main
struct SharkordWatchApp: App {
    @StateObject private var session: SharkordSession
    @StateObject private var model: WatchSessionModel

    init() {
        let session = SharkordSession()
        _session = StateObject(wrappedValue: session)
        _model = StateObject(wrappedValue: WatchSessionModel(session: session))
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(session)
                .environmentObject(model)
                .environmentObject(model.radio)
        }
    }
}
