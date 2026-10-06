import SharkordCore
import SwiftUI

/// First run screen: server address, account and password. Mirrors the web client's login
/// fields; the server password and invite code are optional and collapsed by default.
struct ConnectView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var host = ""
    @State private var identity = ""
    @State private var password = ""
    @State private var serverPassword = ""
    @State private var invite = ""
    @State private var showsAdvanced = false

    private var isConnecting: Bool {
        session.phase == .connecting
    }

    private var canSubmit: Bool {
        !host.isEmpty && !identity.isEmpty && password.count >= 4 && !isConnecting
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.sidebar, Theme.panel],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                header
                card
                footer
            }
            .frame(maxWidth: 420)
            .padding(32)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 56, height: 56)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Sharkord")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            Eyebrow(text: "Native macOS client")
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(title: "Server address", text: $host, placeholder: "localhost:4991")
            field(title: "Identity", text: $identity, placeholder: "your-name")
            secureField(title: "Password", text: $password, placeholder: "password")

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 14) {
                    secureField(
                        title: "Server password",
                        text: $serverPassword,
                        placeholder: "if the server requires one"
                    )
                    field(title: "Invite code", text: $invite, placeholder: "if registration is closed")
                }
                .padding(.top, 10)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .onTapGesture { showsAdvanced.toggle() }

            if case .failed(let message) = session.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                HStack {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    }

                    Text(isConnecting ? "Connecting..." : "Connect")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var footer: some View {
        Text(L10n.t("tagline", ns: "macos"))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .disableAutocorrection(true)
                .padding(10)
                .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
        }
    }

    private func secureField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)

            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
        }
    }

    private func submit() {
        guard canSubmit else {
            return
        }

        let hostValue = host
        let identityValue = identity
        let passwordValue = password
        let serverPasswordValue = serverPassword
        let inviteValue = invite

        Task {
            await session.connect(
                host: hostValue,
                identity: identityValue,
                password: passwordValue,
                serverPassword: serverPasswordValue.isEmpty ? nil : serverPasswordValue,
                invite: inviteValue.isEmpty ? nil : inviteValue
            )
        }
    }
}
