import Foundation

/// Direct message listings and opening a conversation. DM channels are created lazily by
/// the server on `dms.open` and published back over `channels.onCreate`.
extension SharkordSession {
    public func loadDirectMessages() async throws {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        let value = try await client.query("dms.get")
        directMessages = try value.decode([DirectMessageConversation].self)
    }

    func loadDirectMessagesQuietly() async {
        try? await loadDirectMessages()
    }

    /// Opens (or reuses) the direct message with `userId` and selects it.
    @discardableResult
    public func openDirectMessage(userId: Int) async throws -> Int {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        let value = try await client.mutation(
            "dms.open",
            input: .object(["userId": .int(userId)])
        )

        let result = try value.decode(OpenDirectMessageResult.self)

        await select(channelId: result.channelId)

        return result.channelId
    }

    public func conversation(for channelId: Int) -> DirectMessageConversation? {
        directMessages.first { $0.channelId == channelId }
    }

    /// The other participant of a DM channel, from the viewer's perspective.
    public func directMessagePartner(for channel: SharkordChannel) -> SharkordUser? {
        if let conversation = conversation(for: channel.id) {
            return user(for: conversation.userId)
        }

        // channel name is `DM - <one>:<two>` before the conversation list has loaded
        let parts = channel.name.replacingOccurrences(of: "DM - ", with: "").split(separator: ":")
        let ids = parts.compactMap { Int($0) }
        let partnerId = ids.first { $0 != ownUserId } ?? ids.first

        return partnerId.flatMap { user(for: $0) }
    }
}
