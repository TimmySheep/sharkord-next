import SharkordCore
import SwiftUI

/// The thread sidebar: the parent message, its replies and a composer scoped to the thread.
struct ThreadSidebarView: View {
    @EnvironmentObject private var session: SharkordSession

    let messageId: Int
    var onClose: () -> Void

    @State private var parent: SharkordMessage?
    @State private var replyTarget: SharkordMessage?
    @State private var editing: SharkordMessage?

    private var replies: [SharkordMessage] {
        session.threadMessages(for: messageId)
    }

    private var channel: SharkordChannel? {
        session.channel(for: parent?.channelId ?? session.selectedChannelId ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let parent {
                        MessageRowView(
                            message: parent,
                            grouped: false,
                            onReply: { replyTarget = $0 },
                            onEdit: { editing = $0 },
                            onOpenThread: { _ in }
                        )

                        Divider().padding(.vertical, 6)
                    }

                    if replies.isEmpty {
                        emptyState
                    } else {
                        ForEach(replies) { message in
                            MessageRowView(
                                message: message,
                                grouped: false,
                                onReply: { replyTarget = $0 },
                                onEdit: { editing = $0 },
                                onOpenThread: { _ in }
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            if let channel {
                Composer(
                    channel: channel,
                    parentMessageId: messageId,
                    replyTarget: $replyTarget,
                    editing: $editing
                )
            }
        }
        .background(Theme.panel)
        .task(id: messageId) {
            _ = try? await session.loadThread(parentMessageId: messageId)
            parent = try? await session.getMessage(messageId: messageId)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)

            Text(L10n.t("thread", ns: "common"))
                .font(.headline)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close thread")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            Text(L10n.t("noRepliesYet", ns: "common"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Pinned messages of a channel, with a jump button per entry.
struct PinnedMessagesPanel: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel
    var onJump: (SharkordMessage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("pinnedMessagesTitle", ns: "common"))
                .font(.headline)
                .padding(12)

            Divider()

            if session.pinnedMessages(in: channel.id).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)

                    Text(L10n.t("noPinnedMessages", ns: "common"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(session.pinnedMessages(in: channel.id)) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(
                                        session.user(for: message.pinnedBy ?? message.userId ?? 0)?.name
                                            ?? "Unknown"
                                    )
                                    .font(.system(size: 11, weight: .semibold))

                                    if let pinnedAt = message.pinnedAt {
                                        Text(
                                            Date(timeIntervalSince1970: Double(pinnedAt) / 1000),
                                            style: .relative
                                        )
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        onJump(message)
                                    } label: {
                                        Image(systemName: "arrow.down.to.line")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.accent)
                                    .help("Scroll to message")
                                }

                                Text(MessageHTML.toPlainText(message.content ?? ""))
                                    .font(.system(size: 12))
                                    .lineLimit(4)
                                    .textSelection(.enabled)
                            }
                            .padding(8)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(10)
                }
            }
        }
        .task {
            _ = try? await session.loadPinned(channelId: channel.id)
        }
    }
}
