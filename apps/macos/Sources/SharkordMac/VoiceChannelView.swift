import AppKit
import SharkordCore
import SwiftUI

/// The voice channel screen. The whole control plane is real here: join, leave, mute and
/// deafen state, webcam media, reactions and moderator moves all use the server voice routes.
struct VoiceChannelView: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voiceMedia: VoiceMediaController

    let channel: SharkordChannel

    private var joined: Bool {
        session.isInVoice(channel.id)
    }

    private var participants: [(user: SharkordUser, state: VoiceUserState)] {
        session.voiceUsers(in: channel.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VoiceMediaHost(controller: voiceMedia)
                .frame(maxWidth: .infinity)
                .frame(height: joined ? 220 : 1)
                .opacity(joined ? 1 : 0.01)

            if joined && voiceMedia.status == "connected" {
                if let errorMessage = voiceMedia.errorMessage {
                    HStack(spacing: 10) {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)

                        if voiceMedia.errorContext == "microphone" ||
                            voiceMedia.errorContext == "camera" ||
                            voiceMedia.errorContext == "screenShare" {
                            Button(L10n.t("openSystemSettings", ns: "macos"), action: openMediaPrivacySettings)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }

                participantGrid
                Divider()
                controls
            } else {
                joinPrompt
            }
        }
        .background(Theme.panel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.secondary)

            Text(channel.name)
                .font(.headline)

            if let topic = channel.topic, !topic.isEmpty {
                Divider().frame(height: 16)

                Text(topic)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(participants.count) connected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var joinPrompt: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 42))
                .foregroundStyle(Theme.accent)

            Text(channel.name)
                .font(.title2.bold())

            if session.hasPermission(.joinVoiceChannels),
               session.hasChannelPermission(channel.id, .join) {
                Button {
                    connectVoice()
                } label: {
                    Label(L10n.t("joinVoice", ns: "macos"), systemImage: "phone.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(voiceMedia.status == "connecting")
            } else {
                Text(L10n.t("voiceNoPermission", ns: "macos"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if voiceMedia.status == "connecting" {
                ProgressView(L10n.t("voiceConnecting", ns: "macos"))
                    .controlSize(.small)
            }

            if let errorMessage = voiceMedia.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var participantGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                spacing: 10
            ) {
                ForEach(participants, id: \.user.id) { entry in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(user: entry.user, size: 56)

                            HStack(spacing: 2) {
                                if entry.state.micMuted {
                                    Image(systemName: "mic.slash.fill")
                                        .foregroundStyle(.red)
                                }

                                if entry.state.soundMuted == true {
                                    Image(systemName: "speaker.slash.fill")
                                        .foregroundStyle(.red)
                                }

                                if entry.state.sharingScreen == true {
                                    Image(systemName: "rectangle.dashed.badge.record")
                                        .foregroundStyle(Theme.accent)
                                }

                                if entry.state.webcamEnabled == true {
                                    Image(systemName: "video.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .font(.system(size: 9))
                            .padding(3)
                            .background(Theme.elevated, in: Circle())
                        }

                        HStack(spacing: 5) {
                            Text(entry.user.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)

                            if entry.user.id != session.ownUserId {
                                VoiceParticipantVolumeButton(
                                    userId: entry.user.id,
                                    stream: .user
                                )

                                if hasScreenShareAudio(for: entry.user.id) {
                                    VoiceParticipantVolumeButton(
                                        userId: entry.user.id,
                                        stream: .screenShare
                                    )
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
                    .contextMenu {
                        if session.hasPermission(.moveMembers) {
                            Menu("Move to") {
                                ForEach(session.voiceChannels.filter { $0.id != channel.id }) { target in
                                    Button(target.name) {
                                        Task {
                                            try? await session.moveUser(userId: entry.user.id, to: target.id)
                                        }
                                    }
                                }
                            }
                        }

                        Button(L10n.t("openDirectMessages", ns: "sidebar")) {
                            Task {
                                try? await session.openDirectMessage(userId: entry.user.id)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if session.hasChannelPermission(channel.id, .speak) {
                controlButton(
                    micMuted ? "mic.slash.fill" : "mic.fill",
                    active: micMuted,
                    help: L10n.t(micMuted ? "unmuteMic" : "muteMic", ns: "macos")
                ) {
                    Task {
                        do {
                            try await voiceMedia.setMicrophoneMuted(!micMuted)
                        } catch {
                            voiceMedia.presentError(error, context: "microphone")
                        }
                    }
                }
                .disabled(voiceMedia.status != "connected" || deafened)
            }

            if session.hasPermission(.enableWebcam),
               session.hasChannelPermission(channel.id, .webcam) {
                controlButton(
                    ownState?.webcamEnabled == true ? "video.fill" : "video.slash",
                    active: ownState?.webcamEnabled == true,
                    help: L10n.t("toggleWebcam", ns: "macos")
                ) {
                    Task {
                        do {
                            try await voiceMedia.setWebcamEnabled(ownState?.webcamEnabled != true)
                        } catch {
                            voiceMedia.presentError(error, context: "camera")
                        }
                    }
                }
                .disabled(voiceMedia.status != "connected")
            }

            controlButton(
                deafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
                active: deafened,
                help: deafened ? "Undeafen" : "Deafen"
            ) {
                Task {
                    do {
                        try await voiceMedia.setOutputMuted(!deafened)
                    } catch {
                        voiceMedia.presentError(error, context: "audio")
                    }
                }
            }
            .disabled(voiceMedia.status != "connected")

            if session.hasPermission(.sendVoiceReaction) {
                Menu {
                    ForEach(["👍", "❤️", "😂", "🎉", "👀", "🔥"], id: \.self) { emoji in
                        Button(emoji) {
                            Task { try? await session.sendVoiceReaction(emoji: emoji) }
                        }
                    }
                } label: {
                    Image(systemName: "face.smiling")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Send voice reaction")
            }

            Spacer()

            controlButton("phone.down.fill", active: true, help: "Leave voice") {
                leaveVoice()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func controlButton(
        _ systemName: String,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .background(active ? Theme.accent.opacity(0.25) : Theme.elevated, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Theme.accent : .secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    private var ownState: VoiceUserState? {
        session.voiceUsers(in: channel.id)
            .first { $0.user.id == session.ownUserId }?
            .state
    }

    private var micMuted: Bool {
        ownState?.micMuted ?? true
    }

    private var deafened: Bool {
        ownState?.soundMuted ?? false
    }

    private func hasScreenShareAudio(for userId: Int) -> Bool {
        session.producersByChannel[channel.id]?.contains {
            $0.remoteId == userId && $0.kind == .screenAudio
        } ?? false
    }

    private func connectVoice() {
        Task {
            do {
                if session.currentVoiceChannelId != nil {
                    voiceMedia.stop()
                    try await session.leaveVoice()
                }

                let result = try await session.joinVoice(channelId: channel.id, micMuted: true)
                let capabilities = result["routerRtpCapabilities"] ?? .null
                try await voiceMedia.start(
                    channelId: channel.id,
                    routerRtpCapabilities: capabilities,
                    canProduceAudio: session.hasChannelPermission(channel.id, .speak),
                    canShareScreen: session.hasPermission(.shareScreen) &&
                        session.hasChannelPermission(channel.id, .shareScreen),
                    screenShareLabels: [
                        "share": L10n.t("shareScreen", ns: "macos"),
                        "stop": L10n.t("stopScreenShare", ns: "macos"),
                        "local": L10n.t("mediaLocalUser", ns: "macos"),
                        "screen": L10n.t("mediaScreen", ns: "macos"),
                        "camera": L10n.t("mediaCamera", ns: "macos")
                    ]
                )
            } catch {
                try? await session.leaveVoice()
                voiceMedia.presentError(error)
            }
        }
    }

    private func leaveVoice() {
        voiceMedia.stop()
        Task {
            try? await session.leaveVoice()
        }
    }

    private func openMediaPrivacySettings() {
        let section: String

        switch voiceMedia.errorContext {
        case "microphone":
            section = "Privacy_Microphone"
        case "camera":
            section = "Privacy_Camera"
        case "screenShare":
            section = "Privacy_ScreenCapture"
        default:
            return
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct VoiceParticipantVolumeButton: View {
    @EnvironmentObject private var voiceMedia: VoiceMediaController

    let userId: Int
    let stream: VoiceAudioStream

    @State private var isPresented = false

    private var volume: Double {
        voiceMedia.remoteAudioVolume(for: userId, stream: stream)
    }

    private var title: String {
        let key = stream == .screenShare ? "screenShareAudioVolume" : "userVolume"
        return L10n.t(key, ns: "sidebar")
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(volume == 0 ? Color.red : Color.secondary)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue("\(volumePercentage)%")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    Button(action: toggleMute) {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 20)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t(volume == 0 ? "unmuteAudio" : "muteAudio", ns: "sidebar"))
                    .accessibilityLabel(L10n.t(volume == 0 ? "unmuteAudio" : "muteAudio", ns: "sidebar"))

                    Slider(value: volumeBinding, in: 0 ... 1, step: 0.01)
                        .accessibilityLabel(title)

                    Text("\(volumePercentage)%")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .padding(12)
            .frame(width: 230)
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { volume },
            set: { voiceMedia.setRemoteAudioVolume($0, for: userId, stream: stream) }
        )
    }

    private var volumePercentage: Int {
        Int((volume * 100).rounded())
    }

    private func toggleMute() {
        voiceMedia.toggleRemoteAudioMute(for: userId, stream: stream)
    }
}
