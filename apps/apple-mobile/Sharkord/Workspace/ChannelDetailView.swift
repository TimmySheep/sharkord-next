import SharkordCore
import SwiftUI
import UniformTypeIdentifiers

private struct PendingMessageAttachment: Identifiable {
    let id: String
    let name: String
}

/// The open conversation: the message list with its composer for text channels, the voice
/// room panel for voice channels. Messages, unread state, typing indicators and reactions
/// all come from the live session.
struct ChannelDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let channelId: Int

    @State private var draft = ""
    @State private var replyTo: SharkordMessage?
    @State private var threadParent: SharkordMessage?
    @State private var pendingAttachments: [PendingMessageAttachment] = []
    @State private var isUploadingFiles = false
    @State private var isFileImporterPresented = false
    @State private var isShowingVoiceChat = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if isVoiceChannel && horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    VoiceRoomView(channelId: channelId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    messageScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if isVoiceChannel && !isShowingVoiceChat {
                VoiceRoomView(channelId: channelId)
            } else {
                messageScreen
            }
        }
        .navigationTitle(channelTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(
            isVoiceChannel && horizontalSizeClass != .regular && isShowingVoiceChat
        )
        .toolbar {
            if isVoiceChannel && horizontalSizeClass != .regular && isShowingVoiceChat {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingVoiceChat = false
                    } label: {
                        Label(L10n.t("voice.call"), systemImage: "chevron.left")
                    }
                }
            } else if isVoiceChannel && horizontalSizeClass != .regular {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingVoiceChat = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                    .accessibilityLabel(L10n.t("voice.openChat"))
                }
            }
        }
        .sheet(item: $threadParent) { parent in
            ThreadView(parent: parent)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: uploadSelectedFiles
        )
        .task {
            model.selectChannel(channelId)
            openPendingThreadIfNeeded()
        }
        .onChange(of: model.pendingThreadParentId) { _, _ in
            openPendingThreadIfNeeded()
        }
    }

    private var isVoiceChannel: Bool {
        session.channel(for: channelId)?.type == .voice
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
                        MessageRow(
                            message: message,
                            onReply: { reply in
                                replyTo = reply
                                composerFocused = true
                            },
                            onOpenThread: { threadParent = $0 }
                        )
                        .id(message.id)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                if let navigation = model.pendingMessageNavigation, navigation.channelId == channelId {
                    proxy.scrollTo(navigation.messageId, anchor: .center)
                    model.pendingMessageNavigation = nil
                } else {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.messagesByChannel[channelId]?.count) { _, _ in
                if let navigation = model.pendingMessageNavigation, navigation.channelId == channelId {
                    proxy.scrollTo(navigation.messageId, anchor: .center)
                    model.pendingMessageNavigation = nil
                } else {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: model.pendingMessageNavigation) { _, navigation in
                guard let navigation, navigation.channelId == channelId else {
                    return
                }
                proxy.scrollTo(navigation.messageId, anchor: .center)
                model.pendingMessageNavigation = nil
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
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(pendingAttachments) { file in
                            HStack(spacing: 6) {
                                Text(file.name).lineLimit(1)
                                Button {
                                    removeAttachment(file)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.t("message.removeAttachment"))
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(SharkordTheme.field, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

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
                Button {
                    isFileImporterPresented = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canUploadFiles ? SharkordTheme.accentSoft : SharkordTheme.textTertiary)
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canUploadFiles || isUploadingFiles)
                .accessibilityLabel(L10n.t("message.attachFile"))

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
                            canSend && !isUploadingFiles ? SharkordTheme.accent : SharkordTheme.pillNeutral,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isUploadingFiles)
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
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    private var canUploadFiles: Bool {
        guard session.hasPermission(.uploadFiles), session.settings?.storageUploadEnabled != false else {
            return false
        }
        if session.channel(for: channelId)?.isDm == true {
            return session.settings?.storageFileSharingInDirectMessages != false
        }
        return true
    }

    private var typingNames: String {
        session.typingUsers(in: channelId).map(\.name).joined(separator: ", ")
    }

    private var channelTitle: String {
        guard let channel = session.channel(for: channelId) else {
            return ""
        }
        if channel.isDm {
            return session.directMessagePartner(for: channel)?.name ?? channel.name
        }
        return channel.type == .voice ? channel.name : "#\(channel.name)"
    }

    private func send() {
        let text = draft
        let reply = replyTo
        let files = pendingAttachments.map(\.id)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty else {
            return
        }

        Task {
            do {
                try await session.sendMessage(
                    text,
                    channelId: channelId,
                    replyToMessageId: reply?.id,
                    files: files
                )
                draft = ""
                replyTo = nil
                pendingAttachments = []
            } catch {
                model.banner = error.localizedDescription
            }
        }
    }

    private func uploadSelectedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            if case .failure(let error) = result {
                model.banner = error.localizedDescription
            }
            return
        }

        let limit = max(0, (session.settings?.storageMaxFilesPerMessage ?? 10) - pendingAttachments.count)
        guard limit > 0 else {
            model.banner = L10n.t("message.attachmentLimit")
            return
        }

        isUploadingFiles = true
        Task {
            defer { isUploadingFiles = false }
            for url in urls.prefix(limit) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let data = try Data(contentsOf: url)
                    if let maximumSize = session.settings?.storageUploadMaxFileSize, data.count > maximumSize {
                        throw SharkordHTTPError(status: 413, message: L10n.t("message.fileTooLarge"))
                    }
                    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let tempId = try await session.uploadAttachment(
                        data: data,
                        fileName: url.lastPathComponent,
                        mimeType: mimeType
                    )
                    pendingAttachments.append(PendingMessageAttachment(id: tempId, name: url.lastPathComponent))
                } catch {
                    model.banner = error.localizedDescription
                    break
                }
            }
        }
    }

    private func removeAttachment(_ attachment: PendingMessageAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
        Task { try? await session.deleteTemporaryFile(fileId: attachment.id) }
    }

    private func openPendingThreadIfNeeded() {
        guard let parentId = model.pendingThreadParentId else {
            return
        }

        Task {
            do {
                let parent = try await session.getMessage(messageId: parentId)
                guard parent.channelId == channelId else {
                    return
                }
                _ = try await session.loadThread(parentMessageId: parentId)
                threadParent = parent
                model.pendingThreadParentId = nil
            } catch {
                model.banner = error.localizedDescription
            }
        }
    }
}
