import Foundation

/// Message actions: send (with replies and attachments), edit, delete, reactions, typing
/// and read receipts. Kept in an extension so the session's state and event handling stay
/// in one file.
extension SharkordSession {
    public func sendMessage(
        _ text: String,
        channelId: Int,
        replyToMessageId: Int? = nil,
        files: [String] = []
    ) async throws {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty || !files.isEmpty else {
            return
        }

        var input: [String: JSONValue] = [
            "content": .string(MessageHTML.fromPlainText(trimmed)),
            "channelId": .int(channelId),
            "files": .array(files.map { .string($0) })
        ]

        if let replyToMessageId {
            input["replyToMessageId"] = .int(replyToMessageId)
        }

        _ = try await client.mutation("messages.send", input: .object(input))
    }

    public func editMessage(_ messageId: Int, text: String) async throws {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return
        }

        _ = try await client.mutation(
            "messages.edit",
            input: .object([
                "messageId": .int(messageId),
                "content": .string(MessageHTML.fromPlainText(trimmed))
            ])
        )
    }

    public func deleteMessage(_ messageId: Int) async throws {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        _ = try await client.mutation(
            "messages.delete",
            input: .object(["messageId": .int(messageId)])
        )
    }

    public func toggleReaction(messageId: Int, emoji: String) async throws {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        _ = try await client.mutation(
            "messages.toggleReaction",
            input: .object([
                "messageId": .int(messageId),
                "emoji": .string(emoji)
            ])
        )
    }

    /// Fire and forget: a typing signal is not worth surfacing an error for.
    public func signalTyping(channelId: Int) {
        guard let client else {
            return
        }

        Task {
            _ = try? await client.mutation(
                "messages.signalTyping",
                input: .object(["channelId": .int(channelId)])
            )
        }
    }

    public func markAsRead(_ channelId: Int) {
        clearUnread(channelId)

        guard let client else {
            return
        }

        Task {
            _ = try? await client.mutation(
                "channels.markAsRead",
                input: .object(["channelId": .int(channelId)])
            )
        }
    }

    /// Uploads one attachment and returns the temp file id `messages.send` expects in `files`.
    public func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        guard let http, let token else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        let temp = try await http.upload(
            data: data,
            fileName: fileName,
            mimeType: mimeType,
            token: token
        )

        return temp.id
    }
}
