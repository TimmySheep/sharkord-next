import Foundation

/// Custom emoji management. `emojis.add` takes a top level array of uploads.
extension SharkordSession {
    public func addEmojis(_ entries: [EmojiCreateEntry]) async throws {
        guard !entries.isEmpty else {
            return
        }

        let payload: JSONValue = .array(
            entries.map {
                .object([
                    "fileId": .string($0.fileId),
                    "name": .string($0.name)
                ])
            }
        )

        _ = try await call("emojis.add", method: .mutation, input: payload)
    }

    public func updateEmoji(emojiId: Int, name: String) async throws {
        _ = try await call(
            "emojis.update",
            method: .mutation,
            input: .object([
                "emojiId": .int(emojiId),
                "name": .string(name)
            ])
        )
    }

    public func deleteEmoji(emojiId: Int) async throws {
        _ = try await call(
            "emojis.delete",
            method: .mutation,
            input: .object(["emojiId": .int(emojiId)])
        )
    }

    @discardableResult
    public func getAllEmojis() async throws -> [SharkordEmoji] {
        try await call("emojis.getAll", method: .query).decode([SharkordEmoji].self)
    }
}
