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
    @Published private(set) var isConnecting = false
    @Published private(set) var connectError: String?

    let session: SharkordSession
    let radio: WatchRadioSession

    init(session: SharkordSession) {
        self.session = session
        self.radio = WatchRadioSession()
    }

    func connect() async {
        guard !isConnecting else {
            return
        }

        isConnecting = true
        connectError = nil
        UserDefaults.standard.set(server, forKey: "watch.server")
        UserDefaults.standard.set(identity, forKey: "watch.identity")
        let radioCredentials = WatchRadioCredentials(
            host: server,
            identity: identity,
            password: password,
            serverPassword: serverPassword.isEmpty ? nil : serverPassword
        )

        await session.connect(
            host: server,
            identity: identity,
            password: password,
            serverPassword: serverPassword.isEmpty ? nil : serverPassword
        )

        isConnecting = false

        if case .failed(let message) = session.phase {
            connectError = message
            return
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
