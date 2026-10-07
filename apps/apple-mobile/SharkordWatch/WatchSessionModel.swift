import Foundation
import SwiftUI
import SharkordCore

/// owns the shared Sharkord session and the Watch-only radio controller.
@MainActor
final class WatchSessionModel: ObservableObject {
    @Published var server = UserDefaults.standard.string(forKey: "watch.server") ?? ""
    @Published var identity = UserDefaults.standard.string(forKey: "watch.identity") ?? ""
    @Published var password = ""
    @Published var serverPassword = ""
    @Published var remembersLogin = true
    @Published private(set) var hasSavedLogin = false
    @Published private(set) var needsServerPassword = false
    @Published private(set) var isConnecting = false
    @Published private(set) var connectError: String?
    @Published private(set) var credentialWarning: String?

    let session: SharkordSession
    let radio: WatchRadioSession
    private let credentialStore = WatchCredentialStore()

    init(session: SharkordSession) {
        self.session = session
        self.radio = WatchRadioSession()

        do {
            if let saved = try credentialStore.load() {
                hasSavedLogin = true
                server = saved.server
                identity = saved.identity
                Task { [weak self] in
                    guard let self else {
                        return
                    }
                    await self.connectSavedLogin()
                }
            }
        } catch {
            DiagnosticsLogger.shared.error("credentials", "saved login could not be loaded", error: error)
            credentialWarning = L10n.t("connect.credentialStorageFailed")
        }
    }

    func connect() async {
        guard !isConnecting else {
            return
        }

        if session.phase == .awaitingServerPassword {
            await submitServerPassword()
            return
        }

        isConnecting = true
        connectError = nil
        credentialWarning = nil
        UserDefaults.standard.set(server, forKey: "watch.server")
        UserDefaults.standard.set(identity, forKey: "watch.identity")
        if !remembersLogin {
            do {
                try credentialStore.remove()
                hasSavedLogin = false
            } catch {
                DiagnosticsLogger.shared.error("credentials", "saved login could not be removed", error: error)
                credentialWarning = L10n.t("connect.credentialStorageFailed")
                hasSavedLogin = (try? credentialStore.load()) != nil
                isConnecting = false
                return
            }
        }

        await session.connect(
            host: server,
            identity: identity,
            password: password,
            serverPassword: serverPassword.isEmpty ? nil : serverPassword
        )

        isConnecting = false

        if case .failed(let message) = session.phase {
            DiagnosticsLogger.shared.error("session", message)
            connectError = message
            return
        }

        if session.phase == .awaitingServerPassword {
            needsServerPassword = true
            isConnecting = false
            return
        }

        needsServerPassword = false
        finishConnection(using: WatchRadioCredentials(
            host: server,
            identity: identity,
            password: password,
            serverPassword: serverPassword.isEmpty ? nil : serverPassword
        ))
    }

    func connectSavedLogin() async {
        guard !isConnecting else {
            return
        }

        do {
            guard let saved = try credentialStore.load() else {
                hasSavedLogin = false
                return
            }
            server = saved.server
            identity = saved.identity
            password = saved.password
            serverPassword = saved.serverPassword
            await connect()
        } catch {
            DiagnosticsLogger.shared.error("credentials", "saved login could not be loaded", error: error)
            hasSavedLogin = false
            credentialWarning = L10n.t("connect.credentialStorageFailed")
        }
    }

    func forgetSavedLogin() {
        do {
            try credentialStore.remove()
            hasSavedLogin = false
            credentialWarning = nil
        } catch {
            DiagnosticsLogger.shared.error("credentials", "saved login could not be removed", error: error)
            credentialWarning = L10n.t("connect.credentialStorageFailed")
        }
    }

    private func submitServerPassword() async {
        guard !isConnecting else {
            return
        }
        guard !serverPassword.isEmpty else {
            connectError = L10n.t("connect.serverPasswordRequired")
            return
        }
        if !remembersLogin {
            do {
                try credentialStore.remove()
                hasSavedLogin = false
            } catch {
                DiagnosticsLogger.shared.error("credentials", "saved login could not be removed", error: error)
                credentialWarning = L10n.t("connect.credentialStorageFailed")
                hasSavedLogin = (try? credentialStore.load()) != nil
                return
            }
        }

        isConnecting = true
        connectError = nil
        await session.submitServerPassword(serverPassword)
        isConnecting = false

        if session.phase == .awaitingServerPassword {
            connectError = session.lastError ?? L10n.t("connect.serverPasswordRequired")
            return
        }

        needsServerPassword = false
        finishConnection(using: WatchRadioCredentials(
            host: server,
            identity: identity,
            password: password,
            serverPassword: serverPassword
        ))
    }

    private func finishConnection(using radioCredentials: WatchRadioCredentials) {
        if remembersLogin {
            do {
                try credentialStore.save(
                    WatchLoginCredentials(
                        server: server,
                        identity: identity,
                        password: password,
                        serverPassword: serverPassword
                    )
                )
                hasSavedLogin = true
            } catch {
                DiagnosticsLogger.shared.error("credentials", "saved login could not be stored", error: error)
                try? credentialStore.remove()
                hasSavedLogin = (try? credentialStore.load()) != nil
                credentialWarning = L10n.t("connect.credentialStorageFailed")
            }
        }

        password = ""
        serverPassword = ""
        radio.configure(credentials: radioCredentials)
    }

    func disconnect() async {
        await radio.leave()
        session.disconnect()
    }
}
