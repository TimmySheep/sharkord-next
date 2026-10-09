import Combine
import AVFoundation
import Foundation
import SharkordCore
import SwiftUI
import UserNotifications

struct PendingMessageNavigation: Equatable {
    let channelId: Int
    let messageId: Int
}

enum LocalNotificationOption {
    case all
    case mentions
    case directMessages
    case replies
}

/// The single observable object the screens read. It owns the shared `SharkordSession`
/// (server state and signalling), the `VoiceEngine` (media), and the small amount of UI
/// state that is genuinely app local: language, banners and the Dynamic Island activity.
/// Changes from the session and the voice engine are forwarded here, so views observe one
/// object and still refresh on every server update.
@MainActor
final class AppModel: ObservableObject {
    let session: SharkordSession
    let voice: VoiceEngine
    let watchAccountManager: WatchAccountManager

    @Published var language: String = L10n.current
    @Published var banner: String?
    @Published var pendingThreadParentId: Int?
    @Published var pendingMessageNavigation: PendingMessageNavigation?
    @Published var pendingLiveActivityCallNavigationId: UUID?
    @Published var isReconnecting = false
    @Published private(set) var hasConnected = false
    @Published var notificationStatus: String?
    @Published var notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications.enabled") {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notifications.enabled") }
    }
    @Published var notificationsForMentions = UserDefaults.standard.bool(forKey: "notifications.mentions") {
        didSet { UserDefaults.standard.set(notificationsForMentions, forKey: "notifications.mentions") }
    }
    @Published var notificationsForDms = UserDefaults.standard.bool(forKey: "notifications.dms") {
        didSet { UserDefaults.standard.set(notificationsForDms, forKey: "notifications.dms") }
    }
    @Published var notificationsForReplies = UserDefaults.standard.bool(forKey: "notifications.replies") {
        didSet { UserDefaults.standard.set(notificationsForReplies, forKey: "notifications.replies") }
    }
    @Published var soundEffectsEnabled = UserDefaults.standard.object(forKey: "sounds.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEffectsEnabled, forKey: "sounds.enabled") }
    }

    private let liveActivityController = LiveActivityController()
    private let notificationController = LocalNotificationController.shared
    private var cancellables: Set<AnyCancellable> = []
    private var appIsActive = true
    private var isManualConnectionInProgress = false
    private var lastConnection: (host: String, identity: String, password: String, serverPassword: String)?

    init() {
        let session = SharkordSession()
        self.session = session
        self.voice = VoiceEngine(session: session)
        self.watchAccountManager = WatchAccountManager(session: session)

        session.$phase
            .sink { [weak self] phase in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.session.phase == phase else { return }
                    switch phase {
                    case .connected:
                        self.hasConnected = true
                        self.isReconnecting = false
                    case .failed, .disconnected, .awaitingServerPassword:
                        self.hasConnected = false
                        self.isReconnecting = false
                    case .connecting:
                        self.isReconnecting = self.hasConnected && !self.isManualConnectionInProgress
                    }
                }
            }
            .store(in: &cancellables)

        session.$incomingMessage
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.handleIncomingMessage(message)
                }
            }
            .store(in: &cancellables)

        session.$phase
            .dropFirst()
            .sink { phase in
                if case .failed(let message) = phase {
                    DiagnosticsLogger.shared.error("session", message)
                } else if case .connected = phase {
                    DiagnosticsLogger.shared.info("session", "connected")
                }
            }
            .store(in: &cancellables)

        session.$lastError
            .compactMap { $0 }
            .removeDuplicates()
            .sink { message in
                DiagnosticsLogger.shared.error("session", message)
            }
            .store(in: &cancellables)

        voice.$lastErrorMessage
            .compactMap { $0 }
            .removeDuplicates()
            .sink { message in
                DiagnosticsLogger.shared.error("voice", message)
            }
            .store(in: &cancellables)

        session.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        voice.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // a remote producer appearing anywhere in the joined channel is the cue to open
        // (or drop) consumers; the engine reconciles the full set
        session.$producersByChannel
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.voice.reconcileProducers()
                }
            }
            .store(in: &cancellables)

        // being moved or kicked out of the voice channel clears the local call
        session.$voiceMap
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.syncVoiceWithServer()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - connection

    func connect(host: String, identity: String, password: String, serverPassword: String) async {
        banner = nil
        isReconnecting = false
        hasConnected = false
        isManualConnectionInProgress = true
        lastConnection = (host, identity, password, serverPassword)
        await session.connect(
            host: host,
            identity: identity,
            password: password,
            serverPassword: serverPassword.isEmpty ? nil : serverPassword
        )
        isManualConnectionInProgress = false

        if case .failed(let message) = session.phase {
            banner = message
        }
    }

    func retryConnection() {
        guard let lastConnection else { return }
        Task {
            await connect(
                host: lastConnection.host,
                identity: lastConnection.identity,
                password: lastConnection.password,
                serverPassword: lastConnection.serverPassword
            )
        }
    }

    var canRetryConnection: Bool {
        lastConnection != nil
    }

    func setAppActive(_ active: Bool) {
        appIsActive = active
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        setNotificationOption(.all, enabled: enabled)
    }

    func setNotificationOption(_ option: LocalNotificationOption, enabled: Bool) {
        Task {
            if enabled, !(await notificationController.requestAuthorization()) {
                notificationStatus = L10n.t("settings.notificationsDenied")
                return
            }
            notificationStatus = nil
            switch option {
            case .all:
                notificationsEnabled = enabled
            case .mentions:
                notificationsForMentions = enabled
            case .directMessages:
                notificationsForDms = enabled
            case .replies:
                notificationsForReplies = enabled
            }
        }
    }

    func disconnect() {
        Task { await voice.leave() }
        session.disconnect()
    }

    // MARK: - navigation

    func selectChannel(_ channelId: Int) {
        Task {
            await session.select(channelId: channelId)
            session.markAsRead(channelId)
        }
    }

    // MARK: - language

    func setLanguage(_ code: String) {
        L10n.current = code
        language = code
    }

    // MARK: - voice

    func joinVoice(_ channelId: Int) {
        banner = nil

        Task {
            await voice.join(channelId: channelId)
            await syncVoiceWithServer()
            updateLiveActivity()
        }
    }

    func leaveVoice() {
        Task {
            await voice.leave()
            updateLiveActivity()
        }
    }

    func toggleMicrophone() {
        let target = !voice.microphoneOn

        Task {
            do {
                try await voice.setMicrophoneEnabled(target)
                updateLiveActivity()
            } catch {
                DiagnosticsLogger.shared.error("voice", "microphone change failed", error: error)
                banner = error.localizedDescription
            }
        }
    }

    func handleLiveActivityURL(_ url: URL) {
        guard url.scheme == "cove", url.host == "voice", url.path == "/toggle-microphone" else {
            return
        }

        guard voice.currentChannelId != nil else {
            banner = L10n.t("voice.error.notInCall")
            return
        }

        pendingLiveActivityCallNavigationId = UUID()
        toggleMicrophone()
    }

    func toggleDeafen() {
        let target = !voice.deafened

        Task {
            do {
                try await voice.setDeafened(target)
                updateLiveActivity()
            } catch {
                DiagnosticsLogger.shared.error("voice", "speaker change failed", error: error)
                banner = error.localizedDescription
            }
        }
    }

    func toggleScreenShare() {
        Task {
            await voice.stopScreenShare()
        }
    }

    func prepareScreenShare() {
        do {
            try voice.prepareScreenBroadcast()
        } catch {
            DiagnosticsLogger.shared.error("voice", "screen share preparation failed", error: error)
            banner = error.localizedDescription
        }
    }

    func toggleCamera() {
        Task {
            do {
                if voice.cameraOn {
                    await voice.stopCamera()
                } else {
                    try await voice.startCamera()
                }
            } catch {
                DiagnosticsLogger.shared.error("voice", "camera action failed", error: error)
                banner = error.localizedDescription
            }
        }
    }

    func switchCamera() {
        Task {
            do {
                try await voice.switchCamera()
            } catch {
                DiagnosticsLogger.shared.error("voice", "camera switch failed", error: error)
                banner = error.localizedDescription
            }
        }
    }

    /// Keeps the local call in step with the server: the user being moved by a moderator
    /// or removed from the channel ends the local session exactly like the web client.
    private func syncVoiceWithServer() async {
        guard let channelId = voice.currentChannelId else {
            return
        }

        if session.currentVoiceChannelId != channelId {
            await voice.leave()
            banner = L10n.t("voice.notice.movedOrRemoved")
            updateLiveActivity()
        }
    }

    private func handleIncomingMessage(_ message: SharkordMessage) {
        guard message.userId != session.ownUserId else { return }

        guard let channel = session.channel(for: message.channelId) else {
            if soundEffectsEnabled { notificationController.playMessageSound() }
            return
        }
        if appIsActive && session.selectedChannelId == channel.id {
            if soundEffectsEnabled { notificationController.playMessageSound() }
            return
        }

        let isMention = MessageHTML.parse(message.content ?? "").blocks
            .flatMap(\.spans)
            .contains { span in
                if case .mention(let userId, _) = span.content {
                    return userId == session.ownUserId
                }
                return false
            }
        let isReplyToOwnMessage = message.replyToMessageId != nil
            && message.replyTo?.userId == session.ownUserId
        let shouldNotify: Bool
        if channel.isDm {
            shouldNotify = notificationsForDms
        } else if notificationsForMentions {
            shouldNotify = isMention
        } else if notificationsEnabled {
            shouldNotify = true
        } else {
            shouldNotify = notificationsForReplies && isReplyToOwnMessage
        }

        guard shouldNotify else {
            if soundEffectsEnabled { notificationController.playMessageSound() }
            return
        }

        let author = message.userId.flatMap { session.user(for: $0)?.name }
            ?? message.pluginId
            ?? L10n.t("message.unknownAuthor")
        let channelName = channel.isDm
            ? author + " · " + L10n.t("nav.directMessages")
            : author + " · #" + channel.name
        let body = MessageText.plainText(fromHTML: message.content)
        notificationController.send(
            title: channelName,
            body: body.isEmpty ? L10n.t("settings.attachmentNotification") : body,
            channelId: channel.id,
            playsSound: soundEffectsEnabled
        )
    }

    // MARK: - Dynamic Island

    private func updateLiveActivity() {
        if let channelId = voice.currentChannelId, let channel = session.channel(for: channelId) {
            let participants = session.voiceUsers(in: channelId).count
            let topic = channel.topic ?? L10n.t("voice.liveActivity.topic")

            if liveActivityController.isRunning {
                Task {
                    await liveActivityController.update(
                        channelName: channel.name,
                        topic: topic,
                        participantCount: participants,
                        isSpeaking: voice.microphoneOn
                    )
                }
            } else {
                liveActivityController.start(
                    serverAddress: session.serverName,
                    channelName: channel.name,
                    topic: topic,
                    participantCount: participants
                )
            }
        } else if liveActivityController.isRunning {
            Task { await liveActivityController.end() }
        }
    }

    // MARK: - display helpers

    var serverDisplayName: String {
        if !session.serverName.isEmpty {
            return session.serverName
        }
        return session.serverBaseURL?.host() ?? "Sharkord"
    }

    var isConnected: Bool {
        if case .connected = session.phase {
            return true
        }
        return false
    }
}

private final class LocalNotificationController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationController()

    private let center = UNUserNotificationCenter.current()
    @MainActor private var soundPlayer: AVAudioPlayer?

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            return true
        }

        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func send(title: String, body: String, channelId: Int, playsSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(240))
        content.sound = playsSound ? .default : nil
        content.userInfo = ["channelId": channelId]

        let request = UNNotificationRequest(
            identifier: "message-\(channelId)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    @MainActor
    func playMessageSound() {
        guard let player = try? AVAudioPlayer(data: Self.messageTone()) else { return }
        soundPlayer = player
        soundPlayer?.volume = 0.08
        soundPlayer?.play()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    private static func messageTone() -> Data {
        let sampleRate: UInt32 = 22_050
        let sampleCount = UInt32(sampleRate / 14)
        var data = Data("RIFF".utf8)
        appendLittleEndian(36 + sampleCount * 2, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * 2, to: &data)
        appendLittleEndian(UInt16(2), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(sampleCount * 2, to: &data)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let fade = min(1, Double(sampleCount - index) / 900)
            let sample = Int16(sin(2 * .pi * 600 * time) * 2_400 * fade)
            appendLittleEndian(sample, to: &data)
        }
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
