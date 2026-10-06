import SwiftUI

@main
struct SharkordApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(.sharkordBlue)
        }
    }
}
