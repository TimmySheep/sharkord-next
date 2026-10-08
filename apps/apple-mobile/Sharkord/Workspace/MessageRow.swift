import SharkordCore
import SwiftUI

/// One message: author, timestamp, body (the server's HTML shown as plain text), reply
/// preview, attachments, reaction chips and the message actions on long press.
struct MessageRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    let message: SharkordMessage
    let onReply: (SharkordMessage) -> Void
    let onOpenThread: (SharkordMessage) -> Void

    @State private var isEditing = false
    @State private var editedText = ""
    @State private var previewFile: SharkordFile?

    private static let quickReactions = ["👍", "❤️", "😂", "🎉", "😮"]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: authorName, diameter: 40)

            VStack(alignment: .leading, spacing: 4) {
                header

                if let replyTo = message.replyTo {
                    replyPreview(replyTo)
                }

                let body = MessageText.plainText(fromHTML: message.content)
                if !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(SharkordTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if let files = message.files, !files.isEmpty {
                    attachments(files)
                }

                if !reactionGroups.isEmpty {
                    reactions
                }

                threadButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contextMenu {
            ForEach(Self.quickReactions, id: \.self) { emoji in
                Button {
                    react(emoji)
                } label: {
                    Label(emoji, systemImage: "face.smiling")
                }
            }

            Button {
                onReply(message)
            } label: {
                Label(L10n.t("message.reply"), systemImage: "arrowshape.turn.up.left")
            }

            Button {
                onOpenThread(message)
            } label: {
                Label(L10n.t("message.thread"), systemImage: "bubble.left.and.bubble.right")
            }

            if message.userId == session.ownUserId && message.editable != false {
                Button {
                    editedText = MessageText.plainText(fromHTML: message.content)
                    isEditing = true
                } label: {
                    Label(L10n.t("message.edit"), systemImage: "pencil")
                }
            }

            if canDelete {
                Button(role: .destructive) {
                    Task { try? await session.deleteMessage(message.id) }
                } label: {
                    Label(L10n.t("message.delete"), systemImage: "trash")
                }
            }

            if session.canManageMessages {
                Button {
                    Task { try? await session.togglePin(messageId: message.id) }
                } label: {
                    Label(L10n.t("message.pin"), systemImage: "pin")
                }
            }
        }
        .alert(L10n.t("message.editTitle"), isPresented: $isEditing) {
            TextField(L10n.t("message.editPlaceholder"), text: $editedText)
            Button(L10n.t("common.save")) {
                let text = editedText
                Task { try? await session.editMessage(message.id, text: text) }
            }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .fullScreenCover(item: $previewFile) { file in
            NavigationStack {
                AsyncImage(url: session.publicFileURL(for: file)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        ContentUnavailableView(L10n.t("message.previewFailed"), systemImage: "exclamationmark.triangle")
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
                        Button(L10n.t("common.done")) { previewFile = nil }
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

    private func replyPreview(_ reply: SharkordReplyPreview) -> some View {
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
                        previewFile = file
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

    private var threadButton: some View {
        let count = session.replyCount(for: message)
        return Button {
            onOpenThread(message)
        } label: {
            Label(
                count > 0 ? L10n.format("message.replyCount", count) : L10n.t("message.thread"),
                systemImage: "bubble.left.and.bubble.right"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(SharkordTheme.accentSoft)
        }
        .buttonStyle(.plain)
        .padding(.top, 3)
    }

    private var reactionGroups: [ReactionGroup] {
        session.reactionGroups(for: message)
    }

    private var reactions: some View {
        HStack(spacing: 6) {
            ForEach(reactionGroups) { group in
                Button {
                    react(group.emoji)
                } label: {
                    HStack(spacing: 4) {
                        Text(group.emoji)
                            .font(.caption)

                        Text("\(group.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(group.mine ? SharkordTheme.accentSoft : SharkordTheme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        group.mine ? SharkordTheme.accent.opacity(0.28) : SharkordTheme.field,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
        }
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
        Task { try? await session.toggleReaction(messageId: message.id, emoji: emoji) }
    }
}
