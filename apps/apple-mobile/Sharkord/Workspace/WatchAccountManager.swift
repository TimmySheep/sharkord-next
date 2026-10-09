import Foundation
import Combine
import Security
import SharkordCore
import WatchConnectivity

@MainActor
final class WatchAccountManager: NSObject, ObservableObject {
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var accountIdentity: String?
    @Published private(set) var isWorking = false
    @Published private(set) var isCollectingLogs = false
    @Published private(set) var logsStatusMessage: String?

    private let session: SharkordSession
    private let connectivity = WCSession.default
    private let credentialsStore = KeychainLoginCredentialsStore(
        service: "com.timmysheep.cove.watch-login",
        account: "linked-watch"
    )
    private var pendingLogRequestID: String?
    private var pendingLogContinuation: CheckedContinuation<String?, Never>?

    init(session: SharkordSession) {
        self.session = session
        super.init()
        accountIdentity = credentialsStore.credentials()?.identity

        guard WCSession.isSupported() else {
            statusMessage = L10n.t("watchAccount.notSupported")
            return
        }

        connectivity.delegate = self
        connectivity.activate()
        refreshPairingState()
    }

    var suggestedIdentity: String {
        let source = session.ownUser?._identity ?? session.ownUser?.name ?? "user"
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return "user-watch"
        }
        return normalized.hasSuffix("watch") ? normalized : "\(normalized)-watch"
    }

    func syncSavedAccount() {
        guard let credentials = credentialsStore.credentials() else {
            statusMessage = L10n.t("watchAccount.noAccount")
            return
        }
        send(credentials)
    }

    func collectWatchLogs() async -> String? {
        guard connectivity.isPaired, connectivity.isWatchAppInstalled else {
            logsStatusMessage = L10n.t("settings.watchLogsUnavailable")
            return nil
        }
        guard connectivity.activationState == .activated else {
            logsStatusMessage = L10n.t("settings.watchLogsNotReachable")
            return nil
        }

        isCollectingLogs = true
        logsStatusMessage = L10n.t("settings.collectingWatchLogs")
        defer { isCollectingLogs = false }

        return await withCheckedContinuation { continuation in
            let requestID = UUID().uuidString
            pendingLogRequestID = requestID
            pendingLogContinuation = continuation
            requestWatchLogs(requestID)

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                self?.finishLogRequest(
                    requestID: requestID,
                    logs: nil,
                    status: L10n.t("settings.watchLogsNotReachable")
                )
            }
        }
    }

    private func requestWatchLogs(_ requestID: String) {
        let payload: [String: Any] = ["type": "collectLogs", "requestID": requestID]
        guard connectivity.isReachable else {
            connectivity.transferUserInfo(payload)
            return
        }

        connectivity.sendMessage(
            payload,
            replyHandler: { [weak self] reply in
                guard let logs = reply["watchLogs"] as? String else {
                    return
                }
                Task { @MainActor in
                    self?.finishLogRequest(requestID: requestID, logs: logs, status: L10n.t("settings.watchLogsCollected"))
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.connectivity.transferUserInfo(payload)
                }
            }
        )
    }

    private func finishLogRequest(requestID: String, logs: String?, status: String) {
        guard pendingLogRequestID == requestID, let continuation = pendingLogContinuation else {
            return
        }
        pendingLogRequestID = nil
        pendingLogContinuation = nil
        logsStatusMessage = status
        continuation.resume(returning: logs)
    }

    func createAccount(identity: String, invite: String) async {
        guard !isWorking else {
            return
        }
        guard isPaired, isWatchAppInstalled else {
            statusMessage = L10n.t("watchAccount.pairFirst")
            return
        }
        guard session.phase == .connected, let host = session.linkedDeviceHost else {
            statusMessage = L10n.t("watchAccount.connectFirst")
            return
        }
        guard credentialsStore.credentials() == nil else {
            statusMessage = L10n.t("watchAccount.alreadyCreated")
            return
        }

        let normalizedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedIdentity.isEmpty, normalizedIdentity.hasSuffix("watch") else {
            statusMessage = L10n.t("watchAccount.identityMustEndWatch")
            return
        }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        let password = Self.makePassword()
        do {
            try await session.registerLinkedWatchAccount(
                identity: normalizedIdentity,
                password: password,
                invite: invite
            )

            let credentials = StoredLoginCredentials(
                host: host,
                identity: normalizedIdentity,
                password: password,
                serverPassword: session.linkedDeviceServerPassword
            )
            guard credentialsStore.setCredentials(credentials) else {
                statusMessage = L10n.t("watchAccount.keychainFailed")
                return
            }

            accountIdentity = normalizedIdentity
            send(credentials)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func send(_ credentials: StoredLoginCredentials) {
        guard connectivity.activationState == .activated,
              connectivity.isPaired,
              connectivity.isWatchAppInstalled
        else {
            statusMessage = L10n.t("watchAccount.pairFirst")
            return
        }

        let payload: [String: Any] = [
            "server": credentials.host,
            "identity": credentials.identity,
            "password": credentials.password,
            "serverPassword": credentials.serverPassword ?? ""
        ]

        do {
            try connectivity.updateApplicationContext(payload)
            connectivity.transferUserInfo(payload)
            statusMessage = L10n.t("watchAccount.syncQueued")
        } catch {
            statusMessage = L10n.t("watchAccount.syncFailed")
        }
    }

    private func refreshPairingState() {
        isPaired = connectivity.isPaired
        isWatchAppInstalled = connectivity.isWatchAppInstalled
    }

    private static func makePassword() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~!@#$%^&*")
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
}

extension WatchAccountManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.refreshPairingState()
            if error != nil {
                self?.statusMessage = L10n.t("watchAccount.syncFailed")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        Task { @MainActor [weak self] in
            self?.refreshPairingState()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshPairingState()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["type"] as? String == "watchLogs",
              let requestID = userInfo["requestID"] as? String,
              let logs = userInfo["logs"] as? String
        else {
            return
        }
        Task { @MainActor [weak self] in
            self?.finishLogRequest(
                requestID: requestID,
                logs: logs,
                status: L10n.t("settings.watchLogsCollected")
            )
        }
    }
}
