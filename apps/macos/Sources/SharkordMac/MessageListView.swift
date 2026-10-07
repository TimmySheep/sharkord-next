import Combine
import SharkordCore
import SwiftUI

/// One message and the chrome around it: the group header, inline reply preview, files,
/// reactions, the thread button and the hover actions. The web client keeps hover actions
/// in the row, so the native list does the same instead of using a context menu only.
struct MessageRowView: View {
    @EnvironmentObject private var session: SharkordSession

    let message: SharkordMessage
    let grouped: Bool
    var highlighted: Bool = false

    var onReply: (SharkordMessage) -> Void
    var onEdit: (SharkordMessage) -> Void
    var onOpenThread: (SharkordMessage) -> Void

    @State private var hovering = false
    @State private var showsDeleteConfirmation = false

    private var author: SharkordUser? {
        message.userId.flatMap { session.user(for: $0) }
    }

    private var isOwn: Bool {
        message.userId == session.ownUserId
    }

    private var canEdit: Bool {
        message.editable != false && (isOwn || session.canManageMessages)
    }

    private var canDelete: Bool {
        isOwn || session.canManageMessages
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let preview = message.replyTo {
                replyPreview(preview)
            }

            HStack(alignment: .top, spacing: 8) {
                if grouped {
                    Color.clear.frame(width: 32)
                } else {
                    AvatarView(user: author, size: 32)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if !grouped {
                        header
                    }

                    content

                    if !messageMedia.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(messageMedia) { media in
                                MessageMediaPlayerView(media: media)
                            }
                        }
                        .padding(.top, 2)
                    }

                    if let files = message.files, !files.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(files) { file in
                                FileCardView(file: file, onDelete: canDelete ? { deleteFile(file) } : nil)
                            }
                        }
                        .padding(.top, 2)
                    }

                    ReactionBar(groups: session.reactionGroups(for: message)) { emoji in
                        Task {
                            try? await session.toggleReaction(messageId: message.id, emoji: emoji)
                        }
                    }

                    footer
                }

                Spacer(minLength: 32)

                if hovering {
                    actions
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, grouped ? 2 : 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? Theme.accent.opacity(0.22) : mentionHighlight)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .contextMenu {
                contextMenuItems
            }
        }
        .confirmationDialog(
            L10n.t("deleteMessageTitle", ns: "common"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("deleteLabel", ns: "common"), role: .destructive) {
                deleteMessage()
            }

            Button(L10n.t("cancel", ns: "common"), role: .cancel) {}
        } message: {
            Text(L10n.t("deleteMessageConfirm", ns: "common"))
        }
    }

    private var mentionHighlight: Color {
        if session.ownUser.map({ MessageHTML.toPlainText(message.content ?? "").contains("@\($0.name)") }) == true {
            return Theme.accent.opacity(0.06)
        }

        return .clear
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(author?.name ?? "Unknown")
                .font(.system(size: 14.5, weight: isOwn ? .bold : .semibold))
                .foregroundStyle(author.map { Theme.color(for: $0) } ?? .primary)
                .strikethrough(author?.banned == true)

            if message.pluginId != nil {
                Text("bot")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }

            Text(Date(timeIntervalSince1970: Double(message.createdAt) / 1000), style: .relative)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        let html = message.content ?? ""
        let document = MessageHTML.parse(html)

        if MessageHTML.isEmpty(html), let files = message.files, !files.isEmpty {
            EmptyView()
        } else {
            MessageBodyView(document: document, emojiOnly: MessageHTML.isEmojiOnly(html))
        }
    }

    private var messageMedia: [MessageMediaReference] {
        let fileMedia = (message.files ?? []).compactMap { file in
            MessageMediaReference.file(
                fileExtension: file.fileExtension,
                url: session.publicFileURL(for: file)
            )
        }
        let metadataMedia = (message.metadata ?? []).compactMap { metadata in
            MessageMediaReference.metadata(
                kind: metadata.kind,
                mediaType: metadata.mediaType,
                url: session.url(forPath: metadata.url)
            )
        }

        return MessageMediaReference.deduplicated(fileMedia + metadataMedia)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if message.editedAt != nil {
                Text("edited")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if message.pinned == true {
                Label(L10n.t("pinnedBadge", ns: "macos"), systemImage: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            let replies = session.replyCount(for: message)

            if replies > 0, message.parentMessageId == nil {
                Button {
                    onOpenThread(message)
                } label: {
                    Label("\(replies) replies", systemImage: "text.bubble")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.top, 1)
    }

    private func replyPreview(_ preview: SharkordReplyPreview) -> some View {
        let author = preview.userId.flatMap { session.user(for: $0) }

        return HStack(spacing: 5) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Text(author?.name ?? "Unknown")
                .font(.system(size: 10.5, weight: .semibold))

            Text(MessageHTML.toPlainText(preview.content ?? ""))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.leading, 40)
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if session.hasPermission(.reactToMessages) {
                quickReactButton
            }

            Button {
                onReply(message)
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            }
            .help("Reply")

            if message.parentMessageId == nil {
                Button {
                    onOpenThread(message)
                } label: {
                    Image(systemName: "text.bubble")
                }
                .help("Reply in thread")
            }

            if canEdit {
                Button {
                    onEdit(message)
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit")
            }

            if session.hasPermission(.pinMessages), message.parentMessageId == nil {
                Button {
                    Task { try? await session.togglePin(messageId: message.id) }
                } label: {
                    Image(systemName: message.pinned == true ? "pin.slash" : "pin")
                }
                .help(message.pinned == true ? "Unpin" : "Pin")
            }

            if canDelete {
                Button(role: .destructive) {
                    requestDeleteConfirmation()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
    }

    private var quickReactButton: some View {
        Menu {
            ForEach(["👍", "❤️", "😂", "🎉", "👀", "🙏"], id: \.self) { emoji in
                Button(emoji) {
                    Task { try? await session.toggleReaction(messageId: message.id, emoji: emoji) }
                }
            }
        } label: {
            Image(systemName: "face.smiling")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(L10n.t("replyToMessage", ns: "common")) { onReply(message) }

        if message.parentMessageId == nil {
            Button(L10n.t("replyInThread", ns: "common")) { onOpenThread(message) }
        }

        if canEdit {
            Button(L10n.t("editLabel", ns: "sidebar")) { onEdit(message) }
        }

        if session.hasPermission(.pinMessages), message.parentMessageId == nil {
            Button(message.pinned == true ? "Unpin" : "Pin") {
                Task { try? await session.togglePin(messageId: message.id) }
            }
        }

        if canDelete {
            Divider()
            Button(L10n.t("deleteLabel", ns: "sidebar"), role: .destructive) {
                requestDeleteConfirmation()
            }
        }
    }

    private func requestDeleteConfirmation() {
        showsDeleteConfirmation = true
    }

    private func deleteMessage() {
        Task {
            try? await session.deleteMessage(message.id)
        }
    }

    private func deleteFile(_ file: SharkordFile) {
        Task { try? await session.deleteFile(fileId: file.id) }
    }
}

/// The message list of one channel. Consecutive messages from the same author within a
/// minute merge into a group, exactly like the web client's `useGroupedMessages`.
struct MessageListView: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel
    var onReply: (SharkordMessage) -> Void
    var onEdit: (SharkordMessage) -> Void
    var onOpenThread: (SharkordMessage) -> Void

    @State private var highlightId: Int?

    private var messages: [SharkordMessage] {
        session.messagesByChannel[channel.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.hasNewerByChannel[channel.id] == true {
                returnToPresent
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if session.hasMoreOlderByChannel[channel.id] == true {
                            loadOlderButton
                        }

                        ForEach(groups) { group in
                            MessageGroupView(
                                group: group,
                                highlightId: highlightId,
                                onReply: onReply,
                                onEdit: onEdit,
                                onOpenThread: onOpenThread
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: session.selectedChannelId) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if !session.typingUsers(in: channel.id).isEmpty {
                typingIndicator
            }
        }
        .background(Theme.panel)
    }

    private var loadOlderButton: some View {
        Button(L10n.t("loadEarlierMessages", ns: "macos")) {
            Task { await session.loadOlder(channelId: channel.id) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var returnToPresent: some View {
        Button(L10n.t("returnToPresent", ns: "macos")) {
            Task { await session.select(channelId: channel.id) }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.accent, in: Capsule())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var typingIndicator: some View {
        HStack(spacing: 6) {
            TypingDots()

            Text(typingText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private var typingText: String {
        let names = session.typingUsers(in: channel.id).map(\.name)

        if names.count == 1 {
            return "\(names[0]) is typing"
        }

        return "\(names.joined(separator: ", ")) are typing"
    }

    /// Same rules as the web client: same author, neither side is an inline reply, and less
    /// than a minute apart.
    private var groups: [MessageGroup] {
        var result: [MessageGroup] = []

        for message in messages {
            guard let last = result.last, let previous = last.messages.last else {
                result.append(MessageGroup(id: message.id, messages: [message]))
                continue
            }

            let sameAuthor = previous.userId == message.userId && previous.pluginId == message.pluginId
            let inlineReply = previous.replyToMessageId != nil || message.replyToMessageId != nil
            let closeInTime = abs(message.createdAt - previous.createdAt) < 60_000

            if sameAuthor, !inlineReply, closeInTime {
                result[result.count - 1].messages.append(message)
            } else {
                result.append(MessageGroup(id: message.id, messages: [message]))
            }
        }

        return result
    }
}

/// A run of consecutive messages that render as one block with a single author header.
struct MessageGroup: Identifiable {
    let id: Int
    var messages: [SharkordMessage]
}

struct MessageGroupView: View {
    let group: MessageGroup
    let highlightId: Int?
    var onReply: (SharkordMessage) -> Void
    var onEdit: (SharkordMessage) -> Void
    var onOpenThread: (SharkordMessage) -> Void

    var body: some View {
        ForEach(group.messages) { message in
            MessageRowView(
                message: message,
                grouped: message.id != group.id,
                highlighted: message.id == highlightId,
                onReply: onReply,
                onEdit: onEdit,
                onOpenThread: onOpenThread
            )
            .id(message.id)
        }
    }
}

/// Three dots that fade in sequence, matching the web client's `TypingDots`.
struct TypingDots: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 4, height: 4)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
