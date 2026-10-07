import SwiftUI
import SharkordCore

/// routing: connect -> channel list -> radio room. Same explicit lifecycle as the
/// product definition: joining a channel starts a radio session, leaving ends it.
struct WatchRootView: View {
    @EnvironmentObject private var session: SharkordSession

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .disconnected, .connecting, .failed:
                    WatchConnectView()
                case .connected:
                    WatchChannelListView()
                }
            }
            .background(WatchTheme.background)
        }
        .preferredColorScheme(.dark)
    }
}
