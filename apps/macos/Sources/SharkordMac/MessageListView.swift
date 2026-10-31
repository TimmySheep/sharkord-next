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

    private var canEdit: Bool { message.editable != false && isOwn }

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

            }
            .padding(.horizontal, 12)
            .padding(.vertical, grouped ? 2 : 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? Theme.accent.opacity(0.22) : mentionHighlight)
            )
            .background(hovering ? Theme.hover : .clear)
            .overlay(alignment: .topTrailing) {
                if hovering {
                    actions.padding(.trailing, 12)
                }
            }
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
            Text(author?.name ?? L10n.t("unknownUser", ns: "common"))
                .font(.system(size: 14.5, weight: isOwn ? .bold : .semibold))
                .foregroundStyle(author.map { Theme.color(for: $0) } ?? .primary)
                .strikethrough(author?.banned == true)

            if message.pluginId != nil {
                Text(L10n.t("botBadge", ns: "macos"))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }

            Text(L10n.date(Date(timeIntervalSince1970: Double(message.createdAt) / 1000), style: .time))
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
                Text(L10n.t("edited", ns: "common"))
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
                    Label(L10n.t("reply", ns: "common", ["count": replies]), systemImage: "text.bubble")
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

            Text(author?.name ?? L10n.t("unknownUser", ns: "common"))
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
            .help(L10n.t("replyToMessage", ns: "common"))
            .accessibilityLabel(L10n.t("replyToMessage", ns: "common"))

            if message.parentMessageId == nil {
                Button {
                    onOpenThread(message)
                } label: {
                    Image(systemName: "text.bubble")
                }
                .help(L10n.t("replyInThread", ns: "common"))
                .accessibilityLabel(L10n.t("replyInThread", ns: "common"))
            }

            if canEdit {
                Button {
                    onEdit(message)
                } label: {
                    Image(systemName: "pencil")
                }
                .help(L10n.t("editMessage", ns: "common"))
                .accessibilityLabel(L10n.t("editMessage", ns: "common"))
            }

            if session.hasPermission(.pinMessages), message.parentMessageId == nil {
                Button {
                    Task { try? await session.togglePin(messageId: message.id) }
                } label: {
                    Image(systemName: message.pinned == true ? "pin.slash" : "pin")
                }
                .help(L10n.t(message.pinned == true ? "unpinMessage" : "pinMessage", ns: "common"))
                .accessibilityLabel(L10n.t(message.pinned == true ? "unpinMessage" : "pinMessage", ns: "common"))
            }

            if canDelete {
                Button(role: .destructive) {
                    requestDeleteConfirmation()
                } label: {
                    Image(systemName: "trash")
                }
                .help(L10n.t("deleteLabel", ns: "common"))
                .accessibilityLabel(L10n.t("deleteLabel", ns: "common"))
            }

            if isOwn {
                Menu {
                    contextMenuItems
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.t("messageActions", ns: "macos"))
                .accessibilityLabel(L10n.t("messageActions", ns: "macos"))
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 6))
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
        .help(L10n.t("addReaction", ns: "common"))
        .accessibilityLabel(L10n.t("addReaction", ns: "common"))
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
            Button(L10n.t(message.pinned == true ? "unpinMessage" : "pinMessage", ns: "common")) {
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

/// stable message identities let lazy layout retain the reading position when history grows
struct MessageListView: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel
    var onReply: (SharkordMessage) -> Void
    var onEdit: (SharkordMessage) -> Void
    var onOpenThread: (SharkordMessage) -> Void

    @State private var highlightId: Int?
    @State private var visibleMessageId: Int?
    @State private var atBottom = true
    @State private var positioned = false
    @State private var loadingOlder = false
    @State private var newMessagesStartId: Int?

    private var messages: [SharkordMessage] {
        session.messagesByChannel[channel.id] ?? []
    }

    private var unreadBoundary: Int? {
        session.unreadBoundaryByChannel[channel.id]
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if session.hasNewerByChannel[channel.id] == true || !atBottom || newMessagesStartId != nil {
                    Button(L10n.t("returnToPresent", ns: "macos")) {
                        Task {
                            if session.hasNewerByChannel[channel.id] == true {
                                await session.returnToPresent(channelId: channel.id)
                            }
                            newMessagesStartId = nil
                            scrollToBottom(proxy)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Theme.accent)
                }

                GeometryReader { viewport in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if session.hasMoreOlderByChannel[channel.id] == true {
                                loadOlderButton
                            }

                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                VStack(alignment: .leading, spacing: 0) {
                                    if message.id == unreadBoundary {
                                        messageDivider(L10n.t("unreadMessages", ns: "macos"))
                                    }
                                    if message.id == newMessagesStartId, message.id != unreadBoundary {
                                        messageDivider(L10n.t("newMessages", ns: "macos"))
                                    }
                                    MessageRowView(
                                        message: message,
                                        grouped: isGrouped(message, at: index),
                                        highlighted: message.id == highlightId,
                                        onReply: onReply,
                                        onEdit: onEdit,
                                        onOpenThread: onOpenThread
                                    )
                                }
                                .id(message.id)
                            }

                            Color.clear.frame(height: 1)
                                .background {
                                    GeometryReader { bottom in
                                        Color.clear.preference(
                                            key: MessageBottomPreference.self,
                                            value: bottom.frame(in: .named("messageViewport")).maxY
                                        )
                                    }
                                }
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, 8)
                    }
                    .coordinateSpace(name: "messageViewport")
                    .scrollPosition(id: $visibleMessageId, anchor: .top)
                    .onPreferenceChange(MessageBottomPreference.self) { bottom in
                        atBottom = bottom <= viewport.size.height + 40
                    }
                }

                if !session.typingUsers(in: channel.id).isEmpty {
                    typingIndicator
                }
            }
            .onAppear {
                positionInitially(proxy)
            }
            .onChange(of: messages.last?.id) { oldId, newId in
                guard !loadingOlder else { return }
                if !positioned {
                    positionInitially(proxy)
                } else if atBottom, session.hasNewerByChannel[channel.id] != true {
                    scrollToBottom(proxy)
                } else if newMessagesStartId == nil, let oldId,
                          let oldIndex = messages.firstIndex(where: { $0.id == oldId }) {
                    newMessagesStartId = messages.dropFirst(oldIndex + 1)
                        .first { $0.userId != session.ownUserId }?.id
                }
            }
            .onChange(of: session.messageJumpByChannel[channel.id]) { _, messageId in
                guard let messageId else { return }
                highlightId = messageId
                positioned = true
                proxy.scrollTo(messageId, anchor: .center)
            }
        }
        .background(Theme.panel)
    }

    private func isGrouped(_ message: SharkordMessage, at index: Int) -> Bool {
        guard message.id != unreadBoundary, message.id != newMessagesStartId else { return false }
        let previous = index > 0 ? messages[index - 1] : nil
        return MessageTimeline.isGrouped(message, after: previous)
    }

    private func positionInitially(_ proxy: ScrollViewProxy) {
        guard !positioned, !messages.isEmpty else { return }
        positioned = true
        if let messageId = session.messageJumpByChannel[channel.id] {
            highlightId = messageId
            proxy.scrollTo(messageId, anchor: .center)
        } else if let unreadBoundary {
            proxy.scrollTo(unreadBoundary, anchor: .top)
        } else if session.hasNewerByChannel[channel.id] != true {
            scrollToBottom(proxy)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
        atBottom = true
    }

    private var loadOlderButton: some View {
        Button(L10n.t("loadEarlierMessages", ns: "macos")) {
            loadingOlder = true
            let anchor = visibleMessageId
            Task {
                await session.loadOlder(channelId: channel.id)
                // scrollPosition retains this stable row when older rows are prepended
                visibleMessageId = anchor
                loadingOlder = false
            }
        }
        .disabled(loadingOlder || session.isLoadingMore.contains(channel.id))
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func messageDivider(_ title: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().frame(height: 1)
            Text(title).font(.system(size: 10, weight: .semibold))
            Rectangle().frame(height: 1)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        let key = names.count == 1 ? "typingSingle" : "typingMultiple"
        return L10n.t(key, ns: "macos", ["names": names.joined(separator: ", ")])
    }
}

private struct MessageBottomPreference: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
