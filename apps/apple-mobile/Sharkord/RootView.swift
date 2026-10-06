import SwiftUI

/// single switch between the two top level scenes. it lives in its own file because every future
/// scene change (deeplink, expired session) will go through here rather than through a view.
struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.phase {
        case .onboarding:
            NavigationStack {
                ConnectView(model: model)
            }
            .transition(.opacity)
        case .workspace:
            WorkspaceView(model: model)
                .transition(.opacity)
        }
    }
}
