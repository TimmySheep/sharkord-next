import SharkordCore
import SwiftUI

/// The chat tab: a segmented pill choosing between the open text channel and the open
/// direct message, then the conversation itself. Picking a conversation on the channels
/// tab lands here.
struct ChatTabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    @State private var segment = 0
    @State private var openChannelId: Int?
    @State private var openDmId: Int?

    private var segmentItems: [String] {
        [L10n.t("nav.channels"), L10n.t("nav.directMessages")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenTitle(text: L10n.t("nav.chat"))

            SegmentPill(items: segmentItems, selection: $segment)

            conversation
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            adopt(session.selectedChannelId)
        }
        .onChange(of: session.selectedChannelId) { _, selected in
            adopt(selected)
        }
    }

    @ViewBuilder
    private var conversation: some View {
        let openId = segment == 0 ? openChannelId : openDmId

        if let openId {
            ChannelDetailView(channelId: openId)
                .id(openId)
        } else {
            EmptyStateView(
                symbol: "bubble.left.and.bubble.right",
                title: L10n.t("chat.pickTitle"),
                body_: L10n.t("chat.pickBody")
            )
            .frame(maxHeight: .infinity)
        }
    }

    /// routes a freshly selected conversation to the right segment so the tab always shows
    /// what the user just tapped.
    private func adopt(_ channelId: Int?) {
        guard let channelId, let channel = session.channel(for: channelId) else {
            return
        }

        if channel.isDm {
            openDmId = channelId
            segment = 1
        } else if channel.type == .text {
            openChannelId = channelId
            segment = 0
        }
    }
}
