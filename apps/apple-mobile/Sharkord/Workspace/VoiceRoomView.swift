import SharkordCore
import SwiftUI

/// The screen for a voice channel: who is in it, what their mic/output state is, and the
/// call controls. The microphone control is disabled while the output is off, and the
/// reason is spelled out so the protection reads as intentional.
struct VoiceRoomView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voice: VoiceEngine

    let channelId: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !voice.remoteVideoStreams.isEmpty {
                    remoteStreams
                }
                participants
                controls
            }
            .padding(18)
        }
    }

    private var remoteStreams: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionEyebrow(title: L10n.t("voice.remoteStreams"))

            ForEach(voice.remoteVideoStreams) { stream in
                RemoteVideoView(track: stream.track)
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
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
    }

    private func streamLabel(_ stream: RemoteVideoStream) -> String {
        let name = session.user(for: stream.remoteId)?.name ?? L10n.t("message.unknownAuthor")
        let kind = stream.kind == .screen || stream.kind == .screenAudio
            ? L10n.t("voice.screen.start")
            : L10n.t("voice.remoteCamera")
        return "\(name) · \(kind)"
    }

    private var isInThisCall: Bool {
        voice.currentChannelId == channelId
    }

    private var participantRows: [VoiceParticipant] {
        session.voiceParticipants(in: channelId)
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionEyebrow(title: L10n.t("voice.participants"))

            if participantRows.isEmpty {
                Text(L10n.t("voice.emptyRoom"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(participantRows) { participant in
                    HStack(spacing: 11) {
                        AvatarView(
                            name: participant.user.name,
                            diameter: 34,
                            isSpeaking: participant.id == session.ownUserId && voice.microphoneOn
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(participant.user.name)
                                .font(.subheadline.weight(.medium))

                            Text(stateText(participant.state))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 6)

                        Image(systemName: participant.state.micMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.subheadline)
                            .foregroundStyle(participant.state.micMuted ? Color.secondary : Color.green)
                            .accessibilityHidden(true)

                        Image(systemName: participant.state.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(participant.state.soundMuted ? Color.orange : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(11)
                    .sharkordGlassCard(cornerRadius: 17)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title: L10n.t("voice.controls"))

            if !isInThisCall {
                SharkordPrimaryButton(title: L10n.t("voice.join"), symbol: "phone.fill") {
                    model.joinVoice(channelId)
                }
            } else {
                HStack(spacing: 11) {
                    controlTile(
                        title: voice.microphoneOn ? L10n.t("voice.mic.mute") : L10n.t("voice.mic.unmute"),
                        symbol: voice.microphoneOn ? "mic.fill" : "mic.slash.fill",
                        tint: voice.microphoneOn ? .green : .primary,
                        disabled: !voice.canEnableMicrophone
                    ) {
                        model.toggleMicrophone()
                    }

                    controlTile(
                        title: voice.deafened ? L10n.t("voice.output.enable") : L10n.t("voice.output.disable"),
                        symbol: voice.deafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        tint: voice.deafened ? .orange : .primary,
                        disabled: false
                    ) {
                        model.toggleDeafen()
                    }

                    controlTile(
                        title: voice.screenSharing ? L10n.t("voice.screen.stop") : L10n.t("voice.screen.start"),
                        symbol: voice.screenSharing ? "rectangle.slash.fill" : "rectangle.on.rectangle.fill",
                        tint: voice.screenSharing ? .sharkordBlueSoft : .primary,
                        disabled: false
                    ) {
                        model.toggleScreenShare()
                    }
                }

                if !voice.canEnableMicrophone {
                    Label {
                        Text(L10n.t("voice.micBlocked"))
                            .font(.footnote.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sharkordGlassCard(cornerRadius: 16)
                }

                SharkordPrimaryButton(title: L10n.t("voice.leave"), symbol: "phone.down.fill") {
                    model.leaveVoice()
                }
            }

            if let banner = model.banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func controlTile(
        title: String,
        symbol: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))

                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
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
