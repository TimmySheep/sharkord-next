import Foundation

/// Pins, single message lookup, threads and search.
extension SharkordSession {
    @discardableResult
    public func loadPinned(channelId: Int) async throws -> [SharkordMessage] {
        let pinned = try await call(
            "messages.getPinned",
            method: .query,
            input: .object(["channelId": .int(channelId)])
        ).decode([SharkordMessage].self)

        pinnedByChannel[channelId] = pinned

        return pinned
    }

    @discardableResult
    public func getMessage(messageId: Int) async throws -> SharkordMessage {
        try await call(
            "messages.getOne",
            method: .query,
            input: .object(["messageId": .int(messageId)])
        ).decode(SharkordMessage.self)
    }

    public func togglePin(messageId: Int) async throws {
        _ = try await call(
            "messages.togglePin",
            method: .mutation,
            input: .object(["messageId": .int(messageId)])
        )
    }

    @discardableResult
    public func loadThread(parentMessageId: Int, cursor: MessagesCursor? = nil) async throws -> ThreadPage {
        var input: [String: JSONValue] = [
            "parentMessageId": .int(parentMessageId),
            "limit": .int(ProtocolDefaults.messagesLimit)
        ]

        if let cursor {
            input["cursor"] = .object([
                "createdAt": .int(cursor.createdAt),
                "id": .int(cursor.id)
            ])
        }

        let page = try await call("messages.getThread", method: .query, input: .object(input))
            .decode(ThreadPage.self)

        let ascending = page.messages.sorted { $0.createdAt < $1.createdAt }
        let existing = threadMessages[parentMessageId] ?? []
        let existingIds = Set(existing.map(\.id))
        let merged = existing + ascending.filter { !existingIds.contains($0.id) }

        threadMessages[parentMessageId] = merged.sorted { $0.createdAt < $1.createdAt }

        return page
    }

    @discardableResult
    public func search(query: String) async throws -> SearchResult {
        try await call(
            "messages.search",
            method: .query,
            input: .object(["query": .string(query)])
        ).decode(SearchResult.self)
    }
}
