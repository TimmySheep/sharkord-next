import SharkordCore
import SwiftUI

/// The channels tab: search, direct messages, text channels grouped by category, voice
/// channels with live member rows, and the server member list. Everything is real session
/// state, unread counts included.
struct ChannelListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    var onOpenTextChannel: ((Int) -> Void)?
    var onOpenVoiceChannel: ((Int) -> Void)?

    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(text: L10n.t("nav.channels"))

                searchField

                if !dmChannels.isEmpty {
                    section(icon: "person.crop.circle", title: L10n.t("nav.directMessages")) {
                        ForEach(dmChannels) { channel in
                            textChannelRow(channel)
                        }
                    }
                }

                ForEach(session.categories) { category in
                    let channels = textChannels(in: category)

                    if !channels.isEmpty {
                        section(icon: "square.grid.2x2", title: category.name) {
                            ForEach(channels) { channel in
                                textChannelRow(channel)
                            }
                        }
                    }
                }

                if !voiceChannels.isEmpty {
                    section(icon: "waveform", title: L10n.t("nav.voiceChannels")) {
                        ForEach(voiceChannels) { channel in
                            voiceChannelCard(channel)
                        }
                    }
                }

                MembersSection(query: query)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(SharkordTheme.textSecondary)
                .accessibilityHidden(true)

            TextField("", text: $query, prompt: Text(L10n.t("channel.searchPlaceholder")).foregroundColor(SharkordTheme.textSecondary))
                .font(.body)
                .foregroundStyle(SharkordTheme.textPrimary)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .tint(SharkordTheme.accentSoft)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .background(SharkordTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func section(
        icon: String,
        title: String,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: icon, text: title)
            rows()
        }
    }

    // MARK: filtering

    private var dmChannels: [SharkordChannel] {
        session.directMessageChannels.filter(matches)
    }

    private func textChannels(in category: SharkordCategory) -> [SharkordChannel] {
        session.channels(in: category).filter { $0.type == .text && matches($0) }
    }

    private var voiceChannels: [SharkordChannel] {
        session.voiceChannels.filter(matches)
    }

    private func matches(_ channel: SharkordChannel) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        if channel.name.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let topic = channel.topic, topic.localizedCaseInsensitiveContains(query) {
            return true
        }
        return channel.isDm && (session.directMessagePartner(for: channel)?.name ?? "")
            .localizedCaseInsensitiveContains(query)
    }

    // MARK: rows

    private func textChannelRow(_ channel: SharkordChannel) -> some View {
        Button {
            open(channel)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: channel.isDm ? "person.crop.circle" : "number")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.isDm ? dmName(for: channel) : channel.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SharkordTheme.textPrimary)
                        .lineLimit(1)

                    if let topic = channel.topic, !topic.isEmpty {
                        Text(topic)
                            .font(.footnote)
                            .foregroundStyle(SharkordTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let unread = session.unreadByChannel[channel.id], unread > 0 {
                    Text("\(unread)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SharkordTheme.accent, in: Capsule())
                }
            }
            .sharkordCard(cornerRadius: 22, padding: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(channel.isDm ? dmName(for: channel) : channel.name)
    }

    private func voiceChannelCard(_ channel: SharkordChannel) -> some View {
        let joined = session.isInVoice(channel.id)
        let participants = session.voiceParticipants(in: channel.id)

        return Button {
            open(channel)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 13) {
                    Image(systemName: "waveform")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(joined ? SharkordTheme.accentSoft : SharkordTheme.textSecondary)
                        .frame(width: 26)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(channel.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SharkordTheme.textPrimary)
                            .lineLimit(1)

                        if let topic = channel.topic, !topic.isEmpty {
                            Text(topic)
                                .font(.footnote)
                                .foregroundStyle(SharkordTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text("\(participants.count)")
                        .font(.subheadline)
                        .foregroundStyle(SharkordTheme.textSecondary)

                    if joined {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SharkordTheme.accent)
                            .accessibilityLabel(L10n.t("voice.state.joined"))
                    }
                }

                if joined && !participants.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(participants) { participant in
                            voiceParticipantRow(participant)
                        }
                    }
                    .padding(.leading, 39)
                }
            }
            .sharkordCard(cornerRadius: 24, padding: 17)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(channel.name)
    }

    private func voiceParticipantRow(_ participant: VoiceParticipant) -> some View {
        HStack(spacing: 11) {
            AvatarView(name: participant.user.name, diameter: 34)

            Text(participant.user.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if participant.state.micMuted {
                Image(systemName: "mic.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(SharkordTheme.danger)
                    .accessibilityLabel(L10n.t("voice.state.muted"))
            }

            if participant.state.soundMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(SharkordTheme.danger)
                    .accessibilityLabel(L10n.t("voice.state.deafened"))
            }

            if participant.state.sharingScreen == true {
                Image(systemName: "rectangle.on.rectangle.fill")
                    .font(.footnote)
                    .foregroundStyle(SharkordTheme.accentSoft)
                    .accessibilityLabel(L10n.t("voice.state.screenSharing"))
            }
        }
    }

    private func open(_ channel: SharkordChannel) {
        if channel.type == .voice {
            model.selectChannel(channel.id)
            onOpenVoiceChannel?(channel.id)
        } else {
            model.selectChannel(channel.id)
            onOpenTextChannel?(channel.id)
        }
    }

    private func dmName(for channel: SharkordChannel) -> String {
        guard let partner = session.directMessagePartner(for: channel) else {
            return channel.name
        }
        return partner.name
    }
}
