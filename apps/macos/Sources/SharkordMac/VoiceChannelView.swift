import SharkordCore
import SwiftUI

/// The voice channel screen. The whole control plane is real here: join, leave, mute and
/// deafen state, webcam and screen share flags, reactions and moderator moves all go
/// through the same tRPC procedures the web client uses. Moving actual media still needs a
/// WebRTC stack, which is the one gap left (documented in apps/README.md).
struct VoiceChannelView: View {
    @EnvironmentObject private var session: SharkordSession

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

            if joined {
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
                    Task {
                        _ = try? await session.joinVoice(channelId: channel.id)
                    }
                } label: {
                    Label(L10n.t("joinVoice", ns: "macos"), systemImage: "phone.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(L10n.t("voiceNoPermission", ns: "macos"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(L10n.t("voiceMediaMissing", ns: "macos"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

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

                        Text(entry.user.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
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
            controlButton(
                micMuted ? "mic.slash.fill" : "mic.fill",
                active: micMuted,
                help: micMuted ? "Unmute microphone" : "Mute microphone"
            ) {
                Task { try? await session.updateVoiceState(micMuted: !micMuted) }
            }

            controlButton(
                deafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
                active: deafened,
                help: deafened ? "Undeafen" : "Deafen"
            ) {
                Task {
                    if deafened {
                        try? await session.updateVoiceState(soundMuted: false)
                    } else {
                        try? await session.updateVoiceState(micMuted: true, soundMuted: true)
                    }
                }
            }

            if session.hasPermission(.enableWebcam),
               session.hasChannelPermission(channel.id, .webcam) {
                controlButton(
                    ownState?.webcamEnabled == true ? "video.fill" : "video.slash",
                    active: ownState?.webcamEnabled == true,
                    help: "Toggle webcam"
                ) {
                    Task {
                        try? await session.updateVoiceState(webcamEnabled: ownState?.webcamEnabled != true)
                    }
                }
            }

            if session.hasPermission(.shareScreen),
               session.hasChannelPermission(channel.id, .shareScreen) {
                controlButton(
                    "rectangle.dashed.badge.record",
                    active: ownState?.sharingScreen == true,
                    help: "Toggle screen share"
                ) {
                    Task {
                        try? await session.updateVoiceState(sharingScreen: ownState?.sharingScreen != true)
                    }
                }
            }

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
                Task { try? await session.leaveVoice() }
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
}
