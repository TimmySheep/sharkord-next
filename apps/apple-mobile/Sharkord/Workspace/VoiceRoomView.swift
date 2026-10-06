import SharkordCore
import SwiftUI

/// The voice tab: the live call for the channel the device is in, or the voice channel
/// picker when no call is active. The three call controls live in `VoiceControlsBar`
/// pinned under this screen.
struct VoiceTabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    var body: some View {
        if let channelId = voice.currentChannelId {
            VoiceRoomView(channelId: channelId)
        } else {
            picker
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(text: L10n.t("nav.voice"))

                if let banner = model.banner {
                    bannerView(banner)
                }

                if session.voiceChannels.isEmpty {
                    EmptyStateView(
                        symbol: "waveform",
                        title: L10n.t("voice.emptyRoom"),
                        body_: L10n.t("chat.pickBody")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    SectionLabel(icon: "waveform", text: L10n.t("nav.voiceChannels"))

                    ForEach(session.voiceChannels) { channel in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 13) {
                                Image(systemName: "waveform")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SharkordTheme.textSecondary)
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

                                Text("\(session.voiceParticipants(in: channel.id).count)")
                                    .font(.subheadline)
                                    .foregroundStyle(SharkordTheme.textSecondary)
                            }

                            SharkordPrimaryButton(title: L10n.t("voice.join"), symbol: "phone.fill") {
                                model.joinVoice(channel.id)
                            }
                        }
                        .sharkordCard(cornerRadius: 24, padding: 17)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func bannerView(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SharkordTheme.danger)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharkordCard(cornerRadius: 18)
    }
}

/// The live call screen for a voice channel: who is in it, what their mic/output state is,
/// and any incoming screen or camera streams. The microphone pill in the control bar is
/// disabled while the output is off, and the reason is spelled out here so the protection
/// reads as intentional.
struct VoiceRoomView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    let channelId: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let banner = model.banner {
                    bannerView(banner)
                }

                if !voice.canEnableMicrophone && isInThisCall {
                    micBlockedNote
                }

                participants

                if !voice.remoteVideoStreams.isEmpty {
                    RemoteStreamList()
                }

                if !isInThisCall {
                    SharkordPrimaryButton(title: L10n.t("voice.join"), symbol: "phone.fill") {
                        model.joinVoice(channelId)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScreenTitle(
                text: channelName,
                trailing: AnyView(StatusPill(text: L10n.t("members.online"), color: SharkordTheme.success))
            )

            Text(L10n.format("voice.memberCount", participantRows.count))
                .font(.subheadline)
                .foregroundStyle(SharkordTheme.textSecondary)
        }
    }

    private var channelName: String {
        session.channel(for: channelId)?.name ?? L10n.t("voice.call")
    }

    private var isInThisCall: Bool {
        voice.currentChannelId == channelId
    }

    private var participantRows: [VoiceParticipant] {
        session.voiceParticipants(in: channelId)
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeading(icon: "person.2", text: L10n.t("channel.currentMembers"))

                Spacer()

                Text("\(participantRows.count)")
                    .font(.body)
                    .foregroundStyle(SharkordTheme.textSecondary)
            }

            if participantRows.isEmpty {
                Text(L10n.t("voice.emptyRoom"))
                    .font(.subheadline)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 16) {
                    ForEach(participantRows) { participant in
                        participantRow(participant)
                    }
                }
            }
        }
        .sharkordCard(cornerRadius: 24)
    }

    private func participantRow(_ participant: VoiceParticipant) -> some View {
        let isSelf = participant.id == session.ownUserId

        return HStack(spacing: 12) {
            AvatarView(
                name: participant.user.name,
                diameter: 42,
                isSpeaking: isSelf && voice.microphoneOn
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(participant.user.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SharkordTheme.textPrimary)
                        .lineLimit(1)

                    if isSelf {
                        Text(L10n.t("voice.youTag"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SharkordTheme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(SharkordTheme.field, in: Capsule())
                    }
                }

                Text(stateText(participant.state))
                    .font(.footnote)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if participant.state.sharingScreen == true {
                Image(systemName: "rectangle.on.rectangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SharkordTheme.accentSoft)
                    .accessibilityLabel(L10n.t("voice.state.screenSharing"))
            }

            Image(systemName: participant.state.micMuted ? "mic.slash.fill" : "mic.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(participant.state.micMuted ? SharkordTheme.danger : SharkordTheme.success)
                .accessibilityHidden(true)

            Image(systemName: participant.state.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(participant.state.soundMuted ? SharkordTheme.danger : SharkordTheme.accentSoft)
                .accessibilityHidden(true)
        }
    }

    private var micBlockedNote: some View {
        Label {
            Text(L10n.t("voice.micBlocked"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "hand.raised.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SharkordTheme.danger)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharkordCard(cornerRadius: 18)
    }

    private func bannerView(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SharkordTheme.danger)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharkordCard(cornerRadius: 18)
    }

    private func stateText(_ state: VoiceUserState) -> String {
        if state.sharingScreen == true {
            return L10n.t("voice.state.screenSharing")
        }
        if state.soundMuted {
            return L10n.t("voice.state.deafened")
        }
        if state.micMuted {
            return L10n.t("voice.state.muted")
        }
        return L10n.t("voice.state.live")
    }
}

/// incoming video: remote screen shares and cameras, labelled by owner and kind.
struct RemoteStreamList: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(
                icon: "rectangle.on.rectangle.fill",
                text: L10n.t("voice.remoteStreams"),
                tint: SharkordTheme.accentSoft
            )

            ForEach(voice.remoteVideoStreams) { stream in
                RemoteVideoView(track: stream.track)
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text(streamLabel(stream))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(10)
                    }
            }
        }
        .sharkordCard(cornerRadius: 24)
    }

    private func streamLabel(_ stream: RemoteVideoStream) -> String {
        let name = session.user(for: stream.remoteId)?.name ?? L10n.t("message.unknownAuthor")
        let kind = stream.kind == .screen || stream.kind == .screenAudio
            ? L10n.t("voice.screen.start")
            : L10n.t("voice.remoteCamera")
        return "\(name) · \(kind)"
    }
}
