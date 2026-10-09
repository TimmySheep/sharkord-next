import SharkordCore
import SwiftUI

/// the voice channel picker used by the channel workspace.
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

                if !isInThisCall {
                    SharkordPrimaryButton(title: L10n.t("voice.join"), symbol: "phone.fill") {
                        model.joinVoice(channelId)
                    }
                }

                participants

                cameraControls

                ScreenShareControls(channelId: channelId)

                if !voice.remoteVideoStreams.isEmpty {
                    RemoteStreamList()
                }

            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        Group {
            if let topic = session.channel(for: channelId)?.topic, !topic.isEmpty {
                Text(topic)
                    .font(.subheadline)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                Text(L10n.t("channel.currentMembers"))
                    .font(.headline)
                    .foregroundStyle(SharkordTheme.textPrimary)

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
                LazyVGrid(columns: participantColumns, spacing: 12) {
                    ForEach(participantRows) { participant in
                        participantTile(participant)
                    }
                }
            }
        }
    }

    private var participantColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top)]
    }

    private func participantTile(_ participant: VoiceParticipant) -> some View {
        let isSelf = participant.id == session.ownUserId

        return VStack(spacing: 10) {
            AvatarView(
                name: participant.user.name,
                diameter: 68,
                isSpeaking: isSelf && voice.microphoneOn,
                imageURL: participant.user.avatar.flatMap(session.publicFileURL(for:))
            )

            HStack(spacing: 6) {
                Text(participant.user.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textPrimary)
                    .lineLimit(1)

                if isSelf {
                    Text(L10n.t("voice.youTag"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SharkordTheme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: participant.state.micMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(participant.state.micMuted ? SharkordTheme.danger : SharkordTheme.success)

                if participant.state.sharingScreen == true {
                    Image(systemName: "rectangle.on.rectangle.fill")
                        .foregroundStyle(SharkordTheme.accentSoft)
                        .accessibilityLabel(L10n.t("voice.state.screenSharing"))
                }

                Text(stateText(participant.state))
                    .font(.caption)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 144)
        .padding(12)
        .background(SharkordTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var cameraControls: some View {
        let canUseCamera = session.hasPermission(.enableWebcam) &&
            session.hasChannelPermission(channelId, .webcam)

        return VStack(alignment: .leading, spacing: 12) {
            CardHeading(
                icon: "video.fill",
                text: L10n.t("voice.camera.title"),
                tint: SharkordTheme.accentSoft
            )

            HStack(spacing: 12) {
                Button {
                    model.toggleCamera()
                } label: {
                    Label(
                        L10n.t(voice.cameraOn ? "voice.camera.stop" : "voice.camera.start"),
                        systemImage: voice.cameraOn ? "video.slash.fill" : "video.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(voice.cameraOn ? SharkordTheme.danger : SharkordTheme.accent)
                .disabled(!isInThisCall || voice.cameraStarting || (!canUseCamera && !voice.cameraOn))

                if voice.cameraOn {
                    Button {
                        model.switchCamera()
                    } label: {
                        Label(L10n.t("voice.camera.switch"), systemImage: "camera.rotate.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if voice.cameraOn, let track = voice.localCameraTrack {
                RemoteVideoView(track: track)
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text(L10n.t("voice.youTag"))
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
                    .overlay(alignment: .topTrailing) {
                        if !stream.qualityLayers.isEmpty {
                            Menu {
                                Button(L10n.t("voice.quality.auto")) {
                                    Task { await voice.setQuality(for: stream, spatialLayer: nil) }
                                }
                                ForEach(stream.qualityLayers, id: \.spatialLayer) { layer in
                                    Button(layer.label) {
                                        Task {
                                            await voice.setQuality(
                                                for: stream,
                                                spatialLayer: layer.spatialLayer
                                            )
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(.black.opacity(0.55), in: Circle())
                                    .padding(10)
                            }
                        }
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
