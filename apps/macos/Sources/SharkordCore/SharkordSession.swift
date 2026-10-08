import Foundation

/// Owns one connection to one server: login, handshake, join, every live subscription and
/// the client side state the UI reads. This is the piece `apps/apple-mobile` would share
/// once it grows a real session layer (`packages/apple-core` in the strategy document).
@MainActor
public final class SharkordSession: ObservableObject {
    public enum Phase: Equatable {
        case disconnected
        case connecting
        case awaitingServerPassword
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

    // MARK: observable state

    @Published public internal(set) var phase: Phase = .disconnected
    @Published public internal(set) var serverInfo: SharkordServerInfo?
    @Published public internal(set) var serverId: String = ""
    @Published public internal(set) var serverName: String = ""
    @Published public internal(set) var categories: [SharkordCategory] = []
    @Published public internal(set) var channels: [SharkordChannel] = []
    @Published public internal(set) var users: [SharkordUser] = []
    @Published public internal(set) var roles: [SharkordRole] = []
    @Published public internal(set) var emojis: [SharkordEmoji] = []
    @Published public internal(set) var settings: SharkordSettings?
    @Published public internal(set) var directMessages: [DirectMessageConversation] = []
    @Published public internal(set) var ownUserId: Int = 0
    @Published public internal(set) var ownUserPasswordSet = false
    @Published public internal(set) var showWelcomeDialog = false
    @Published public internal(set) var channelPermissions: ChannelPermissionsMap = .init(entries: [:])
    @Published public internal(set) var voiceMap: VoiceMap = .init(entries: [:])
    @Published public internal(set) var externalStreamsMap: ExternalStreamsMap = .init(entries: [:])
    @Published public internal(set) var pluginCommands: PluginCommandsMap = .init(entries: [:])
    @Published public internal(set) var pluginIdsWithComponents: [String] = []
    @Published public internal(set) var pluginCapabilityAccess: [PluginCapabilityAccessRule] = []
    @Published public internal(set) var pluginsMetadata: [PluginMetadata] = []
    @Published public internal(set) var pluginLogs: [PluginLogEntry] = []

    @Published public internal(set) var selectedChannelId: Int?
    @Published public internal(set) var incomingMessage: SharkordMessage?
    @Published public internal(set) var messagesByChannel: [Int: [SharkordMessage]] = [:]
    @Published public internal(set) var hasMoreOlderByChannel: [Int: Bool] = [:]
    @Published public internal(set) var hasNewerByChannel: [Int: Bool] = [:]
    @Published public internal(set) var isLoadingMore: Set<Int> = []
    @Published public internal(set) var unreadByChannel: [Int: Int] = [:]
    @Published public internal(set) var typingByChannel: [Int: [Int: Date]] = [:]
    @Published public internal(set) var replyCounts: [Int: Int] = [:]
    @Published public internal(set) var pinnedByChannel: [Int: [SharkordMessage]] = [:]
    @Published public internal(set) var threadMessages: [Int: [SharkordMessage]] = [:]
    @Published public internal(set) var voiceReactions: [VoiceReactionEvent] = []
    @Published public internal(set) var producersByChannel: [Int: [VoiceProducerEvent]] = [:]
    @Published public internal(set) var pluginPushes: [PluginPushEvent] = []
    @Published public internal(set) var lastError: String?
    @Published public internal(set) var loginCredentialsSaveFailed = false

    // MARK: plumbing

    private(set) var http: SharkordHTTPClient?
    private(set) var client: TRPCWebSocketClient?
    private(set) var token: String?
    private var credentials: Credentials?
    private var voiceProducerSubscriptionTasks: [Task<Void, Never>] = []
    private var reconnectAttempt = 0
    private var isStopping = false
    private var didAttemptAutomaticLogin = false
    private var shouldRememberLoginCredentials = false
    private var pendingHandshakeHash: String?
    var subscriptionTasks: [Task<Void, Never>] = []
    private var cursors: [Int: MessagesCursor] = [:]
    private var loadedChannels: Set<Int> = []
    private let keychain = KeychainTokenStore()
    private let loginCredentialStore = KeychainLoginCredentialsStore()

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

    public func role(for id: Int) -> SharkordRole? {
        roles.first { $0.id == id }
    }

    public func emoji(named name: String) -> SharkordEmoji? {
        emojis.first { $0.name == name }
    }

    public func publicFileURL(for file: SharkordFile) -> URL? {
        http?.publicFileURL(for: file)
    }

    /// Resolves a server relative path (`/public/emoji/12`) or an absolute url, which is
    /// what message html carries for custom emoji and link previews.
    public func url(forPath path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }

        guard let base = http?.baseURL else {
            return nil
        }

        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// The origin of the connected server, for invite links and share buttons.
    public var serverBaseURL: URL? {
        http?.baseURL
    }

    // MARK: - permissions

    /// The union of the viewer's role permissions.
    public func hasPermission(_ permission: Permission) -> Bool {
        if isOwner() {
            return true
        }

        guard let ownUser, let roleIds = ownUser.roleIds else {
            return false
        }

        return roleIds.contains { roleId in
            role(for: roleId)?.allows(permission) ?? false
        }
    }

    /// Effective channel permissions the server computed for the viewer.
    public func hasChannelPermission(_ channelId: Int, _ permission: ChannelPermission) -> Bool {
        if let entry = channelPermissions[channelId] {
            return entry.allows(permission)
        }

        guard let channel = channel(for: channelId) else {
            return false
        }

        // the server includes dm channels only for participants and gives them no permission rows
        if channel.isDm {
            return true
        }

        return isOwner() || !channel.isPrivate
    }

    public var canManageUsers: Bool { hasPermission(.manageUsers) }
    public var canManageChannels: Bool { hasPermission(.manageChannels) }
    public var canManageRoles: Bool { hasPermission(.manageRoles) }
    public var canManageEmojis: Bool { hasPermission(.manageEmojis) }
    public var canManageCategories: Bool { hasPermission(.manageCategories) }
    public var canManageSettings: Bool { hasPermission(.manageSettings) }
    public var canManageStorage: Bool { hasPermission(.manageStorage) }
    public var canManageInvites: Bool { hasPermission(.manageInvites) }
    public var canManageMessages: Bool { hasPermission(.manageMessages) }
    public var canManagePlugins: Bool { hasPermission(.managePlugins) }

    /// The owner role cannot be touched by anyone who is not an owner.
    public func isOwner() -> Bool {
        ownUser?.roleIds?.contains(ProtocolDefaults.ownerRoleId) ?? false
    }

    // MARK: - message presentation helpers

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

    public func pinnedMessages(in channelId: Int) -> [SharkordMessage] {
        pinnedByChannel[channelId] ?? []
    }

    public func threadMessages(for parentMessageId: Int) -> [SharkordMessage] {
        threadMessages[parentMessageId] ?? []
    }

    /// Users currently connected to a voice channel.
    public func voiceUsers(in channelId: Int) -> [(user: SharkordUser, state: VoiceUserState)] {
        guard let channelUsers = voiceMap[channelId] else {
            return []
        }

        return channelUsers
            .states()
            .compactMap { userId, state in
                user(for: userId).map { (user: $0, state: state) }
            }
            .sorted { $0.user.name.lowercased() < $1.user.name.lowercased() }
    }

    public func isInVoice(_ channelId: Int) -> Bool {
        voiceMap[channelId]?.users.keys.contains(String(ownUserId)) ?? false
    }

    /// The channel the viewer is currently in, if any.
    public var currentVoiceChannelId: Int? {
        for (channelId, channelUsers) in voiceMap.entries where channelUsers.users.keys.contains(String(ownUserId)) {
            return channelId
        }

        return nil
    }

    // MARK: - connect

    public func connect(
        host: String,
        identity: String,
        password: String,
        serverPassword: String? = nil,
        invite: String? = nil,
        rememberLoginCredentials: Bool = false
    ) async {
        guard let baseURL = Self.normalize(host: host) else {
            ClientLogStore.shared.recordFailure("session.connect.failed", code: "invalid_server_address")
            phase = .failed("Enter a valid server address")
            return
        }

        ClientLogStore.shared.recordInfo("session.connect.started")
        isStopping = false
        reconnectAttempt = 0
        shouldRememberLoginCredentials = rememberLoginCredentials
        loginCredentialsSaveFailed = false
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
            if phase != .awaitingServerPassword {
                phase = .connected
                ClientLogStore.shared.recordInfo("session.connect.succeeded")
                saveLoginCredentialsIfNeeded()
            }
        } catch {
            ClientLogStore.shared.recordError("session.connect.failed", error: error)
            phase = .failed(Self.describe(error))
        }
    }

    public func attemptAutomaticLogin(enabled: Bool) async {
        guard !didAttemptAutomaticLogin else {
            return
        }

        didAttemptAutomaticLogin = true

        guard enabled, let saved = loginCredentialStore.credentials() else {
            return
        }

        await connect(
            host: saved.host,
            identity: saved.identity,
            password: saved.password,
            serverPassword: saved.serverPassword,
            rememberLoginCredentials: true
        )
    }

    public func updateSavedLoginPassword(_ password: String) {
        guard let current = credentials else {
            return
        }

        credentials = Credentials(
            host: current.host,
            identity: current.identity,
            password: password,
            serverPassword: current.serverPassword,
            invite: current.invite
        )

        guard shouldRememberLoginCredentials,
              let saved = loginCredentialStore.credentials(),
              saved.host == current.host,
              saved.identity == current.identity
        else {
            return
        }

        let updated = StoredLoginCredentials(
            host: saved.host,
            identity: saved.identity,
            password: password,
            serverPassword: saved.serverPassword
        )
        loginCredentialsSaveFailed = !loginCredentialStore.setCredentials(updated)
    }

    public func dismissLoginCredentialsSaveFailure() {
        loginCredentialsSaveFailed = false
    }

    private func saveLoginCredentialsIfNeeded() {
        guard shouldRememberLoginCredentials, let credentials else {
            return
        }

        let saved = StoredLoginCredentials(
            host: credentials.host,
            identity: credentials.identity,
            password: credentials.password,
            serverPassword: credentials.serverPassword
        )
        loginCredentialsSaveFailed = !loginCredentialStore.setCredentials(saved)
    }

    public func submitServerPassword(_ password: String) async {
        guard !password.isEmpty, let pendingHandshakeHash, let credentials else {
            return
        }

        self.credentials = Credentials(
            host: credentials.host,
            identity: credentials.identity,
            password: credentials.password,
            serverPassword: password,
            invite: credentials.invite
        )
        phase = .connecting
        lastError = nil

        do {
            try await finishJoin(handshakeHash: pendingHandshakeHash, password: password)
            self.pendingHandshakeHash = nil
            phase = .connected
            saveLoginCredentialsIfNeeded()
        } catch {
            ClientLogStore.shared.recordError("session.server_password.failed", error: error)
            lastError = Self.describe(error)
            phase = .awaitingServerPassword
        }
    }

    public func cancelServerPasswordPrompt() {
        disconnect()
    }

    public func disconnect() {
        isStopping = true
        subscriptionTasks.forEach { $0.cancel() }
        subscriptionTasks.removeAll()
        stopVoiceProducerSubscriptions()

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
        pendingHandshakeHash = nil
        http = nil
        serverInfo = nil
        serverId = ""
        serverName = ""
        categories = []
        channels = []
        users = []
        roles = []
        emojis = []
        settings = nil
        directMessages = []
        ownUserId = 0
        ownUserPasswordSet = false
        showWelcomeDialog = false
        channelPermissions = .init(entries: [:])
        voiceMap = .init(entries: [:])
        externalStreamsMap = .init(entries: [:])
        pluginCommands = .init(entries: [:])
        pluginIdsWithComponents = []
        pluginCapabilityAccess = []
        pluginsMetadata = []
        pluginLogs = []
        selectedChannelId = nil
        incomingMessage = nil
        messagesByChannel = [:]
        hasMoreOlderByChannel = [:]
        hasNewerByChannel = [:]
        unreadByChannel = [:]
        typingByChannel = [:]
        replyCounts = [:]
        pinnedByChannel = [:]
        threadMessages = [:]
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
        pendingHandshakeHash = handshake.handshakeHash

        if handshake.hasPassword {
            guard let serverPassword = credentials?.serverPassword, !serverPassword.isEmpty else {
                phase = .awaitingServerPassword
                return
            }

            try await finishJoin(handshakeHash: handshake.handshakeHash, password: serverPassword)
            return
        }

        try await finishJoin(handshakeHash: handshake.handshakeHash, password: nil)
    }

    private func finishJoin(handshakeHash: String, password: String?) async throws {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "The server connection is not available.")
        }

        var joinInput: [String: JSONValue] = ["handshakeHash": .string(handshakeHash)]

        if let password {
            joinInput["password"] = .string(password)
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
        ownUserPasswordSet = join.ownUserPasswordSet ?? true
        showWelcomeDialog = join.showWelcomeDialog ?? false
        serverId = join.serverId
        serverName = join.serverName
        channelPermissions = join.channelPermissions ?? .init(entries: [:])
        voiceMap = join.voiceMap ?? .init(entries: [:])
        externalStreamsMap = join.externalStreamsMap ?? .init(entries: [:])
        pluginCommands = join.commands ?? .init(entries: [:])
        pluginIdsWithComponents = join.pluginIdsWithComponents ?? []
        pluginCapabilityAccess = join.pluginCapabilityAccess ?? []
        pluginsMetadata = join.pluginsMetadata ?? []

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
        stopVoiceProducerSubscriptions()

        // messages
        subscribe(client, "messages.onNew") { [weak self] value in
            guard let message = try? value.decode(SharkordMessage.self) else { return }
            guard let self else { return }
            self.incomingMessage = message
            self.upsert(message, markUnread: message.userId != self.ownUserId)
        }

        subscribe(client, "messages.onUpdate") { [weak self] value in
            guard let message = try? value.decode(SharkordMessage.self) else { return }
            self?.upsert(message, markUnread: false)
        }

        subscribe(client, "messages.onDelete") { [weak self] value in
            guard let event = try? value.decode(MessageDeleteEvent.self) else { return }
            self?.removeMessage(id: event.messageId, channelId: event.channelId)
        }

        subscribe(client, "messages.onTyping") { [weak self] value in
            guard let event = try? value.decode(TypingEvent.self) else { return }
            self?.typingByChannel[event.channelId, default: [:]][event.userId] = Date()
        }

        subscribe(client, "messages.onThreadReplyCountUpdate") { [weak self] value in
            guard let update = try? value.decode(ReplyCountUpdate.self) else { return }
            self?.replyCounts[update.messageId] = update.replyCount
        }

        // users
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
            guard let event = try? value.decode(UserDeleteEvent.self) else { return }
            self?.removeUser(event.deletedUserId)
        }

        // channels
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

        subscribe(client, "channels.onPermissionsUpdate") { [weak self] value in
            guard let map = try? value.decode(ChannelPermissionsMap.self) else { return }
            self?.channelPermissions = map
        }

        subscribe(client, "channels.onReadStateUpdate") { [weak self] value in
            guard let update = try? value.decode(ReadStateUpdate.self) else { return }
            self?.unreadByChannel[update.channelId] = update.count
        }

        subscribe(client, "channels.onReadStateDelta") { [weak self] value in
            guard let delta = try? value.decode(ReadStateDelta.self) else { return }
            self?.applyUnreadDelta(channelId: delta.channelId, delta: delta.delta)
        }

        // categories
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

        // emojis
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

        // roles
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

        // server settings
        subscribe(client, "others.onServerSettingsUpdate") { [weak self] value in
            guard let settings = try? value.decode(SharkordSettings.self) else { return }
            self?.settings = settings
        }

        // dms
        subscribe(client, "dms.onConversationOpen") { [weak self] value in
            Task { await self?.loadDirectMessagesQuietly() }
        }

        // voice
        subscribe(client, "voice.onJoin") { [weak self] value in
            guard let event = try? value.decode(VoiceJoinEvent.self) else { return }
            self?.applyVoiceJoin(event)
        }

        subscribe(client, "voice.onLeave") { [weak self] value in
            guard let event = try? value.decode(VoiceLeaveEvent.self) else { return }
            self?.applyVoiceLeave(event)
        }

        subscribe(client, "voice.onUpdateState") { [weak self] value in
            guard let event = try? value.decode(VoiceJoinEvent.self) else { return }
            self?.applyVoiceJoin(event)
        }

        subscribe(client, "voice.onMoved") { [weak self] value in
            guard let event = try? value.decode(VoiceMovedEvent.self) else { return }
            self?.applyVoiceMoved(event)
        }

        subscribe(client, "voice.onReaction") { [weak self] value in
            guard let event = try? value.decode(VoiceReactionEvent.self) else { return }
            self?.voiceReactions.append(event)
        }

        subscribe(client, "voice.onAddExternalStream") { [weak self] value in
            self?.applyExternalStream(value)
        }

        subscribe(client, "voice.onUpdateExternalStream") { [weak self] value in
            self?.applyExternalStream(value)
        }

        subscribe(client, "voice.onRemoveExternalStream") { [weak self] value in
            guard let event = try? value.decode(VoiceExternalStreamEvent.self), let streamId = event.streamId else { return }
            self?.removeExternalStream(channelId: event.channelId, streamId: streamId)
        }

        // plugins
        subscribe(client, "plugins.onLog") { [weak self] value in
            guard let entry = try? value.decode(PluginLogEntry.self) else { return }
            self?.pluginLogs.append(entry)
        }

        subscribe(client, "plugins.onCommandsChange") { [weak self] value in
            guard let map = try? value.decode(PluginCommandsMap.self) else { return }
            self?.pluginCommands = map
        }

        subscribe(client, "plugins.onComponentsChange") { [weak self] value in
            guard let ids = try? value.decode([String].self) else { return }
            self?.pluginIdsWithComponents = ids
        }

        subscribe(client, "plugins.onCapabilityAccessChange") { [weak self] value in
            guard let rules = try? value.decode([PluginCapabilityAccessRule].self) else { return }
            self?.pluginCapabilityAccess = rules
        }

        subscribe(client, "plugins.onMetadataChange") { [weak self] value in
            guard let metadata = try? value.decode([PluginMetadata].self) else { return }
            self?.pluginsMetadata = metadata
        }

        subscribe(client, "plugins.onPush") { [weak self] value in
            guard let event = try? value.decode(PluginPushEvent.self) else { return }
            self?.pluginPushes.append(event)
        }
    }

    @discardableResult
    private func subscribe(
        _ client: TRPCWebSocketClient,
        _ path: String,
        _ handler: @escaping @MainActor (JSONValue) -> Void
    ) -> Task<Void, Never> {
        let task = makeSubscriptionTask(client, path, handler)
        subscriptionTasks.append(task)
        return task
    }

    private func makeSubscriptionTask(
        _ client: TRPCWebSocketClient,
        _ path: String,
        _ handler: @escaping @MainActor (JSONValue) -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            let stream = await client.subscribe(path)
            await self?.consume(stream, onValue: handler)
        }
    }

    func startVoiceProducerSubscriptions() {
        stopVoiceProducerSubscriptions()

        guard let client else {
            return
        }

        voiceProducerSubscriptionTasks = [
            makeSubscriptionTask(client, "voice.onNewProducer") { [weak self] value in
                guard let event = try? value.decode(VoiceProducerEvent.self) else { return }
                self?.upsertProducer(event)
            },
            makeSubscriptionTask(client, "voice.onProducerClosed") { [weak self] value in
                guard let event = try? value.decode(VoiceProducerEvent.self) else { return }
                self?.removeProducer(event)
            }
        ]
    }

    func stopVoiceProducerSubscriptions() {
        voiceProducerSubscriptionTasks.forEach { $0.cancel() }
        voiceProducerSubscriptionTasks.removeAll()
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
        if let parentMessageId = message.parentMessageId {
            var thread = threadMessages[parentMessageId] ?? []

            if let index = thread.firstIndex(where: { $0.id == message.id }) {
                thread[index] = message
            } else {
                thread.append(message)
                thread.sort { $0.createdAt < $1.createdAt }
            }

            threadMessages[parentMessageId] = thread

            if markUnread, message.channelId != selectedChannelId {
                applyUnreadDelta(channelId: message.channelId, delta: 1)
            }

            return
        }

        var list = messagesByChannel[message.channelId] ?? []

        if let index = list.firstIndex(where: { $0.id == message.id }) {
            list[index] = message
        } else {
            list.append(message)
            list.sort { $0.createdAt < $1.createdAt }
        }

        messagesByChannel[message.channelId] = list

        if message.pinned == true {
            upsertPinned(message)
        }

        if markUnread, message.channelId != selectedChannelId {
            applyUnreadDelta(channelId: message.channelId, delta: 1)
        }
    }

    private func upsertPinned(_ message: SharkordMessage) {
        var list = pinnedByChannel[message.channelId] ?? []

        if let index = list.firstIndex(where: { $0.id == message.id }) {
            list[index] = message
        } else {
            list.append(message)
            list.sort { ($0.pinnedAt ?? $0.createdAt) > ($1.pinnedAt ?? $1.createdAt) }
        }

        pinnedByChannel[message.channelId] = list
    }

    private func removeMessage(id: Int, channelId: Int) {
        guard var list = messagesByChannel[channelId] else { return }
        list.removeAll { $0.id == id }
        messagesByChannel[channelId] = list

        if var pinned = pinnedByChannel[channelId] {
            pinned.removeAll { $0.id == id }
            pinnedByChannel[channelId] = pinned
        }
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
        pinnedByChannel[channelId] = nil

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

        roles.sort { $0.id < $1.id }
    }

    private func applyUnreadDelta(channelId: Int, delta: Int) {
        guard channelId != selectedChannelId else { return }
        unreadByChannel[channelId, default: 0] = max(0, (unreadByChannel[channelId] ?? 0) + delta)
    }

    /// Clears the unread badge locally; the server is told separately by `markAsRead`.
    func clearUnread(_ channelId: Int) {
        unreadByChannel[channelId] = 0
    }

    // MARK: - voice state

    func applyVoiceJoin(_ event: VoiceJoinEvent) {
        var entries = voiceMap.entries
        var channelUsers = entries[event.channelId]?.users ?? [:]

        channelUsers[String(event.userId)] = event.state
        entries[event.channelId] = VoiceChannelUsers(users: channelUsers)
        voiceMap = VoiceMap(entries: entries)
    }

    func applyVoiceLeave(_ event: VoiceLeaveEvent) {
        var entries = voiceMap.entries

        guard var channelUsers = entries[event.channelId]?.users else {
            return
        }

        channelUsers.removeValue(forKey: String(event.userId))
        entries[event.channelId] = VoiceChannelUsers(users: channelUsers)
        voiceMap = VoiceMap(entries: entries)
    }

    private func applyVoiceMoved(_ event: VoiceMovedEvent) {
        applyVoiceLeave(VoiceLeaveEvent(channelId: event.fromChannelId, userId: ownUserId))
    }

    private func upsertProducer(_ event: VoiceProducerEvent) {
        var list = producersByChannel[event.channelId] ?? []

        if !list.contains(where: { $0.remoteId == event.remoteId && $0.kind == event.kind }) {
            list.append(event)
        }

        producersByChannel[event.channelId] = list
    }

    private func removeProducer(_ event: VoiceProducerEvent) {
        producersByChannel[event.channelId]?.removeAll {
            $0.remoteId == event.remoteId && $0.kind == event.kind
        }
    }

    private func applyExternalStream(_ value: JSONValue) {
        guard
            let event = try? value.decode(VoiceExternalStreamEvent.self),
            let streamId = event.streamId,
            let stream = event.stream
        else {
            return
        }

        var entries = externalStreamsMap.entries
        var channelStreams = entries[event.channelId] ?? [:]

        channelStreams[streamId] = stream
        entries[event.channelId] = channelStreams
        externalStreamsMap = ExternalStreamsMap(entries: entries)
    }

    private func removeExternalStream(channelId: Int, streamId: String) {
        var entries = externalStreamsMap.entries

        entries[channelId]?.removeValue(forKey: streamId)
        externalStreamsMap = ExternalStreamsMap(entries: entries)
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
            try await load(channelId: channelId, cursor: nil, targetMessageId: nil)
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
            try await load(channelId: channelId, cursor: cursor, targetMessageId: nil)
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// Loads the window around one message so the list can jump to it.
    public func jumpTo(messageId: Int, channelId: Int) async {
        selectedChannelId = channelId
        isLoadingMore.insert(channelId)
        defer { isLoadingMore.remove(channelId) }

        do {
            try await load(channelId: channelId, cursor: nil, targetMessageId: messageId)
        } catch {
            lastError = Self.describe(error)
        }
    }

    private func load(channelId: Int, cursor: MessagesCursor?, targetMessageId: Int?) async throws {
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

        if let targetMessageId {
            input["targetMessageId"] = .int(targetMessageId)
        }

        let value = try await client.query("messages.get", input: .object(input))
        let page = try value.decode(MessagesPage.self)
        let ascending = page.messages.sorted { $0.createdAt < $1.createdAt }

        if targetMessageId != nil {
            messagesByChannel[channelId] = ascending
        } else if cursor == nil {
            messagesByChannel[channelId] = ascending
        } else if !ascending.isEmpty {
            let existing = messagesByChannel[channelId] ?? []
            let existingIds = Set(existing.map(\.id))
            let older = ascending.filter { !existingIds.contains($0.id) }
            messagesByChannel[channelId] = older + existing
        }

        cursors[channelId] = page.nextCursor
        hasMoreOlderByChannel[channelId] = page.nextCursor != nil
        hasNewerByChannel[channelId] = page.hasNewer ?? false

        for message in ascending where message.pinned == true {
            upsertPinned(message)
        }
    }

    // MARK: - reconnect

    private func handleUnexpectedDisconnect(_ error: Error?) {
        guard !isStopping, phase == .connected || phase == .connecting else { return }

        if let error {
            ClientLogStore.shared.recordError("session.disconnected", error: error)
        } else {
            ClientLogStore.shared.recordFailure("session.disconnected", code: "connection_closed")
        }

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

    /// Wraps one tRPC call so the extensions can share the error mapping.
    func call(_ path: String, method: TRPCMethod, input: JSONValue? = nil) async throws -> JSONValue {
        guard let client else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        switch method {
        case .query:
            return try await client.query(path, input: input)
        case .mutation:
            return try await client.mutation(path, input: input)
        case .subscription:
            throw TRPCClientError(code: "PROTOCOL", message: "Subscriptions are not calls")
        }
    }

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

    public static func describe(_ error: Error?) -> String {
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
