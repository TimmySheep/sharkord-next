import Foundation
import Testing

@testable import SharkordCore

enum LocalIntegrationServer {
    static var configuredURL: URL? {
        baseURL(for: ProcessInfo.processInfo.environment["SHARKORD_IT_HOST"])
    }

    static func baseURL(for host: String?) -> URL? {
        guard let host else { return nil }
        let authority = host == "::1" ? "[::1]" : host
        // validate the raw authority so URL parsing cannot reinterpret user info or a path
        guard authority.range(
            of: #"\A(?:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]{1,5})?\z"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil, let components = URLComponents(string: "http://\(authority)") else { return nil }
        if let port = components.port, !(1...65535).contains(port) { return nil }
        return components.url
    }
}

struct LocalIntegrationHostTests {
    @Test func destructiveSuitesAcceptOnlyExplicitLoopbackHosts() {
        for host in [
            "localhost", "LOCALHOST:4992", "localhost:65535", "127.0.0.1", "127.0.0.1:4992",
            "::1", "[::1]", "[::1]:4992"
        ] {
            #expect(LocalIntegrationServer.baseURL(for: host) != nil)
        }
        #expect(LocalIntegrationServer.baseURL(for: nil) == nil)
        for host in [
            "", "voice.timhuang.net", "voice.timhuang.net:443", "https://voice.timhuang.net",
            "127.0.0.1.voice.timhuang.net", "localhost@voice.timhuang.net", "voice.timhuang.net@localhost",
            "http://localhost:4992", "127.0.0.2", "127.1", "[::ffff:127.0.0.1]",
            "localhost/path", "localhost?host=voice.timhuang.net", "localhost#fragment",
            "localhost:0", "localhost:65536", "localhost:999999", "localhost:\\4992",
            " localhost", "localhost\n"
        ] {
            #expect(LocalIntegrationServer.baseURL(for: host) == nil)
        }
    }
}

/// end to end checks for a disposable local server only. SHARKORD_IT_HOST must be an
/// explicit loopback host; both the suite and each connection enforce the same allowlist.
/// these tests register users and mutate shared state, so never use an active local server.
///
///   SHARKORD_IT_HOST=127.0.0.1:4992 swift test --filter IntegrationTests
@Suite(.enabled(if: LocalIntegrationServer.configuredURL != nil))
struct IntegrationTests {
    private var identity: String {
        ProcessInfo.processInfo.environment["SHARKORD_IT_IDENTITY"] ?? "native-probe"
    }

    private var password: String {
        ProcessInfo.processInfo.environment["SHARKORD_IT_PASSWORD"] ?? "probe-password"
    }

    @Test
    func loginJoinSendAndReceive() async throws {
        let baseURL = try #require(LocalIntegrationServer.configuredURL)
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
        let baseURL = try #require(LocalIntegrationServer.configuredURL)
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
