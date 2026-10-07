import SwiftUI

/// Routing: connect -> channel list -> radio room. Same explicit lifecycle as the
/// product definition: joining a channel starts a radio session, leaving ends it.
struct WatchRootView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        Group {
            switch model.phase {
            case .disconnected, .connecting:
                WatchConnectView()
            case .connected:
                WatchChannelListView()
            }
        }
        .background(WatchTheme.background)
    }
}
