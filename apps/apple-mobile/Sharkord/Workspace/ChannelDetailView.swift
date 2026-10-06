import SwiftUI

/// renders whichever channel is open: a text channel with a message list and composer, or a voice
/// channel with its member roster. both are driven from `AppModel`, so swapping the sample data for a
/// protocol client does not change this view's shape.
struct ChannelDetailView: View {
    @ObservedObject var model: AppModel
    let channelID: String
    @State private var draft = ""

    private var channel: ServerChannel? {
        model.channel(withID: channelID)
    }

    var body: some View {
        Group {
            if let channel {
                switch channel.kind {
                case .text:
                    textChannel(channel)
                case .voice:
                    voiceChannel(channel)
                }
            } else {
                missingChannel
            }
        }
        .background(BrandBackground())
        .navigationTitle(channel?.name ?? "频道")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func textChannel(_ channel: ServerChannel) -> some View {
        VStack(spacing: 0) {
            OfflineNotice()
                .padding(.horizontal, 16)
                .padding(.top, 10)

            messageList(channel)

            composer(channel)
        }
    }

    private func messageList(_ channel: ServerChannel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(channel.topic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)

                ForEach(model.messagesByChannel[channel.id] ?? []) { message in
                    messageRow(message)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.bottom)
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let name = authorName(for: message)

        return HStack(alignment: .top, spacing: 11) {
            AvatarView(name: name, diameter: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))

                    Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }

                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.7)
        }
    }

    private func composer(_ channel: ServerChannel) -> some View {
        HStack(spacing: 10) {
            TextField("在 #\(channel.name) 中发言", text: $draft)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
                }
                .onSubmit(sendDraft)

            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(canSend ? Color.sharkordBlue : Color.secondary)
            }
            .disabled(!canSend)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        model.send(draft, to: channelID)
        draft = ""
    }

    private func voiceChannel(_ channel: ServerChannel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OfflineNotice()

                VStack(alignment: .leading, spacing: 8) {
                    Text(channel.topic)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(channel.voiceMemberIDs.count) 人在线")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                    spacing: 18
                ) {
                    ForEach(channel.voiceMemberIDs, id: \.self) { memberID in
                        voiceTile(memberID)
                    }
                }

                SharkordPrimaryButton(
                    title: "语音尚未接入",
                    symbol: "speaker.wave.2",
                    enabled: false,
                    action: {}
                )
                .accessibilityHint("语音依赖 mediasoup 客户端，属于第二阶段")

                Text("本阶段只搭界面骨架，语音频道尚未建立 WebRTC 连接。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func voiceTile(_ memberID: String) -> some View {
        let member = model.member(withID: memberID)

        return VStack(spacing: 7) {
            AvatarView(
                name: member?.name ?? "?",
                diameter: 54,
                isSpeaking: member?.isSpeaking ?? false
            )

            Text(member?.name ?? "未知用户")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var missingChannel: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("频道不存在")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func authorName(for message: ChatMessage) -> String {
        if message.authorID == "local" {
            return model.accountDisplayName
        }
        return model.member(withID: message.authorID)?.name ?? "未知用户"
    }
}
