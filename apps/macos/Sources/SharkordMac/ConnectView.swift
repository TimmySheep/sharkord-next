import SharkordCore
import SwiftUI

/// First run screen: server address, account and password. Mirrors the web client's login
/// fields; the server password and invite code are optional and collapsed by default.
struct ConnectView: View {
    @EnvironmentObject private var session: SharkordSession
    @AppStorage("login.autoLoginEnabled") private var autoLoginEnabled = true

    @State private var host = ""
    @State private var identity = ""
    @State private var password = ""
    @State private var serverPassword = ""
    @State private var invite = ""
    @State private var showsServerPasswordPrompt = false
    @State private var didLoadSavedCredentials = false
    @State private var credentialStorageError = false

    private let loginCredentialStore = KeychainLoginCredentialsStore()

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
            }
            .frame(maxWidth: 420)
            .padding(32)
        }
        .sheet(isPresented: $showsServerPasswordPrompt) {
            ServerPasswordPromptView()
                .environmentObject(session)
                .frame(width: 430)
                .interactiveDismissDisabled()
        }
        .onAppear {
            loadSavedCredentials()
            showsServerPasswordPrompt = session.phase == .awaitingServerPassword
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .awaitingServerPassword {
                showsServerPasswordPrompt = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image("cove-icon", bundle: .module)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            Text("cove")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(
                title: L10n.t("connectServerAddress", ns: "macos"),
                text: $host,
                placeholder: "localhost:4991"
            )
            field(
                title: L10n.t("identityLabel", ns: "connect"),
                text: $identity,
                placeholder: L10n.t("identityLabel", ns: "connect")
            )
            secureField(
                title: L10n.t("passwordLabel", ns: "connect"),
                text: $password,
                placeholder: L10n.t("passwordLabel", ns: "connect")
            )

            Toggle(isOn: $autoLoginEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("autoLoginLabel", ns: "macos"))
                        .font(.system(size: 12, weight: .medium))

                    Text(L10n.t("autoLoginDescription", ns: "macos"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(isConnecting)
            .onChange(of: autoLoginEnabled) { _, enabled in
                guard !enabled else {
                    credentialStorageError = false
                    return
                }

                credentialStorageError = !loginCredentialStore.deleteCredentials()
            }

            if credentialStorageError || session.loginCredentialsSaveFailed {
                Label(L10n.t("credentialStorageFailed", ns: "macos"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup(L10n.t("advancedOptions", ns: "macos")) {
                VStack(alignment: .leading, spacing: 14) {
                    secureField(
                        title: L10n.t("serverPasswordLabel", ns: "macos"),
                        text: $serverPassword,
                        placeholder: L10n.t("optional", ns: "connect")
                    )
                    field(
                        title: L10n.t("inviteCodeLabel", ns: "macos"),
                        text: $invite,
                        placeholder: L10n.t("optional", ns: "connect")
                    )
                }
                .padding(.top, 10)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

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

                    Text(isConnecting
                        ? L10n.t("connecting", ns: "macos")
                        : L10n.t("connectBtn", ns: "connect"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)

            DiagnosticLogExportButton()
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .disableAutocorrection(true)
                .padding(10)
                .background(Theme.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.primary)
                .accessibilityLabel(title)
        }
    }

    private func secureField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)

            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Theme.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.primary)
                .accessibilityLabel(title)
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
                invite: inviteValue.isEmpty ? nil : inviteValue,
                rememberLoginCredentials: autoLoginEnabled
            )
        }
    }

    private func loadSavedCredentials() {
        guard !didLoadSavedCredentials else {
            return
        }

        didLoadSavedCredentials = true

        guard autoLoginEnabled, let saved = loginCredentialStore.credentials() else {
            return
        }

        host = saved.host
        identity = saved.identity
        password = saved.password
        serverPassword = saved.serverPassword ?? ""
    }
}

private struct ServerPasswordPromptView: View {
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("serverPasswordTitle", ns: "dialogs"))
                .font(.title3.bold())

            Text(L10n.t("serverPasswordDesc", ns: "dialogs"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SecureField(L10n.t("passwordLabel", ns: "connect"), text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            if let lastError = session.lastError {
                Text(lastError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(L10n.t("cancel", ns: "dialogs"), action: cancel)

                Spacer()

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L10n.t("joinBtn", ns: "dialogs"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
    }

    private func submit() {
        guard !password.isEmpty, !isSubmitting else {
            return
        }

        isSubmitting = true
        Task {
            await session.submitServerPassword(password)
            isSubmitting = false

            if session.phase == .connected {
                dismiss()
            }
        }
    }

    private func cancel() {
        session.cancelServerPasswordPrompt()
        dismiss()
    }
}
