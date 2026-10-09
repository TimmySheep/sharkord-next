import SharkordCore
import SwiftUI
import UIKit

/// message actions live in a content-sized sheet so they do not clutter the timeline.
struct MessageRow: View {
    @EnvironmentObject private var session: SharkordSession

    let message: SharkordMessage
    let onReply: (SharkordMessage) -> Void
    let onOpenThread: (SharkordMessage) -> Void
    var allowsReply = true
    var allowsThread = true

    @State private var isEditing = false
    @State private var editedText = ""
    @State private var selectedImageFile: SharkordFile?
    @State private var isShowingActions = false
    @State private var actionSheetHeight: CGFloat = 320
    @State private var pendingAction: (() -> Void)?
    @State private var isConfirmingDelete = false
    @State private var actionError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(
                name: authorName,
                diameter: 40,
                imageURL: message.userId
                    .flatMap { session.user(for: $0)?.avatar }
                    .flatMap(session.publicFileURL(for:))
            )

            VStack(alignment: .leading, spacing: 4) {
                header

                if let replyTo = message.replyTo {
                    replySnippet(replyTo)
                }

                if !MessageHTML.parse(message.content ?? "").isEmpty {
                    MessageRichText(html: message.content ?? "")
                }

                if let files = message.files, !files.isEmpty {
                    attachments(files)
                }

                if !reactionGroups.isEmpty {
                    reactions
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onLongPressGesture { isShowingActions = true }
        .accessibilityAction(named: L10n.t("message.actions")) { isShowingActions = true }
        .sheet(isPresented: $isShowingActions, onDismiss: performPendingAction) {
            ScrollView {
                messageActions
                    .padding(20)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: MessageActionHeightKey.self, value: geometry.size.height)
                        }
                    }
            }
            .onPreferenceChange(MessageActionHeightKey.self) { actionSheetHeight = $0 + 24 }
            .presentationDetents([.height(actionSheetHeight)])
            .presentationDragIndicator(.visible)
        }
        .alert(L10n.t("message.editTitle"), isPresented: $isEditing) {
            TextField(L10n.t("message.editPlaceholder"), text: $editedText)
            Button(L10n.t("common.save")) {
                let text = editedText
                runAction { try await session.editMessage(message.id, text: text) }
            }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .alert(L10n.t("message.delete"), isPresented: $isConfirmingDelete) {
            Button(L10n.t("message.delete"), role: .destructive) {
                runAction { try await session.deleteMessage(message.id) }
            }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("message.confirmDelete"))
        }
        .alert(L10n.t("message.actionFailed"), isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button(L10n.t("common.done"), role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .fullScreenCover(item: $selectedImageFile) { file in
            NavigationStack {
                AsyncImage(url: session.publicFileURL(for: file)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        ContentUnavailableView(L10n.t("message.imageLoadFailed"), systemImage: "exclamationmark.triangle")
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .navigationTitle(file.originalName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.t("common.done")) { selectedImageFile = nil }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SharkordTheme.textPrimary)

            Text(MessageText.date(fromMilliseconds: message.createdAt), format: .dateTime.month().day().hour().minute())
                .font(.caption2)
                .foregroundStyle(SharkordTheme.textTertiary)

            if message.editedAt != nil {
                Text(L10n.t("message.edited"))
                    .font(.caption2)
                    .foregroundStyle(SharkordTheme.textTertiary)
            }

            if message.pinned == true {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(SharkordTheme.accentSoft)
                    .accessibilityLabel(L10n.t("message.pinned"))
            }
        }
    }

    private func replySnippet(_ reply: SharkordReplyPreview) -> some View {
        let name = reply.userId.flatMap { session.user(for: $0)?.name } ?? L10n.t("message.unknownAuthor")

        return HStack(spacing: 5) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.caption2)
                .foregroundStyle(SharkordTheme.accentSoft)

            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SharkordTheme.textSecondary)

            Text(MessageText.plainText(fromHTML: reply.content))
                .font(.caption)
                .foregroundStyle(SharkordTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func attachments(_ files: [SharkordFile]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(files) { file in
                if file.mimeType.hasPrefix("image/"), let url = session.publicFileURL(for: file) {
                    Button {
                        selectedImageFile = file
                    } label: {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else if phase.error != nil {
                                Label(file.originalName, systemImage: "photo.badge.exclamationmark")
                                    .foregroundStyle(SharkordTheme.textSecondary)
                            } else {
                                ProgressView()
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .frame(maxWidth: 260, maxHeight: 200, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if let url = session.publicFileURL(for: file) {
                    Link(destination: url) {
                        Label(file.originalName, systemImage: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Label(file.originalName, systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var messageActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(authorName).font(.headline)
            let preview = MessageText.plainText(fromHTML: message.content)
            if !preview.isEmpty {
                Text(preview).font(.subheadline).lineLimit(2).foregroundStyle(.secondary)
            }
            if session.hasPermission(.reactToMessages) {
                Text(L10n.t("message.addReaction")).font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 6) {
                    ForEach(["👍", "❤️", "😂", "🎉", "👀", "😮", "😀", "😍", "😢", "🔥", "✅", "🙏"], id: \.self) { emoji in
                        Button {
                            dismissActions { react(emoji) }
                        } label: {
                            Text(emoji).font(.title2).frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(session.emojis) { emoji in
                        Button {
                            dismissActions { react(emoji.name) }
                        } label: {
                            if let file = emoji.file, let url = session.publicFileURL(for: file) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Text(emoji.name).font(.caption)
                                }
                                .frame(width: 32, height: 32)
                                .frame(minWidth: 44, minHeight: 44)
                            } else {
                                Text(emoji.name).font(.caption).frame(minWidth: 44, minHeight: 44)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emoji.name)
                    }
                }
            }
            if allowsReply {
                actionButton("message.reply", symbol: "arrowshape.turn.up.left") {
                    dismissActions { onReply(message) }
                }
            }
            if !preview.isEmpty {
                actionButton("message.copy", symbol: "doc.on.doc") {
                    dismissActions { UIPasteboard.general.string = preview }
                }
            }
            if allowsThread {
                actionButton("message.thread", symbol: "bubble.left.and.bubble.right") {
                    dismissActions { onOpenThread(message) }
                }
            }
            if message.userId == session.ownUserId && message.editable != false {
                actionButton("message.edit", symbol: "pencil") {
                    dismissActions {
                        editedText = MessageText.plainText(fromHTML: message.content)
                        isEditing = true
                    }
                }
            }
            if session.canManageMessages {
                actionButton(message.pinned == true ? "message.unpin" : "message.pin", symbol: "pin") {
                    dismissActions { runAction { try await session.togglePin(messageId: message.id) } }
                }
            }
            if canDelete {
                actionButton("message.delete", symbol: "trash", destructive: true) {
                    dismissActions { isConfirmingDelete = true }
                }
            }
        }
    }

    private func actionButton(_ key: String, symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.t(key), systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .foregroundStyle(destructive ? SharkordTheme.danger : SharkordTheme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func dismissActions(_ action: @escaping () -> Void) {
        pendingAction = action
        isShowingActions = false
    }

    private func performPendingAction() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }

    private var reactionGroups: [ReactionGroup] {
        session.reactionGroups(for: message)
    }

    private var reactions: some View {
        ScrollView(.horizontal) {
          HStack(spacing: 6) {
            ForEach(reactionGroups) { group in
                Button {
                    react(group.emoji)
                } label: {
                    HStack(spacing: 4) {
                        if let file = group.file, let url = session.publicFileURL(for: file) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { Text(group.emoji).font(.caption) }
                            .frame(width: 22, height: 22)
                        } else {
                            Text(group.emoji).font(.caption)
                        }

                        Text("\(group.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(group.mine ? SharkordTheme.accentSoft : SharkordTheme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minHeight: 44)
                    .background(
                        group.mine ? SharkordTheme.accent.opacity(0.28) : SharkordTheme.field,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(!session.hasPermission(.reactToMessages))
                .accessibilityLabel("\(group.emoji) \(group.count)")
                .accessibilityAddTraits(group.mine ? .isSelected : [])
            }
          }
        }
        .scrollIndicators(.hidden)
    }

    private var canDelete: Bool {
        message.userId == session.ownUserId || session.canManageMessages
    }

    private var authorName: String {
        if let userId = message.userId, let user = session.user(for: userId) {
            return user.name
        }
        return message.pluginId ?? L10n.t("message.unknownAuthor")
    }

    private func react(_ emoji: String) {
        runAction { try await session.toggleReaction(messageId: message.id, emoji: emoji) }
    }

    private func runAction(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() }
            catch { actionError = error.localizedDescription }
        }
    }
}

private struct MessageActionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
