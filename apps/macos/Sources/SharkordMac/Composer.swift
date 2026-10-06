import Combine
import SharkordCore
import SwiftUI
import UniformTypeIdentifiers

/// Text composer. Plain text is escaped into the HTML the server stores, the same way the
/// web client's editor hands over HTML. Enter sends, Shift+Enter inserts a line break. It
/// also owns the reply target, edit mode and attachment uploads for the channel.
struct Composer: View {
    @EnvironmentObject private var session: SharkordSession

    let channel: SharkordChannel
    @Binding var replyTarget: SharkordMessage?
    @Binding var editing: SharkordMessage?

    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var pendingFiles: [PendingAttachment] = []
    @State private var isImporting = false
    @State private var now = Date()
    @State private var lastTypingSignal = Date.distantPast

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct PendingAttachment: Identifiable {
        let id: String
        let name: String
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingFiles.isEmpty
    }

    private var typingUsers: [SharkordUser] {
        // `now` is read so the view re-evaluates as the typing window expires
        _ = now

        return session.typingUsers(in: channel.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let editing {
                banner(
                    icon: "pencil",
                    label: "Editing message",
                    detail: MessageHTML.toPlainText(editing.content ?? ""),
                    onCancel: {
                        self.editing = nil
                        text = ""
                    }
                )
            } else if let replyTarget {
                banner(
                    icon: "arrowshape.turn.up.left",
                    label: "Replying to \(session.user(for: replyTarget.userId ?? 0)?.name ?? "message")",
                    detail: MessageHTML.toPlainText(replyTarget.content ?? ""),
                    onCancel: { self.replyTarget = nil }
                )
            }

            if !typingUsers.isEmpty {
                Text(typingLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !pendingFiles.isEmpty {
                attachmentsRow
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "paperclip")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .help("Attach a file")

                TextField("Message \(channel.isDm ? "" : "#")\(channel.name)", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(10)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit(send)
                    .onChange(of: text) { _, _ in signalTyping() }

                Button(action: send) {
                    Image(systemName: editing == nil ? "paperplane.fill" : "checkmark")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!canSend || isSending)
            }
        }
        .padding(12)
        .onReceive(timer) { now = $0 }
        .onChange(of: editing?.id) { _, _ in
            guard let editing else {
                return
            }

            text = MessageHTML.toPlainText(editing.content ?? "")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private var typingLabel: String {
        let names = typingUsers.map(\.name)

        if names.count == 1 {
            return "\(names[0]) is typing..."
        }

        return "\(names.joined(separator: ", ")) are typing..."
    }

    private var attachmentsRow: some View {
        HStack(spacing: 6) {
            ForEach(pendingFiles) { file in
                HStack(spacing: 4) {
                    Image(systemName: "paperclip").font(.system(size: 10))
                    Text(file.name).font(.system(size: 11)).lineLimit(1)
                    Button {
                        pendingFiles.removeAll { $0.id == file.id }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.elevated, in: Capsule())
            }
        }
    }

    private func banner(
        icon: String,
        label: String,
        detail: String,
        onCancel: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11, weight: .semibold))

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func signalTyping() {
        guard !text.isEmpty, Date().timeIntervalSince(lastTypingSignal) > 3 else {
            return
        }

        lastTypingSignal = Date()
        session.signalTyping(channelId: channel.id)
    }

    private func send() {
        guard canSend, !isSending else {
            return
        }

        let outgoing = text
        let fileIds = pendingFiles.map(\.id)
        let replyTo = replyTarget?.id
        let editingId = editing?.id

        text = ""
        pendingFiles = []
        isSending = true
        errorMessage = nil

        Task {
            defer { isSending = false }

            do {
                if let editingId {
                    try await session.editMessage(editingId, text: outgoing)
                    editing = nil
                } else {
                    try await session.sendMessage(
                        outgoing,
                        channelId: channel.id,
                        replyToMessageId: replyTo,
                        files: fileIds
                    )
                    replyTarget = nil
                }
            } catch {
                text = outgoing
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to send"
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            return
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"

            Task {
                do {
                    let id = try await session.uploadAttachment(
                        data: data,
                        fileName: url.lastPathComponent,
                        mimeType: mimeType
                    )
                    pendingFiles.append(PendingAttachment(id: id, name: url.lastPathComponent))
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Upload failed"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
