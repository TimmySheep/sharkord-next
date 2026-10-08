import AppKit
import Combine
import SharkordCore
import UserNotifications

struct DesktopNotificationPreferences {
    let allMessages: Bool
    let mentionsOnly: Bool
    let directMessages: Bool
    let replies: Bool
}

enum DesktopNotificationPolicy {
    static func shouldRequestAuthorization(for status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    static func shouldNotify(
        isDirectMessage: Bool,
        isOwnMessage: Bool,
        isVisible: Bool,
        isMention: Bool,
        isReplyToOwnMessage: Bool,
        preferences: DesktopNotificationPreferences
    ) -> Bool {
        guard !isOwnMessage, !isVisible else {
            return false
        }

        if isDirectMessage {
            return preferences.directMessages
        }

        if preferences.mentionsOnly {
            return isMention
        }

        if preferences.allMessages {
            return true
        }

        return preferences.replies && isReplyToOwnMessage
    }

    static func hasMention(_ content: String, userId: Int) -> Bool {
        MessageHTML.parse(content).blocks
            .flatMap(\.spans)
            .contains { span in
                guard case .mention(let mentionedUserId, _) = span.content else {
                    return false
                }

                return mentionedUserId == userId
            }
    }

    static func plainText(_ html: String) -> String {
        MessageHTML.parse(html).blocks.map { block in
            block.spans.map { span in
                switch span.content {
                case .text(let value):
                    return value
                case .lineBreak:
                    return " "
                case .mention(_, let label), .channelReference(_, let label):
                    return label
                case .emoji(let name, _):
                    return ":\(name):"
                case .media(_, let alt):
                    return alt
                case .pluginCommand(let name):
                    return name
                }
            }
            .joined()
        }
        .joined(separator: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }
}

@MainActor
final class DesktopNotificationController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var requestFailed = false

    private let center = UNUserNotificationCenter.current()
    private weak var session: SharkordSession?
    private var cancellables = Set<AnyCancellable>()
    private var openClient: (() -> Void)?
    private var authorizationRequestInFlight = false

    override init() {
        super.init()
        center.delegate = self
    }

    func bind(to session: SharkordSession) {
        guard self.session !== session else {
            return
        }

        self.session = session
        cancellables.removeAll()

        session.$incomingMessage
            .compactMap { $0 }
            .sink { [weak self, weak session] message in
                Task { @MainActor in
                    guard let self, let session else { return }
                    self.notifyIfNeeded(message, session: session)
                }
            }
            .store(in: &cancellables)

        session.$unreadByChannel
            .sink { counts in
                let total = counts.values.reduce(0) { $0 + max(0, $1) }
                NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
            }
            .store(in: &cancellables)

    }

    func setOpenClientHandler(_ handler: @escaping () -> Void) {
        openClient = handler
    }

    var hasAuthorization: Bool {
        authorizationStatus == .authorized
            || authorizationStatus == .provisional
    }

    var permissionDescriptionKey: String {
        switch authorizationStatus {
        case .authorized, .provisional:
            return "notificationPermission_granted"
        case .denied:
            return "notificationPermission_denied"
        case .notDetermined:
            return "notificationPermission_default"
        @unknown default:
            return "notificationPermission_default"
        }
    }

    func refreshAuthorization() {
        Task {
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequestInFlight else {
            return
        }

        authorizationRequestInFlight = true

        Task {
            defer { authorizationRequestInFlight = false }

            let currentSettings = await center.notificationSettings()
            authorizationStatus = currentSettings.authorizationStatus

            guard DesktopNotificationPolicy.shouldRequestAuthorization(for: currentSettings.authorizationStatus) else {
                return
            }

            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                requestFailed = false
            } catch {
                requestFailed = true
            }

            let updatedSettings = await center.notificationSettings()
            authorizationStatus = updatedSettings.authorizationStatus
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let channelId = response.notification.request.content.userInfo["channelId"] as? Int

        Task { @MainActor [weak self] in
            if let self {
                self.openClient?()

                if let session = self.session, let channelId {
                    await session.select(channelId: channelId)
                }
            }

            completionHandler()
        }
    }

    private func notifyIfNeeded(_ message: SharkordMessage, session: SharkordSession) {
        guard hasAuthorization,
              let channel = session.channel(for: message.channelId),
              let author = message.pluginId.flatMap({ pluginId in
                  session.pluginsMetadata.first { $0.pluginId == pluginId }?.name
              }) ?? message.userId.flatMap(session.user(for:))?.name else {
            return
        }

        let hasVisibleWindow = NSApp.keyWindow?.isVisible == true
        let isVisible = NSApp.isActive && hasVisibleWindow && session.selectedChannelId == message.channelId
        let isOwnMessage = message.userId == session.ownUserId
        let preferences = DesktopNotificationPreferences(
            allMessages: UserDefaults.standard.object(forKey: "notify.allMessages") as? Bool ?? false,
            mentionsOnly: UserDefaults.standard.object(forKey: "notify.mentionsOnly") as? Bool ?? true,
            directMessages: UserDefaults.standard.object(forKey: "notify.dms") as? Bool ?? true,
            replies: UserDefaults.standard.object(forKey: "notify.replies") as? Bool ?? true
        )
        let shouldNotify = DesktopNotificationPolicy.shouldNotify(
            isDirectMessage: channel.isDm,
            isOwnMessage: isOwnMessage,
            isVisible: isVisible,
            isMention: DesktopNotificationPolicy.hasMention(message.content ?? "", userId: session.ownUserId),
            isReplyToOwnMessage: message.replyToMessageId != nil && message.replyTo?.userId == session.ownUserId,
            preferences: preferences
        )

        guard shouldNotify else {
            return
        }

        let plainText = DesktopNotificationPolicy.plainText(message.content ?? "")
        let content = UNMutableNotificationContent()
        content.title = channel.isDm
            ? L10n.t("notificationDirectMessageTitle", ns: "macos", ["author": author])
            : L10n.t("notificationChannelTitle", ns: "macos", ["author": author, "channel": channel.name])
        content.body = String((plainText.isEmpty ? L10n.t("notificationAttachmentBody", ns: "macos") : plainText).prefix(240))
        content.sound = .default
        content.userInfo = ["channelId": message.channelId]
        content.threadIdentifier = "\(session.serverId).\(message.channelId)"

        let request = UNNotificationRequest(
            identifier: "\(session.serverId).\(message.channelId).\(message.id)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

}
