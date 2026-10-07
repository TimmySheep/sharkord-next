import SwiftUI

/// Channel list: the entry to a radio session. Tapping a channel opens the room and
/// joins; leaving the room ends the session.
struct WatchChannelListView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(L10n.t("nav.channels"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(model.channels) { channel in
                    NavigationLink(value: channel.id) {
                        WatchCard {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .foregroundStyle(WatchTheme.accentSoft)
                                    Text(channel.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(WatchTheme.textPrimary)
                                }
                                Text(channel.topic)
                                    .font(.caption2)
                                    .foregroundStyle(WatchTheme.textSecondary)
                                Text(L10n.format("voice.memberCount", channel.participants.count))
                                    .font(.caption2)
                                    .foregroundStyle(WatchTheme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive) {
                    model.disconnect()
                } label: {
                    Text(L10n.t("settings.disconnect"))
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationDestination(for: String.self) { channelId in
            WatchRoomView(channelId: channelId)
        }
    }
}
