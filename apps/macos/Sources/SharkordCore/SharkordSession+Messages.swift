import Foundation

/// Message actions: send (with replies, threads and attachments), edit, delete, reactions
/// and typing. Kept in an extension so the session's state and event handling stay in one
/// file; pins, threads and search live in `SharkordSession+MessagesExtra`.
extension SharkordSession {
    public func sendMessage(
        _ text: String,
        channelId: Int,
        replyToMessageId: Int? = nil,
        parentMessageId: Int? = nil,
        files: [String] = []
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty || !files.isEmpty else {
            return
        }

        var input: [String: JSONValue] = [
            "content": .string(MessageHTML.prepare(MessageHTML.fromPlainText(trimmed))),
            "channelId": .int(channelId),
            "files": .array(files.map { .string($0) })
        ]

        if let replyToMessageId {
            input["replyToMessageId"] = .int(replyToMessageId)
        }

        if let parentMessageId {
            input["parentMessageId"] = .int(parentMessageId)
        }

        _ = try await call("messages.send", method: .mutation, input: .object(input))
    }

    /// Sends raw html, for content the composer built from mentions and emoji.
    public func sendRichMessage(
        _ html: String,
        channelId: Int,
        replyToMessageId: Int? = nil,
        parentMessageId: Int? = nil,
        files: [String] = []
    ) async throws {
        var input: [String: JSONValue] = [
            "content": .string(MessageHTML.prepare(html)),
            "channelId": .int(channelId),
            "files": .array(files.map { .string($0) })
        ]

        if let replyToMessageId {
            input["replyToMessageId"] = .int(replyToMessageId)
        }

        if let parentMessageId {
            input["parentMessageId"] = .int(parentMessageId)
        }

        _ = try await call("messages.send", method: .mutation, input: .object(input))
    }

    public func editMessage(_ messageId: Int, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return
        }

        _ = try await call(
            "messages.edit",
            method: .mutation,
            input: .object([
                "messageId": .int(messageId),
                "content": .string(MessageHTML.prepare(MessageHTML.fromPlainText(trimmed)))
            ])
        )
    }

    public func deleteMessage(_ messageId: Int) async throws {
        _ = try await call(
            "messages.delete",
            method: .mutation,
            input: .object(["messageId": .int(messageId)])
        )
    }

    public func toggleReaction(messageId: Int, emoji: String) async throws {
        _ = try await call(
            "messages.toggleReaction",
            method: .mutation,
            input: .object([
                "messageId": .int(messageId),
                "emoji": .string(emoji)
            ])
        )
    }

    /// Fire and forget: a typing signal is not worth surfacing an error for.
    public func signalTyping(channelId: Int, parentMessageId: Int? = nil) {
        guard let client else {
            return
        }

        var input: [String: JSONValue] = ["channelId": .int(channelId)]

        if let parentMessageId {
            input["parentMessageId"] = .int(parentMessageId)
        }

        Task {
            _ = try? await client.mutation("messages.signalTyping", input: .object(input))
        }
    }
}
