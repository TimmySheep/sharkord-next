import SharkordCore
import SwiftUI
import UniformTypeIdentifiers

struct ThreadView: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss

    let parent: SharkordMessage

    @State private var draft = ""
    @State private var nextCursor: MessagesCursor?
    @State private var isSending = false
    @State private var replyTo: SharkordMessage?
    @State private var pendingAttachments: [PendingMessageAttachment] = []
    @State private var isUploading = false
    @State private var isFileImporterPresented = false
    @State private var threadError: String?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            MessageRow(message: parent, onReply: { _ in composerFocused = true }, onOpenThread: { _ in }, allowsThread: false)

                            if let nextCursor {
                                Button {
                                    loadOlder(cursor: nextCursor)
                                } label: {
                                    Text(L10n.t("channel.loadOlder"))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(SharkordTheme.accentSoft)
                                        .frame(maxWidth: .infinity)
                                }
                                .padding(.vertical, 8)
                            }

                            ForEach(session.threadMessages(for: parent.id)) { message in
                                MessageRow(message: message, onReply: {
                                    replyTo = $0
                                    composerFocused = true
                                }, onOpenThread: { _ in }, allowsThread: false)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: session.threadMessages(for: parent.id).count) { _, _ in
                        if let lastId = session.threadMessages(for: parent.id).last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .background(BrandBackground())
            .navigationTitle(L10n.t("message.thread"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: true, onCompletion: uploadSelectedFiles)
        .alert(L10n.t("message.actionFailed"), isPresented: Binding(
            get: { threadError != nil },
            set: { if !$0 { threadError = nil } }
        )) {
            Button(L10n.t("common.done"), role: .cancel) { threadError = nil }
        } message: { Text(threadError ?? "") }
        .task(id: parent.id) {
            do {
                nextCursor = try await session.loadThread(parentMessageId: parent.id).nextCursor
            } catch {
                threadError = error.localizedDescription
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTo {
                HStack {
                    Text(MessageText.plainText(fromHTML: replyTo.content)).font(.caption).lineLimit(1)
                    Spacer()
                    Button { self.replyTo = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L10n.t("common.cancel"))
                }
                .padding(.horizontal, 18)
            }
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(pendingAttachments) { attachment in
                            Button {
                                pendingAttachments.removeAll { $0.id == attachment.id }
                                Task {
                                    do { try await session.deleteTemporaryFile(fileId: attachment.id) }
                                    catch { threadError = error.localizedDescription }
                                }
                            } label: {
                                Label(attachment.name, systemImage: "xmark.circle.fill").font(.caption).lineLimit(1)
                            }
                            .disabled(isSending || isUploading)
                            .accessibilityLabel(L10n.t("message.removeAttachment") + " " + attachment.name)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
            MessageTypingIndicator(channelId: parent.channelId, parentMessageId: parent.id)
            HStack(spacing: 10) {
                Button { isFileImporterPresented = true } label: {
                    Image(systemName: "paperclip").frame(width: 36, height: 44)
                }
                .disabled(!MessageAttachmentUpload.isAllowed(session: session, channelId: parent.channelId) || isUploading || isSending)
                .accessibilityLabel(L10n.t("message.attachFile"))
                TextField(L10n.t("channel.messagePlaceholder"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .disabled(isSending)
                    .onChange(of: draft) { _, _ in
                        session.signalTyping(channelId: parent.channelId, parentMessageId: parent.id)
                    }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(canSend ? SharkordTheme.accent : SharkordTheme.pillNeutral, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending || isUploading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SharkordTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(SharkordTheme.background)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    private func loadOlder(cursor: MessagesCursor) {
        Task {
            do {
                nextCursor = try await session.loadThread(parentMessageId: parent.id, cursor: cursor).nextCursor
            } catch {
                threadError = error.localizedDescription
            }
        }
    }

    private func send() {
        let text = draft
        let replyId = replyTo?.id
        let files = pendingAttachments.map(\.id)
        guard canSend, !isSending, !isUploading else {
            return
        }

        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await session.sendMessage(text, channelId: parent.channelId, replyToMessageId: replyId, parentMessageId: parent.id, files: files)
                draft = ""
                replyTo = nil
                pendingAttachments = []
            } catch {
                threadError = error.localizedDescription
            }
        }
    }

    private func uploadSelectedFiles(_ result: Result<[URL], Error>) {
        guard MessageAttachmentUpload.isAllowed(session: session, channelId: parent.channelId), !isUploading, !isSending else { return }
        guard case .success(let urls) = result else {
            if case .failure(let error) = result { threadError = error.localizedDescription }
            return
        }
        let limit = max(0, (session.settings?.storageMaxFilesPerMessage ?? 10) - pendingAttachments.count)
        guard limit > 0 else {
            threadError = L10n.t("message.attachmentLimit")
            return
        }
        isUploading = true
        Task {
            defer { isUploading = false }
            for url in urls.prefix(limit) {
                do {
                    let attachment = try await MessageAttachmentUpload.upload(url, session: session)
                    pendingAttachments.append(attachment)
                } catch {
                    threadError = error.localizedDescription
                    break
                }
            }
        }
    }
}
