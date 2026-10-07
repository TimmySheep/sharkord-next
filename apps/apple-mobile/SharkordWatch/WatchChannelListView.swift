import SwiftUI
import SharkordCore

/// lists live text, voice and direct-message channels from the connected server.
struct WatchChannelListView: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var model: WatchSessionModel
    @State private var searchText = ""

    private var channels: [SharkordChannel] {
        session.channels.filter { channel in
            searchText.isEmpty || channel.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(L10n.t("nav.channels"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField(L10n.t("channel.searchPlaceholder"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(WatchTheme.field, in: RoundedRectangle(cornerRadius: WatchTheme.fieldCorner, style: .continuous))

                let regular = channels.filter { !$0.isDm }
                ForEach(session.categories) { category in
                    let categoryChannels = regular
                        .filter { $0.categoryId == category.id }
                        .sorted { $0.position < $1.position }
                    if !categoryChannels.isEmpty {
                        section(category.name, channels: categoryChannels)
                    }
                }

                let uncategorized = regular
                    .filter { $0.categoryId == nil }
                    .sorted { $0.position < $1.position }
                if !uncategorized.isEmpty {
                    section(L10n.t("watch.otherChannels"), channels: uncategorized)
                }

                let directMessages = channels.filter(\.isDm)
                if !directMessages.isEmpty {
                    section(L10n.t("nav.directMessages"), channels: directMessages)
                }

                Button(role: .destructive) {
                    Task {
                        await model.disconnect()
                    }
                } label: {
                    Text(L10n.t("settings.disconnect"))
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func section(_ title: String, channels: [SharkordChannel]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(channels) { channel in
                NavigationLink {
                    destination(for: channel)
                } label: {
                    channelCard(channel)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func channelCard(_ channel: SharkordChannel) -> some View {
        WatchCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: channel.type == .voice ? "dot.radiowaves.left.and.right" : "number")
                        .foregroundStyle(WatchTheme.accentSoft)
                    Text(channel.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let unread = session.unreadByChannel[channel.id], unread > 0 {
                        Text("\(unread)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WatchTheme.accent, in: Capsule())
                    }
                }

                if let topic = channel.topic, !topic.isEmpty {
                    Text(topic)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                        .lineLimit(2)
                }

                if channel.type == .voice {
                    Text(L10n.format("voice.memberCount", session.voiceUsers(in: channel.id).count))
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for channel: SharkordChannel) -> some View {
        if channel.type == .voice {
            WatchRoomView(channelId: channel.id)
        } else {
            WatchMessagesView(channelId: channel.id, channelName: channel.name)
        }
    }
}
