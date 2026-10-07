import SharkordCore
import SwiftUI

struct ThreadView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss

    let parent: SharkordMessage

    @State private var draft = ""
    @State private var nextCursor: MessagesCursor?
    @State private var isSending = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            MessageRow(message: parent, onReply: { _ in }, onOpenThread: { _ in })

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
                                MessageRow(message: message, onReply: { _ in }, onOpenThread: { _ in })
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

                composer
            }
            .background(BrandBackground())
            .navigationTitle(L10n.t("message.thread"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .task(id: parent.id) {
            do {
                nextCursor = try await session.loadThread(parentMessageId: parent.id).nextCursor
            } catch {
                model.banner = error.localizedDescription
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(L10n.t("channel.messagePlaceholder"), text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($composerFocused)
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
            .disabled(!canSend || isSending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SharkordTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadOlder(cursor: MessagesCursor) {
        Task {
            do {
                nextCursor = try await session.loadThread(parentMessageId: parent.id, cursor: cursor).nextCursor
            } catch {
                model.banner = error.localizedDescription
            }
        }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSending else {
            return
        }

        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await session.sendMessage(text, channelId: parent.channelId, parentMessageId: parent.id)
                draft = ""
            } catch {
                model.banner = error.localizedDescription
            }
        }
    }
}
