import SwiftUI

@main
struct SharkordApp: App {
    @StateObject private var model = AppModel()

    init() {
        DiagnosticsLogger.shared.start(app: "iPhone")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.session)
                .environmentObject(model.voice)
        }
    }
}
