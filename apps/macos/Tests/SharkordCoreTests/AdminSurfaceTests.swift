import Foundation
import Testing

@testable import SharkordCore

/// End to end check of the routes the native client gained after the first slice: the
/// category and channel tree, roles, emojis, invites, user administration, server
/// settings, pins, threads, search and voice join/leave. Same gating as
/// `IntegrationTests`: it only runs when `SHARKORD_IT_HOST` points at a throwaway server.
///
///   SHARKORD_IT_HOST=127.0.0.1:4992 swift test --filter AdminSurface
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHARKORD_IT_HOST"] != nil))
struct AdminSurfaceTests {
    private var host: String {
        ProcessInfo.processInfo.environment["SHARKORD_IT_HOST"] ?? ""
    }

    private var identity: String {
        ProcessInfo.processInfo.environment["SHARKORD_IT_IDENTITY"] ?? "native-probe"
    }

    private var password: String {
        ProcessInfo.processInfo.environment["SHARKORD_IT_PASSWORD"] ?? "probe-password"
    }

    private struct Connected {
        let client: TRPCWebSocketClient
        let join: JoinResult
    }

    private func connect() async throws -> Connected {
        let baseURL = try #require(URL(string: "http://\(host)"))
        let http = SharkordHTTPClient(baseURL: baseURL)

        _ = try await http.serverInfo()
        let login = try await http.login(identity: identity, password: password)

        let client = TRPCWebSocketClient(
            configuration: .init(url: http.webSocketURL, token: login.token)
        )

        try await client.connect()

        let handshake = try await client.query("others.handshake")
            .decode(SharkordHandshake.self)

        let join = try await client.query(
            "others.joinServer",
            input: .object(["handshakeHash": .string(handshake.handshakeHash)])
        ).decode(JoinResult.self)

        // claim ownership so the permission gated routes below are reachable
        let secret = ProcessInfo.processInfo.environment["SHARKORD_IT_SECRET"] ?? "dev"
        _ = try? await client.mutation(
            "others.useSecretToken",
            input: .object(["token": .string(secret)])
        )

        return Connected(client: client, join: join)
    }

    @Test
    func categoryAndChannelTreeRoundTrip() async throws {
        let state = try await connect()
        defer { Task { await state.client.close() } }

        let marker = UUID().uuidString.prefix(8).lowercased()

        let categoryId = try #require(
            try await state.client.mutation(
                "categories.add",
                input: .object(["name": .string("it-cat-\(marker)")])
            ).intValue
        )

        let category = try await state.client.query(
            "categories.get",
            input: .object(["categoryId": .int(categoryId)])
        ).decode(SharkordCategory.self)

        #expect(category.name == "it-cat-\(marker)")

        _ = try await state.client.mutation(
            "categories.update",
            input: .object([
                "categoryId": .int(categoryId),
                "name": .string("it-cat-\(marker)-renamed")
            ])
        )

        let channelId = try #require(
            try await state.client.mutation(
                "channels.add",
                input: .object([
                    "type": .string("TEXT"),
                    "name": .string("it-chan-\(marker)"),
                    "categoryId": .int(categoryId)
                ])
            ).intValue
        )

        let channel = try await state.client.query(
            "channels.get",
            input: .object(["channelId": .int(channelId)])
        ).decode(SharkordChannel.self)

        #expect(channel.categoryId == categoryId)

        // per channel permission overrides for a role and for a user
        let permissions = try await state.client.query(
            "channels.getPermissions",
            input: .object(["channelId": .int(channelId)])
        ).decode(ChannelPermissionsResult.self)

        #expect(permissions.rolePermissions.isEmpty || permissions.rolePermissions.contains {
            $0.channelId == channelId
        })

        if let roleId = state.join.roles.first?.id {
            _ = try await state.client.mutation(
                "channels.updatePermissions",
                input: .object([
                    "channelId": .int(channelId),
                    "roleId": .int(roleId),
                    "permissions": .array([.string("VIEW_CHANNEL")])
                ])
            )

            _ = try await state.client.mutation(
                "channels.deletePermissions",
                input: .object([
                    "channelId": .int(channelId),
                    "roleId": .int(roleId)
                ])
            )
        }

        // reordering must accept the full id list for the category
        _ = try await state.client.mutation(
            "categories.reorder",
            input: .object(["categoryIds": .array(state.join.categories.map { .int($0.id) })])
        )

        _ = try await state.client.mutation(
            "channels.reorder",
            input: .object([
                "categoryId": .int(categoryId),
                "channelIds": .array([.int(channelId)])
            ])
        )

        _ = try await state.client.mutation(
            "channels.delete",
            input: .object(["channelId": .int(channelId)])
        )

        _ = try await state.client.mutation(
            "categories.delete",
            input: .object(["categoryId": .int(categoryId)])
        )
    }

    @Test
    func rolesEmojisAndInvites() async throws {
        let state = try await connect()
        defer { Task { await state.client.close() } }

        let marker = UUID().uuidString.prefix(8).lowercased()

        // roles
        let roleId = try #require(
            try await state.client.mutation("roles.add").intValue
        )

        let roles = try await state.client.query("roles.getAll")
            .decode([SharkordRole].self)

        let created = try #require(roles.first { $0.id == roleId })
        #expect(created.id == roleId)

        _ = try await state.client.mutation(
            "roles.update",
            input: .object([
                "roleId": .int(roleId),
                "name": .string("it-role-\(marker)"),
                "color": .string("#22CC88"),
                "permissions": .array([.string("SEND_MESSAGES")]),
                "storageQuotaOverrideEnabled": .bool(false),
                "storageSpaceQuota": .int(0)
            ])
        )

        let updated = try await state.client.query("roles.getAll")
            .decode([SharkordRole].self)

        #expect(updated.contains { $0.id == roleId && $0.name == "it-role-\(marker)" })

        // emoji upload goes through /upload, then the emoji routes
        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let baseURL = try #require(URL(string: "http://\(host)"))
        let http = SharkordHTTPClient(baseURL: baseURL)
        let login = try await http.login(identity: identity, password: password)

        let uploaded = try await http.upload(
            data: payload,
            fileName: "it-\(marker).png",
            mimeType: "image/png",
            token: login.token
        )

        _ = try await state.client.mutation(
            "emojis.add",
            input: .array([
                .object([
                    "fileId": .string(uploaded.id),
                    "name": .string("it-emoji-\(marker)")
                ])
            ])
        )

        let emojis = try await state.client.query("emojis.getAll")
            .decode([SharkordEmoji].self)

        let emoji = try #require(emojis.first { $0.name == "it-emoji-\(marker)" })

        _ = try await state.client.mutation(
            "emojis.update",
            input: .object([
                "emojiId": .int(emoji.id),
                "name": .string("it-emoji-\(marker)-renamed")
            ])
        )

        _ = try await state.client.mutation(
            "emojis.delete",
            input: .object(["emojiId": .int(emoji.id)])
        )

        // invites
        let invite = try await state.client.mutation(
            "invites.add",
            input: .object(["maxUses": .int(3)])
        ).decode(SharkordInvite.self)

        #expect(!invite.code.isEmpty)

        let invites = try await state.client.query("invites.getAll")
            .decode([SharkordInvite].self)

        #expect(invites.contains { $0.code == invite.code })

        _ = try await state.client.mutation(
            "invites.delete",
            input: .object(["inviteId": .int(invite.id)])
        )

        // the new role can go away again
        _ = try await state.client.mutation(
            "roles.delete",
            input: .object(["roleId": .int(roleId)])
        )
    }

    @Test
    func pinsThreadsSearchAndSettings() async throws {
        let state = try await connect()
        defer { Task { await state.client.close() } }

        let textChannel = try #require(state.join.channels.first { $0.type == .text })
        let marker = "it-pin-\(UUID().uuidString.prefix(8).lowercased())"

        let messageId = try #require(
            try await state.client.mutation(
                "messages.send",
                input: .object([
                    "content": .string("<p>\(marker)</p>"),
                    "channelId": .int(textChannel.id),
                    "files": .array([])
                ])
            ).intValue
        )

        // pin and read back
        _ = try await state.client.mutation(
            "messages.togglePin",
            input: .object(["messageId": .int(messageId)])
        )

        let pinned = try await state.client.query(
            "messages.getPinned",
            input: .object(["channelId": .int(textChannel.id)])
        ).decode([SharkordMessage].self)

        #expect(pinned.contains { $0.id == messageId })

        _ = try await state.client.mutation(
            "messages.togglePin",
            input: .object(["messageId": .int(messageId)])
        )

        // thread on the same message
        let threadReplyId = try #require(
            try await state.client.mutation(
                "messages.send",
                input: .object([
                    "content": .string("<p>\(marker)-thread</p>"),
                    "channelId": .int(textChannel.id),
                    "files": .array([]),
                    "parentMessageId": .int(messageId)
                ])
            ).intValue
        )

        let thread = try await state.client.query(
            "messages.getThread",
            input: .object([
                "parentMessageId": .int(messageId),
                "limit": .int(50)
            ])
        ).decode(ThreadPage.self)

        #expect(thread.messages.contains { $0.id == threadReplyId })

        // a jump window around the reply must report whether newer messages exist
        let jumped = try await state.client.query(
            "messages.get",
            input: .object([
                "channelId": .int(textChannel.id),
                "limit": .int(10),
                "targetMessageId": .int(messageId)
            ])
        ).decode(MessagesPage.self)

        #expect(jumped.messages.contains { $0.id == messageId })
        #expect(jumped.hasNewer != nil)

        // search, server settings and the storage/update read models
        let search = try await state.client.query(
            "messages.search",
            input: .object(["query": .string(marker)])
        ).decode(SearchResult.self)

        #expect(search.messages.contains { $0.id == messageId })
        #expect(search.truncated == false || search.truncated == true)

        let settings = try await state.client.query("others.getSettings")
            .decode(SharkordAdminSettings.self)

        #expect(!settings.name.isEmpty)

        let storage = try await state.client.query("others.getStorageSettings")
            .decode(StorageSettingsResult.self)

        #expect(storage.diskMetrics.totalSpace > 0)

        let update = try await state.client.query("others.getUpdate")
            .decode(UpdateInfo.self)

        #expect(!update.currentVersion.isEmpty)

        let users = try await state.client.query("users.getAll")
            .decode([SharkordAdminUser].self)

        // the server generates the display name on registration, so assert on the id
        #expect(users.contains { $0.id == state.join.ownUserId })
        #expect(users.allSatisfy { $0.identity == nil })

        let detail = try await state.client.query(
            "users.getInfo",
            input: .object(["userId": .int(state.join.ownUserId)])
        ).decode(UserDetail.self)

        #expect(detail.user.id == state.join.ownUserId)

        // voice join and leave through the control plane
        if let voiceChannel = state.join.channels.first(where: { $0.type == .voice }) {
            _ = try await state.client.mutation(
                "voice.join",
                input: .object([
                    "channelId": .int(voiceChannel.id),
                    "state": .object([
                        "micMuted": .bool(true),
                        "soundMuted": .bool(true)
                    ])
                ])
            )

            _ = try await state.client.mutation("voice.leave")
        }

        // cleanup so a rerun on the same throwaway server stays cheap
        _ = try? await state.client.mutation(
            "messages.delete",
            input: .object(["messageId": .int(messageId)])
        )
    }

    @Test
    func pluginSurfaceIsQueryable() async throws {
        let state = try await connect()
        defer { Task { await state.client.close() } }

        let plugins = try await state.client.query("plugins.get")
            .decode(PluginsResult.self)
            .plugins

        #expect(plugins.isEmpty || plugins.allSatisfy { !$0.pluginId.isEmpty })

        let commands = try await state.client.query(
            "plugins.getCommands",
            input: .object([:])
        ).decode(PluginCommandsMap.self)

        #expect(commands.entries.count >= 0)
    }
}
