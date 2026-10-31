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
        try Task.checkCancellation()
        let request = ThreadRequest()
        threadRequests[parentMessageId] = request
        defer {
            if threadRequests[parentMessageId]?.id == request.id {
                threadRequests[parentMessageId] = nil
            }
        }
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

        try applyThreadPage(page, parentMessageId: parentMessageId, requestId: request.id)

        return page
    }

    public func cancelThreadLoad(parentMessageId: Int) {
        threadRequests[parentMessageId] = nil
    }

    func applyThreadPage(_ page: ThreadPage, parentMessageId: Int, requestId: UUID) throws {
        try Task.checkCancellation()
        guard let request = threadRequests[parentMessageId], request.id == requestId else {
            throw CancellationError()
        }
        var byId = Dictionary(uniqueKeysWithValues: (threadMessages[parentMessageId] ?? []).map { ($0.id, $0) })
        // subscription changes received during this request are newer than its snapshot
        for message in page.messages where message.parentMessageId == parentMessageId && !request.changedMessageIds.contains(message.id) {
            byId[message.id] = message
        }
        threadMessages[parentMessageId] = byId.values.sorted(by: MessageTimeline.precedes)
        threadNextCursor[parentMessageId] = page.nextCursor
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
