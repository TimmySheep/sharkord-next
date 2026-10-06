import AppKit
import SharkordCore
import SwiftUI

struct MessageListView: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel
    let onReply: (SharkordMessage) -> Void
    let onEdit: (SharkordMessage) -> Void

    private var messages: [SharkordMessage] {
        session.messagesByChannel[channel.id] ?? []
    }

    private var hasMoreOlder: Bool {
        session.hasMoreOlderByChannel[channel.id] == true
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if hasMoreOlder {
                        olderButton
                    }

                    ForEach(messages) { message in
                        MessageRow(message: message, onReply: onReply, onEdit: onEdit)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 10)
            }
            .onChange(of: messages.last?.id) { _, lastId in
                guard let lastId else {
                    return
                }

                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .onChange(of: channel.id) { _, _ in
                if let lastId = messages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    private var olderButton: some View {
        HStack {
            Spacer()

            if session.isLoadingMore.contains(channel.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Load older messages") {
                    Task { await session.loadOlder(channelId: channel.id) }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct MessageRow: View {
    @EnvironmentObject private var session: SharkordSession

    let message: SharkordMessage
    let onReply: (SharkordMessage) -> Void
    let onEdit: (SharkordMessage) -> Void

    private var author: SharkordUser? {
        message.userId.flatMap { session.user(for: $0) }
    }

    private var authorName: String {
        if message.pluginId != nil {
            return "Plugin"
        }

        return author?.name ?? "Unknown"
    }

    private var isOwn: Bool {
        message.userId == session.ownUserId
    }

    private var text: String {
        MessageHTML.toPlainText(message.content ?? "")
    }

    private var reactions: [ReactionGroup] {
        session.reactionGroups(for: message)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(user: author, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                header

                if let replyTo = message.replyTo {
                    replyPreview(replyTo)
                }

                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let files = message.files, !files.isEmpty {
                    attachments(files)
                }

                if !reactions.isEmpty {
                    reactionRow
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu { contextMenu }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(authorName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.color(for: author))

            Text(Self.timestamp(message.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if message.editedAt != nil {
                Text("(edited)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func replyPreview(_ reply: SharkordReplyPreview) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Text(session.user(for: reply.userId ?? 0)?.name ?? "Unknown")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(MessageHTML.toPlainText(reply.content ?? ""))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 2)
    }

    private var reactionRow: some View {
        HStack(spacing: 4) {
            ForEach(reactions) { group in
                ReactionChip(group: group) {
                    Task {
                        try? await session.toggleReaction(messageId: message.id, emoji: group.emoji)
                    }
                }
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private var contextMenu: some View {
        ReactionMenu(message: message)

        Button {
            onReply(message)
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        } label: {
            Label("Copy text", systemImage: "doc.on.doc")
        }

        if isOwn && message.editable != false {
            Button {
                onEdit(message)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }

        if isOwn {
            Divider()

            Button(role: .destructive) {
                Task {
                    try? await session.deleteMessage(message.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func attachments(_ files: [SharkordFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(files) { file in
                if file.mimeType.hasPrefix("image/"), let url = session.publicFileURL(for: file) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let url = session.publicFileURL(for: file) {
                    Link(destination: url) {
                        Label(file.originalName, systemImage: "paperclip")
                            .font(.system(size: 12))
                    }
                } else {
                    Label(file.originalName, systemImage: "paperclip")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private static func timestamp(_ milliseconds: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MMM d, HH:mm"

        return formatter.string(from: date)
    }
}
