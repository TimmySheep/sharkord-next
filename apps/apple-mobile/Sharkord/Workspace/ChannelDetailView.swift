import SharkordCore
import SwiftUI

/// The open conversation: the message list with its composer for text channels, the voice
/// room panel for voice channels. Messages, unread state, typing indicators and reactions
/// all come from the live session.
struct ChannelDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    let channelId: Int

    @State private var draft = ""
    @State private var replyTo: SharkordMessage?
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let channel = session.channel(for: channelId), channel.type == .voice {
                VoiceRoomView(channelId: channelId)
            } else {
                messageScreen
            }
        }
        .navigationTitle(channelTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.selectChannel(channelId)
        }
    }

    private var messageScreen: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if session.hasMoreOlderByChannel[channelId] == true {
                        Button {
                            Task { await session.loadOlder(channelId: channelId) }
                        } label: {
                            Text(L10n.t("channel.loadOlder"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(SharkordTheme.accentSoft)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 9)
                    }

                    let messages = session.messagesByChannel[channelId] ?? []

                    if messages.isEmpty && session.hasMoreOlderByChannel[channelId] != true {
                        emptyState
                    }

                    ForEach(messages) { message in
                        MessageRow(message: message) { reply in
                            replyTo = reply
                            composerFocused = true
                        }
                        .id(message.id)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: session.messagesByChannel[channelId]?.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "bubble.left.and.bubble.right",
            title: L10n.t("chat.emptyTitle"),
            body_: L10n.t("chat.emptyBody")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTo {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(SharkordTheme.accentSoft)

                    Text(MessageText.plainText(fromHTML: replyTo.content))
                        .font(.caption)
                        .foregroundStyle(SharkordTheme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        self.replyTo = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SharkordTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
            }

            if !typingNames.isEmpty {
                Text(L10n.format("channel.typing", typingNames))
                    .font(.caption)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .padding(.horizontal, 18)
            }

            HStack(spacing: 10) {
                TextField(L10n.t("channel.messagePlaceholder"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.body)
                    .foregroundStyle(SharkordTheme.textPrimary)
                    .textFieldStyle(.plain)
                    .tint(SharkordTheme.accentSoft)
                    .focused($composerFocused)
                    .onChange(of: draft) { _, _ in
                        session.signalTyping(channelId: channelId)
                    }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            canSend ? SharkordTheme.accent : SharkordTheme.pillNeutral,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SharkordTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var typingNames: String {
        session.typingUsers(in: channelId).map(\.name).joined(separator: ", ")
    }

    private var channelTitle: String {
        guard let channel = session.channel(for: channelId) else {
            return ""
        }
        return channel.isDm ? (session.directMessagePartner(for: channel)?.name ?? channel.name) : "#\(channel.name)"
    }

    private func send() {
        let text = draft
        let reply = replyTo
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        draft = ""
        replyTo = nil

        Task {
            do {
                try await session.sendMessage(
                    text,
                    channelId: channelId,
                    replyToMessageId: reply?.id
                )
            } catch {
                model.banner = error.localizedDescription
            }
        }
    }
}
