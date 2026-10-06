import Foundation
import Testing

@testable import SharkordCore

/// End to end check against a real server. Disabled unless `SHARKORD_IT_HOST` is set, so
/// the normal `swift test` run stays offline. Point it at a throwaway instance, not a
/// server anyone is using: the test registers a user and sends a message.
///
///   SHARKORD_IT_HOST=127.0.0.1:4992 swift test --filter endToEnd
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHARKORD_IT_HOST"] != nil))
struct IntegrationTests {
    private var host: String {
        ProcessInfo.processInfo.environment["SHARKORD_IT_HOST"] ?? ""
    }

    private var identity: String {
        ProcessInfo.processInfo.environment["SHARKORD_IT_IDENTITY"] ?? "native-probe"
    }

    private var password: String {
        ProcessInfo.processInfo.environment["SHARKORD_IT_PASSWORD"] ?? "probe-password"
    }

    @Test
    func loginJoinSendAndReceive() async throws {
        let baseURL = try #require(URL(string: "http://\(host)"))
        let http = SharkordHTTPClient(baseURL: baseURL)

        let info = try await http.serverInfo()
        #expect(!info.serverId.isEmpty)

        let login = try await http.login(identity: identity, password: password)
        #expect(!login.token.isEmpty)

        let client = TRPCWebSocketClient(
            configuration: .init(url: http.webSocketURL, token: login.token)
        )
        try await client.connect()
        defer { Task { await client.close() } }

        let handshake = try await client.query("others.handshake")
            .decode(SharkordHandshake.self)

        #expect(!handshake.handshakeHash.isEmpty)

        let join = try await client.query(
            "others.joinServer",
            input: .object(["handshakeHash": .string(handshake.handshakeHash)])
        ).decode(JoinResult.self)

        #expect(join.ownUserId > 0)
        #expect(join.serverId == info.serverId)
        #expect(join.users.contains { $0.id == join.ownUserId })

        let textChannel = try #require(join.channels.first { $0.type == .text })

        // subscribe before sending so the event cannot be missed
        let stream = await client.subscribe("messages.onNew")

        let marker = "native-probe-\(UUID().uuidString)"
        let messageId = try await client.mutation(
            "messages.send",
            input: .object([
                "content": .string("<p>\(marker)</p>"),
                "channelId": .int(textChannel.id),
                "files": .array([])
            ])
        ).intValue

        #expect(messageId != nil)

        let page = try await client.query(
            "messages.get",
            input: .object([
                "channelId": .int(textChannel.id),
                "limit": .int(50)
            ])
        ).decode(MessagesPage.self)

        #expect(page.messages.contains { $0.content?.contains(marker) == true })

        // the live subscription should deliver the same message
        let event = try await Self.firstEvent(stream, timeout: 5)
        let delivered = try event?.decode(SharkordMessage.self)
        #expect(delivered?.content?.contains(marker) == true)
    }

    /// Exercises the message mutations and the DM/read-receipt routes added after the
    /// first slice: edit, react, delete, typing, mark read and open a direct message.
    @Test
    func editReactDeleteAndDirectMessage() async throws {
        let baseURL = try #require(URL(string: "http://\(host)"))
        let http = SharkordHTTPClient(baseURL: baseURL)

        _ = try await http.serverInfo()
        let login = try await http.login(identity: identity, password: password)

        let client = TRPCWebSocketClient(
            configuration: .init(url: http.webSocketURL, token: login.token)
        )
        try await client.connect()
        defer { Task { await client.close() } }

        let handshake = try await client.query("others.handshake")
            .decode(SharkordHandshake.self)

        let join = try await client.query(
            "others.joinServer",
            input: .object(["handshakeHash": .string(handshake.handshakeHash)])
        ).decode(JoinResult.self)

        let textChannel = try #require(join.channels.first { $0.type == .text })

        // claim ownership on a throwaway server so the permission gated routes below are
        // reachable; a fresh server's default role has no REACT_TO_MESSAGES
        let secret = ProcessInfo.processInfo.environment["SHARKORD_IT_SECRET"] ?? "dev"
        _ = try? await client.mutation(
            "others.useSecretToken",
            input: .object(["token": .string(secret)])
        )

        let marker = "probe-edit-\(UUID().uuidString)"

        let messageId = try #require(
            try await client.mutation(
                "messages.send",
                input: .object([
                    "content": .string("<p>\(marker)</p>"),
                    "channelId": .int(textChannel.id),
                    "files": .array([])
                ])
            ).intValue
        )

        _ = try await client.mutation(
            "messages.edit",
            input: .object([
                "messageId": .int(messageId),
                "content": .string("<p>\(marker)-edited</p>")
            ])
        )

        _ = try await client.mutation(
            "messages.toggleReaction",
            input: .object([
                "messageId": .int(messageId),
                "emoji": .string("thumbsup")
            ])
        )

        // typing and read receipts must be accepted without error
        _ = try await client.mutation(
            "messages.signalTyping",
            input: .object(["channelId": .int(textChannel.id)])
        )
        _ = try await client.mutation(
            "channels.markAsRead",
            input: .object(["channelId": .int(textChannel.id)])
        )

        let edited = try await fetchMessage(client, channelId: textChannel.id, messageId: messageId)
        #expect(edited?.content?.contains("edited") == true)
        #expect(edited?.reactions?.contains { $0.emoji == "thumbsup" } == true)

        // direct message: pick any other user on the server
        if let other = join.users.first(where: { $0.id != join.ownUserId && !$0.banned }) {
            let dm = try await client.mutation(
                "dms.open",
                input: .object(["userId": .int(other.id)])
            ).decode(OpenDirectMessageResult.self)

            #expect(dm.channelId > 0)
        }

        _ = try await client.mutation(
            "messages.delete",
            input: .object(["messageId": .int(messageId)])
        )

        let afterDelete = try await fetchMessage(client, channelId: textChannel.id, messageId: messageId)
        #expect(afterDelete == nil)
    }

    private func fetchMessage(
        _ client: TRPCWebSocketClient,
        channelId: Int,
        messageId: Int
    ) async throws -> SharkordMessage? {
        let page = try await client.query(
            "messages.get",
            input: .object([
                "channelId": .int(channelId),
                "limit": .int(100)
            ])
        ).decode(MessagesPage.self)

        return page.messages.first { $0.id == messageId }
    }

    /// Returns the first stream element, or nil if `timeout` elapses first.
    private static func firstEvent(
        _ stream: AsyncThrowingStream<JSONValue, Error>,
        timeout: TimeInterval
    ) async throws -> JSONValue? {
        try await withThrowingTaskGroup(of: JSONValue?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()

                return try await iterator.next()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                return nil
            }

            let first = try await group.next() ?? nil
            group.cancelAll()

            return first
        }
    }
}
