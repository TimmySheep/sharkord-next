import Foundation

/// Owns one connection to one server: login, handshake, join, every live subscription and
/// the client side state the UI reads. This is the piece `apps/apple-mobile` would share
/// once it grows a real session layer (`packages/apple-core` in the strategy document).
@MainActor
public final class SharkordSession: ObservableObject {
    public enum Phase: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    public struct Credentials: Sendable {
        public let host: String
        public let identity: String
        public let password: String
        public let serverPassword: String?
        public let invite: String?
    }

    @Published public private(set) var phase: Phase = .disconnected
    @Published public private(set) var serverInfo: SharkordServerInfo?
    @Published public private(set) var serverName: String = ""
    @Published public private(set) var categories: [SharkordCategory] = []
    @Published public private(set) var channels: [SharkordChannel] = []
    @Published public private(set) var users: [SharkordUser] = []
    @Published public private(set) var roles: [SharkordRole] = []
    @Published public private(set) var emojis: [SharkordEmoji] = []
    @Published public private(set) var settings: SharkordSettings?
    @Published public internal(set) var directMessages: [DirectMessageConversation] = []
    @Published public private(set) var ownUserId: Int = 0
    @Published public private(set) var selectedChannelId: Int?
    @Published public private(set) var messagesByChannel: [Int: [SharkordMessage]] = [:]
    @Published public private(set) var hasMoreOlderByChannel: [Int: Bool] = [:]
    @Published public private(set) var isLoadingMore: Set<Int> = []
    @Published public private(set) var unreadByChannel: [Int: Int] = [:]
    @Published public private(set) var typingByChannel: [Int: [Int: Date]] = [:]
    @Published public private(set) var replyCounts: [Int: Int] = [:]
    @Published public private(set) var lastError: String?

    private(set) var http: SharkordHTTPClient?
    private(set) var client: TRPCWebSocketClient?
    private(set) var token: String?
    private var credentials: Credentials?
    private var reconnectAttempt = 0
    private var isStopping = false
    var subscriptionTasks: [Task<Void, Never>] = []
    private var cursors: [Int: MessagesCursor] = [:]
    private var loadedChannels: Set<Int> = []
    private let keychain = KeychainTokenStore()

    static let reconnectDelays: [UInt64] = [1, 2, 4, 8, 8]

    public init() {}

    // MARK: - derived reads

    public var ownUser: SharkordUser? {
        users.first { $0.id == ownUserId }
    }

    public var textChannels: [SharkordChannel] {
        channels.filter { $0.type == .text && !$0.isDm }
    }

    public var voiceChannels: [SharkordChannel] {
        channels.filter { $0.type == .voice && !$0.isDm }
    }

    public var directMessageChannels: [SharkordChannel] {
        channels
            .filter(\.isDm)
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func channels(in category: SharkordCategory) -> [SharkordChannel] {
        channels
            .filter { $0.categoryId == category.id }
            .sorted { $0.position < $1.position }
    }

    public func channel(for id: Int) -> SharkordChannel? {
        channels.first { $0.id == id }
    }

    public func user(for id: Int) -> SharkordUser? {
        users.first { $0.id == id }
    }

    public func publicFileURL(for file: SharkordFile) -> URL? {
        http?.publicFileURL(for: file)
    }

    /// Reactions of a message grouped into one chip per emoji.
    public func reactionGroups(for message: SharkordMessage) -> [ReactionGroup] {
        let reactions = message.reactions ?? []

        var grouped: [String: (count: Int, mine: Bool, file: SharkordFile?)] = [:]

        for reaction in reactions {
            let current = grouped[reaction.emoji] ?? (0, false, nil)
            grouped[reaction.emoji] = (
                current.count + 1,
                current.mine || reaction.userId == ownUserId,
                reaction.file ?? current.file
            )
        }

        return grouped
            .map { ReactionGroup(emoji: $0.key, count: $0.value.count, mine: $0.value.mine, file: $0.value.file) }
            .sorted { $0.emoji < $1.emoji }
    }

    /// Users currently typing in a channel, excluding the viewer.
    public func typingUsers(in channelId: Int) -> [SharkordUser] {
        let now = Date()
        let entries = typingByChannel[channelId] ?? [:]

        return entries
            .filter { $0.key != ownUserId && now.timeIntervalSince($0.value) < ProtocolDefaults.typingWindow }
            .compactMap { user(for: $0.key) }
    }

    public func replyCount(for message: SharkordMessage) -> Int {
        replyCounts[message.id] ?? message.replyCount ?? 0
    }

    // MARK: - connect

    public func connect(
        host: String,
        identity: String,
        password: String,
        serverPassword: String? = nil,
        invite: String? = nil
    ) async {
        guard let baseURL = Self.normalize(host: host) else {
            phase = .failed("Enter a valid server address")
            return
        }

        isStopping = false
        reconnectAttempt = 0
        phase = .connecting
        lastError = nil

        let credentials = Credentials(
            host: baseURL.absoluteString,
            identity: identity,
            password: password,
            serverPassword: serverPassword,
            invite: invite
        )

        do {
            let http = SharkordHTTPClient(baseURL: baseURL)
            self.http = http

            serverInfo = try await http.serverInfo()

            let login = try await http.login(
                identity: identity,
                password: password,
                invite: invite
            )

            token = login.token
            self.credentials = credentials
            keychain.setToken(login.token, for: baseURL.absoluteString)

            try await establish(baseURL: baseURL, token: login.token)
            phase = .connected
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    public func disconnect() {
        isStopping = true
        subscriptionTasks.forEach { $0.cancel() }
        subscriptionTasks.removeAll()

        let client = self.client
        self.client = nil

        Task {
            await client?.close()
        }

        if let host = credentials?.host {
            keychain.deleteToken(for: host)
        }

        token = nil
        credentials = nil
        http = nil
        serverInfo = nil
        serverName = ""
        categories = []
        channels = []
        users = []
        roles = []
        emojis = []
        settings = nil
        directMessages = []
        ownUserId = 0
        selectedChannelId = nil
        messagesByChannel = [:]
        hasMoreOlderByChannel = [:]
        unreadByChannel = [:]
        typingByChannel = [:]
        replyCounts = [:]
        cursors = [:]
        loadedChannels = []
        phase = .disconnected
    }

    private func establish(baseURL: URL, token: String) async throws {
        let client = TRPCWebSocketClient(
            configuration: .init(url: SharkordHTTPClient(baseURL: baseURL).webSocketURL, token: token)
        )

        await client.setDisconnectHandler { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleUnexpectedDisconnect(error)
            }
        }

        try await client.connect()
        self.client = client

        let handshakeValue = try await client.query("others.handshake")
        let handshake = try handshakeValue.decode(SharkordHandshake.self)

        var joinInput: [String: JSONValue] = [
            "handshakeHash": .string(handshake.handshakeHash)
        ]

        if handshake.hasPassword, let serverPassword = credentials?.serverPassword, !serverPassword.isEmpty {
            joinInput["password"] = .string(serverPassword)
        }

        let joinValue = try await client.query("others.joinServer", input: .object(joinInput))
        let join = try joinValue.decode(JoinResult.self)

        apply(join)
        startSubscriptions(client: client)
        reconnectAttempt = 0

        await loadDirectMessagesQuietly()
    }

    private func apply(_ join: JoinResult) {
        categories = join.categories.sorted { $0.position < $1.position }
        channels = join.channels
        users = join.users.sorted { $0.name.lowercased() < $1.name.lowercased() }
        roles = join.roles
        emojis = join.emojis ?? []
        settings = join.publicSettings
        ownUserId = join.ownUserId
        serverName = join.serverName

        if let readStates = join.readStates {
            unreadByChannel = readStates.reduce(into: [:]) { result, entry in
                if let channelId = Int(entry.key) {
                    result[channelId] = entry.value
                }
            }
        }

        if selectedChannelId == nil, let first = textChannels.first ?? directMessageChannels.first {
            selectedChannelId = first.id
        }
    }

    // MARK: - subscriptions

    private func startSubscriptions(client: TRPCWebSocketClient) {
        subscriptionTasks.forEach { $0.cancel() }

        subscribe(client, "messages.onNew") { [weak self] value in
            guard let message = try? value.decode(SharkordMessage.self) else { return }
            self?.upsert(message, markUnread: message.userId != self?.ownUserId)
        }

        subscribe(client, "messages.onUpdate") { [weak self] value in
            guard let message = try? value.decode(SharkordMessage.self) else { return }
            self?.upsert(message, markUnread: false)
        }

        subscribe(client, "messages.onDelete") { [weak self] value in
            guard let channelId = value["channelId"]?.intValue, let messageId = value["messageId"]?.intValue else { return }
            self?.removeMessage(id: messageId, channelId: channelId)
        }

        subscribe(client, "messages.onTyping") { [weak self] value in
            guard let event = try? value.decode(TypingEvent.self) else { return }
            self?.typingByChannel[event.channelId, default: [:]][event.userId] = Date()
        }

        subscribe(client, "messages.onThreadReplyCountUpdate") { [weak self] value in
            guard let update = try? value.decode(ReplyCountUpdate.self) else { return }
            self?.replyCounts[update.messageId] = update.replyCount
        }

        subscribe(client, "users.onJoin") { [weak self] value in
            guard let user = try? value.decode(SharkordUser.self) else { return }
            self?.upsert(user: user, online: true)
        }

        subscribe(client, "users.onLeave") { [weak self] value in
            if let userId = value.intValue {
                self?.setStatus(userId: userId, status: .offline)
            } else if let userId = value["id"]?.intValue {
                self?.setStatus(userId: userId, status: .offline)
            }
        }

        subscribe(client, "users.onUpdate") { [weak self] value in
            guard let user = try? value.decode(SharkordUser.self) else { return }
            self?.upsert(user: user, online: nil)
        }

        subscribe(client, "users.onCreate") { [weak self] value in
            guard let user = try? value.decode(SharkordUser.self) else { return }
            self?.upsert(user: user, online: user.status == .online)
        }

        subscribe(client, "users.onDelete") { [weak self] value in
            if let userId = value.intValue {
                self?.removeUser(userId)
            } else if let userId = value["id"]?.intValue {
                self?.removeUser(userId)
            }
        }

        subscribe(client, "channels.onCreate") { [weak self] value in
            guard let channel = try? value.decode(SharkordChannel.self) else { return }
            self?.upsert(channel: channel)
        }

        subscribe(client, "channels.onUpdate") { [weak self] value in
            guard let channel = try? value.decode(SharkordChannel.self) else { return }
            self?.upsert(channel: channel)
        }

        subscribe(client, "channels.onDelete") { [weak self] value in
            if let channelId = value.intValue {
                self?.removeChannel(channelId)
            }
        }

        subscribe(client, "channels.onReadStateUpdate") { [weak self] value in
            guard let update = try? value.decode(ReadStateUpdate.self) else { return }
            self?.unreadByChannel[update.channelId] = update.count
        }

        subscribe(client, "channels.onReadStateDelta") { [weak self] value in
            guard let delta = try? value.decode(ReadStateDelta.self) else { return }
            self?.applyUnreadDelta(channelId: delta.channelId, delta: delta.delta)
        }

        subscribe(client, "categories.onCreate") { [weak self] value in
            guard let category = try? value.decode(SharkordCategory.self) else { return }
            self?.upsert(category: category)
        }

        subscribe(client, "categories.onUpdate") { [weak self] value in
            guard let category = try? value.decode(SharkordCategory.self) else { return }
            self?.upsert(category: category)
        }

        subscribe(client, "categories.onDelete") { [weak self] value in
            if let categoryId = value.intValue {
                self?.categories.removeAll { $0.id == categoryId }
            }
        }

        subscribe(client, "emojis.onCreate") { [weak self] value in
            guard let emoji = try? value.decode(SharkordEmoji.self) else { return }
            self?.upsert(emoji: emoji)
        }

        subscribe(client, "emojis.onUpdate") { [weak self] value in
            guard let emoji = try? value.decode(SharkordEmoji.self) else { return }
            self?.upsert(emoji: emoji)
        }

        subscribe(client, "emojis.onDelete") { [weak self] value in
            if let emojiId = value.intValue {
                self?.emojis.removeAll { $0.id == emojiId }
            }
        }

        subscribe(client, "roles.onCreate") { [weak self] value in
            guard let role = try? value.decode(SharkordRole.self) else { return }
            self?.upsert(role: role)
        }

        subscribe(client, "roles.onUpdate") { [weak self] value in
            guard let role = try? value.decode(SharkordRole.self) else { return }
            self?.upsert(role: role)
        }

        subscribe(client, "roles.onDelete") { [weak self] value in
            if let roleId = value.intValue {
                self?.roles.removeAll { $0.id == roleId }
            }
        }

        subscribe(client, "others.onServerSettingsUpdate") { [weak self] value in
            guard let settings = try? value.decode(SharkordSettings.self) else { return }
            self?.settings = settings
        }

        subscribe(client, "dms.onConversationOpen") { [weak self] value in
            Task { await self?.loadDirectMessagesQuietly() }
        }
    }

    private func subscribe(
        _ client: TRPCWebSocketClient,
        _ path: String,
        _ handler: @escaping @MainActor (JSONValue) -> Void
    ) {
        subscriptionTasks.append(Task { [weak self] in
            let stream = await client.subscribe(path)
            await self?.consume(stream, onValue: handler)
        })
    }

    private func consume(
        _ stream: AsyncThrowingStream<JSONValue, Error>,
        onValue: @escaping @MainActor (JSONValue) -> Void
    ) async {
        do {
            for try await value in stream {
                onValue(value)
            }
        } catch {
            // the transport surfaces disconnects through the disconnect handler
        }
    }

    // MARK: - state mutators

    private func upsert(_ message: SharkordMessage, markUnread: Bool) {
        var list = messagesByChannel[message.channelId] ?? []

        if let index = list.firstIndex(where: { $0.id == message.id }) {
            list[index] = message
        } else if message.parentMessageId == nil {
            list.append(message)
            list.sort { $0.createdAt < $1.createdAt }
        } else {
            return
        }

        messagesByChannel[message.channelId] = list

        if markUnread, message.channelId != selectedChannelId {
            unreadByChannel[message.channelId, default: 0] += 1
        }
    }

    private func removeMessage(id: Int, channelId: Int) {
        guard var list = messagesByChannel[channelId] else { return }
        list.removeAll { $0.id == id }
        messagesByChannel[channelId] = list
    }

    private func upsert(user: SharkordUser, online: Bool?) {
        var updated = user

        if let online {
            updated = user.withStatus(online ? .online : .offline)
        }

        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = updated
        } else if let online, online {
            users.append(updated)
            users.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    private func setStatus(userId: Int, status: UserStatus) {
        guard let index = users.firstIndex(where: { $0.id == userId }) else { return }
        users[index] = users[index].withStatus(status)
    }

    private func removeUser(_ userId: Int) {
        users.removeAll { $0.id == userId }
    }

    private func upsert(channel: SharkordChannel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[index] = channel
        } else {
            channels.append(channel)
        }
    }

    private func removeChannel(_ channelId: Int) {
        channels.removeAll { $0.id == channelId }
        messagesByChannel[channelId] = nil
        unreadByChannel[channelId] = nil

        if selectedChannelId == channelId {
            selectedChannelId = textChannels.first?.id ?? directMessageChannels.first?.id
        }
    }

    private func upsert(category: SharkordCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }

        categories.sort { $0.position < $1.position }
    }

    private func upsert(emoji: SharkordEmoji) {
        if let index = emojis.firstIndex(where: { $0.id == emoji.id }) {
            emojis[index] = emoji
        } else {
            emojis.append(emoji)
        }
    }

    private func upsert(role: SharkordRole) {
        if let index = roles.firstIndex(where: { $0.id == role.id }) {
            roles[index] = role
        } else {
            roles.append(role)
        }
    }

    private func applyUnreadDelta(channelId: Int, delta: Int) {
        guard channelId != selectedChannelId else { return }
        unreadByChannel[channelId, default: 0] = max(0, (unreadByChannel[channelId] ?? 0) + delta)
    }

    /// Clears the unread badge locally; the server is told separately by `markAsRead`.
    func clearUnread(_ channelId: Int) {
        unreadByChannel[channelId] = 0
    }

    // MARK: - channel selection + history

    public func select(channelId: Int) async {
        selectedChannelId = channelId

        guard !loadedChannels.contains(channelId) else {
            markAsRead(channelId)
            return
        }

        loadedChannels.insert(channelId)

        do {
            try await load(channelId: channelId, cursor: nil)
            markAsRead(channelId)
        } catch {
            lastError = Self.describe(error)
            loadedChannels.remove(channelId)
        }
    }

    public func loadOlder(channelId: Int) async {
        guard
            !isLoadingMore.contains(channelId),
            hasMoreOlderByChannel[channelId] == true,
            let cursor = cursors[channelId]
        else {
            return
        }

        isLoadingMore.insert(channelId)
        defer { isLoadingMore.remove(channelId) }

        do {
            try await load(channelId: channelId, cursor: cursor)
        } catch {
            lastError = Self.describe(error)
        }
    }

    private func load(channelId: Int, cursor: MessagesCursor?) async throws {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        var input: [String: JSONValue] = [
            "channelId": .int(channelId),
            "limit": .int(ProtocolDefaults.messagesLimit)
        ]

        if let cursor {
            input["cursor"] = .object([
                "createdAt": .int(cursor.createdAt),
                "id": .int(cursor.id)
            ])
        }

        let value = try await client.query("messages.get", input: .object(input))
        let page = try value.decode(MessagesPage.self)

        let ascending = page.messages.sorted { $0.createdAt < $1.createdAt }

        if cursor == nil {
            messagesByChannel[channelId] = ascending
        } else if !ascending.isEmpty {
            let existing = messagesByChannel[channelId] ?? []
            let existingIds = Set(existing.map(\.id))
            let older = ascending.filter { !existingIds.contains($0.id) }
            messagesByChannel[channelId] = older + existing
        }

        cursors[channelId] = page.nextCursor
        hasMoreOlderByChannel[channelId] = page.nextCursor != nil
    }

    // MARK: - reconnect

    private func handleUnexpectedDisconnect(_ error: Error?) {
        guard !isStopping, phase == .connected || phase == .connecting else { return }

        guard let credentials, let token else {
            phase = .failed(Self.describe(error))
            return
        }

        if reconnectAttempt >= Self.reconnectDelays.count {
            phase = .failed("Connection lost")
            return
        }

        phase = .connecting

        Task { [weak self] in
            guard let self else { return }

            let delay = Self.reconnectDelays[min(self.reconnectAttempt, Self.reconnectDelays.count - 1)]
            self.reconnectAttempt += 1

            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)

            guard !self.isStopping, let baseURL = URL(string: credentials.host) else { return }

            do {
                try await self.establish(baseURL: baseURL, token: token)
                self.phase = .connected
                self.reconnectAttempt = 0
            } catch {
                self.handleUnexpectedDisconnect(error)
            }
        }
    }

    // MARK: - helpers

    static func normalize(host: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"

        guard let url = URL(string: withScheme), let scheme = url.scheme, let host = url.host else {
            return nil
        }

        guard scheme == "http" || scheme == "https", !host.isEmpty else { return nil }

        return url
    }

    static func describe(_ error: Error?) -> String {
        guard let error else { return "Unknown error" }

        if let trpc = error as? TRPCClientError {
            return trpc.message
        }

        if let http = error as? SharkordHTTPError {
            return http.message
        }

        return error.localizedDescription
    }
}
