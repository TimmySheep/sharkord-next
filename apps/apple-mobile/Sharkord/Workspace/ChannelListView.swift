import SharkordCore
import SwiftUI

/// Sidebar: direct messages, text channels grouped by category, and voice channels with
/// live member rows. Everything is real session state, unread counts included.
struct ChannelListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            List {
                if !session.directMessageChannels.isEmpty {
                    Section(L10n.t("nav.directMessages")) {
                        ForEach(session.directMessageChannels) { channel in
                            row(for: channel, showsTopic: true)
                        }
                    }
                }

                ForEach(session.categories) { category in
                    let channels = session.channels(in: category)

                    if !channels.isEmpty {
                        Section(category.name) {
                            ForEach(channels) { channel in
                                row(for: channel, showsTopic: true)
                            }
                        }
                    }
                }

                if !session.voiceChannels.isEmpty {
                    Section(L10n.t("nav.voiceChannels")) {
                        ForEach(session.voiceChannels) { channel in
                            voiceChannelRow(channel)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(session.serverName)
            .navigationDestination(for: Int.self) { channelId in
                ChannelDetailView(channelId: channelId)
            }
        }
    }

    /// On iPhone the row pushes onto the navigation stack; on iPad it selects into the
    /// split view detail instead.
    @ViewBuilder
    private func row(for channel: SharkordChannel, showsTopic: Bool) -> some View {
        let label = channelLabel(channel, showsTopic: showsTopic)

        if horizontalSizeClass == .regular {
            Button {
                model.selectChannel(channel.id)
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: channel.id) {
                label
            }
        }
    }

    private func channelLabel(_ channel: SharkordChannel, showsTopic: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: iconName(for: channel))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.isDm ? dmName(for: channel) : channel.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                if showsTopic, let topic = channel.topic, !topic.isEmpty {
                    Text(topic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if channel.type == .voice, session.isInVoice(channel.id) {
                Image(systemName: "phone.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityLabel(L10n.t("voice.state.joined"))
            }

            if let unread = session.unreadByChannel[channel.id], unread > 0 {
                Text("\(unread)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.sharkordBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 2)
    }

    private func iconName(for channel: SharkordChannel) -> String {
        if channel.isDm {
            return "person.crop.circle"
        }
        return channel.type == .voice ? "waveform" : "number"
    }

    private func voiceChannelRow(_ channel: SharkordChannel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row(for: channel, showsTopic: false)

            ForEach(session.voiceParticipants(in: channel.id)) { entry in
                HStack(spacing: 9) {
                    AvatarView(name: entry.user.name, diameter: 24)

                    Text(entry.user.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if entry.state.micMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(L10n.t("voice.state.muted"))
                    }

                    if entry.state.soundMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(L10n.t("voice.state.deafened"))
                    }

                    if entry.state.sharingScreen == true {
                        Image(systemName: "rectangle.on.rectangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.sharkordBlueSoft)
                            .accessibilityLabel(L10n.t("voice.state.screenSharing"))
                    }
                }
                .padding(.leading, 33)
            }
        }
        .padding(.vertical, 2)
    }

    private func dmName(for channel: SharkordChannel) -> String {
        guard let partner = session.directMessagePartner(for: channel) else {
            return channel.name
        }
        return partner.name
    }
}
