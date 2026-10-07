import SharkordCore
import SwiftUI

struct WatchMessagesView: View {
    @EnvironmentObject private var session: SharkordSession
    @State private var draft = ""
    @State private var replyTo: SharkordMessage?
    @State private var sendError: String?

    let channelId: Int
    let channelName: String

    private let quickEmojis = ["👍", "❤️", "😂", "🎉", "🙏"]

    private var messages: [SharkordMessage] {
        (session.messagesByChannel[channelId] ?? [])
            .filter { $0.parentMessageId == nil }
            .suffix(24)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(channelName)
                .font(.headline)
                .lineLimit(1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            Text(L10n.t("watch.emptyMessages"))
                                .font(.caption)
                                .foregroundStyle(WatchTheme.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 90)
                        }

                        ForEach(messages) { message in
                            messageCard(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: messages.last?.id) { _, messageId in
                    guard let messageId else {
                        return
                    }
                    withAnimation {
                        proxy.scrollTo(messageId, anchor: .bottom)
                    }
                }
            }

            composer
        }
        .padding(.horizontal, 6)
        .task {
            await session.select(channelId: channelId)
        }
        .onChange(of: draft) { _, _ in
            session.signalTyping(channelId: channelId)
        }
    }

    private func messageCard(_ message: SharkordMessage) -> some View {
        WatchCard {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(message.userId.flatMap { session.user(for: $0)?.name } ?? L10n.t("watch.unknownUser"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WatchTheme.accentSoft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(messageDate(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                }

                if let preview = message.replyTo, let content = preview.content {
                    Text("↳ \(MessageHTML.toPlainText(content))")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                        .lineLimit(2)
                }

                let content = MessageHTML.toPlainText(message.content ?? "")
                if !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(WatchTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let files = message.files, !files.isEmpty {
                    ForEach(files) { file in
                        Label(file.originalName, systemImage: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(WatchTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                if !session.reactionGroups(for: message).isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(session.reactionGroups(for: message)) { group in
                                Button {
                                    toggleReaction(messageId: message.id, emoji: group.emoji)
                                } label: {
                                    Text("\(group.emoji) \(group.count)")
                                        .font(.caption2)
                                        .foregroundStyle(group.mine ? WatchTheme.accentSoft : WatchTheme.textPrimary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(WatchTheme.field, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        replyTo = message
                    } label: {
                        Label(L10n.t("watch.reply"), systemImage: "arrowshape.turn.up.left")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WatchTheme.textSecondary)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(quickEmojis, id: \.self) { emoji in
                                Button {
                                    toggleReaction(messageId: message.id, emoji: emoji)
                                } label: {
                                    Text(emoji)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 5) {
            if let replyTo {
                HStack(spacing: 4) {
                    Text(L10n.t("watch.replyingTo"))
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                    Text(replyTo.userId.flatMap { session.user(for: $0)?.name } ?? L10n.t("watch.unknownUser"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchTheme.accentSoft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        self.replyTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                TextField(L10n.t("watch.messagePlaceholder"), text: $draft)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(WatchTheme.field, in: Capsule())

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WatchTheme.textSecondary : WatchTheme.accentSoft)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 9) {
                ForEach(quickEmojis, id: \.self) { emoji in
                    Button(emoji) {
                        draft.append(emoji)
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            if let sendError {
                Text(sendError)
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.danger)
                    .lineLimit(2)
            }
        }
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        let replyId = replyTo?.id
        draft = ""
        replyTo = nil
        sendError = nil

        Task {
            do {
                try await session.sendMessage(text, channelId: channelId, replyToMessageId: replyId)
            } catch {
                sendError = error.localizedDescription
                draft = text
            }
        }
    }

    private func toggleReaction(messageId: Int, emoji: String) {
        Task {
            do {
                try await session.toggleReaction(messageId: messageId, emoji: emoji)
            } catch {
                sendError = error.localizedDescription
            }
        }
    }

    private func messageDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        return date.formatted(date: .omitted, time: .shortened)
    }
}
