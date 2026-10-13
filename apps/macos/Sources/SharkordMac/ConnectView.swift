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
    @State private var serverInfo: SharkordServerInfo?
    @State private var serverLogoURL: URL?
    @State private var selectedLanguage = L10n.language

    private let loginCredentialStore = KeychainLoginCredentialsStore()

    private var isConnecting: Bool {
        session.phase == .connecting
    }

    private var canSubmit: Bool {
        !host.isEmpty && !identity.isEmpty && password.count >= 4 && !isConnecting
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color(red: 0.035, green: 0.043, blue: 0.059)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [Color(red: 0.18, green: 0.20, blue: 0.38).opacity(0.34), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: 520
                )
                .frame(width: geometry.size.width * 1.5, height: 720)
                .offset(y: -300)
                .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 22) {
                        card
                        footer
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .environment(\.colorScheme, .dark)
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
        .task(id: host) {
            await refreshServerPreview(for: host)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 12) {
                Group {
                    if let serverLogoURL {
                        AsyncImage(url: serverLogoURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                fallbackLogo
                            }
                        }
                    } else {
                        fallbackLogo
                    }
                }
                .frame(width: 88, height: 88)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

                Text(serverDisplayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                if let description = serverInfo?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty
                {
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)

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
            }

            Toggle(isOn: $autoLoginEnabled) {
                Text(L10n.t("autoLoginLabel", ns: "macos"))
                    .font(.callout.weight(.medium))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(isConnecting)
            .onChange(of: autoLoginEnabled) { _, enabled in
                guard !enabled else {
                    credentialStorageError = false
                    return
                }

                credentialStorageError = !loginCredentialStore.deleteCredentials()
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
            .font(.callout)

            if credentialStorageError || session.loginCredentialsSaveFailed {
                Label(L10n.t("credentialStorageFailed", ns: "macos"), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .failed(let message) = session.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    }

                    Text(
                        isConnecting
                            ? L10n.t("connecting", ns: "macos")
                            : L10n.t("connectBtn", ns: "connect")
                    )
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(26)
        .background(Color(red: 0.075, green: 0.086, blue: 0.112), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 34, x: 0, y: 18)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")")
                    .foregroundStyle(.tertiary)
                Link("GitHub", destination: URL(string: "https://github.com/sharkord/sharkord")!)
                Link("Sharkord", destination: URL(string: "https://sharkord.com")!)
                DiagnosticLogExportButton()
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            .font(.system(size: 12))

            Menu {
                ForEach(Array(L10n.supportedLanguages.enumerated()), id: \.offset) { item in
                    Button(item.element.nativeName) {
                        selectedLanguage = item.element.code
                        L10n.language = item.element.code
                    }
                }
            } label: {
                Label(
                    L10n.supportedLanguages.first(where: { $0.code == selectedLanguage })?.nativeName ?? "English",
                    systemImage: "globe"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.secondary)
    }

    private var fallbackLogo: some View {
        Image("cove-icon", bundle: .module)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .padding(8)
    }

    private var serverDisplayName: String {
        guard let name = serverInfo?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "cove"
        }

        return name
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .disableAutocorrection(true)
                .accessibilityLabel(title)
        }
    }

    private func secureField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)

            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .accessibilityLabel(title)
        }
    }

    private func refreshServerPreview(for host: String) async {
        serverInfo = nil
        serverLogoURL = nil

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return
        }

        let address = trimmedHost.contains("://") ? trimmedHost : "http://\(trimmedHost)"
        guard
            let components = URLComponents(string: address),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let serverHost = components.host,
            !serverHost.isEmpty,
            let baseURL = components.url
        else {
            return
        }

        do {
            try await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else {
                return
            }

            let client = SharkordHTTPClient(baseURL: baseURL)
            let info = try await client.serverInfo()
            guard !Task.isCancelled else {
                return
            }

            serverInfo = info
            serverLogoURL = info.logo.flatMap { client.publicFileURL(for: $0) }
        } catch {}
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
