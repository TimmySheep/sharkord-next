import SwiftUI

/// sign-in screen using the same HTTP login and tRPC handshake as the other clients.
struct WatchConnectView: View {
    @EnvironmentObject private var model: WatchSessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(WatchTheme.accentSoft)
                    Text(L10n.t("connect.title"))
                        .font(.headline)
                        .foregroundStyle(WatchTheme.textPrimary)
                        .multilineTextAlignment(.center)
                }

                if model.hasSavedLogin {
                    Button {
                        Task {
                            await model.connectSavedLogin()
                        }
                    } label: {
                        Text(L10n.t("connect.quickSignIn"))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isConnecting)

                    Button(L10n.t("connect.forgetSavedLogin")) {
                        model.forgetSavedLogin()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .disabled(model.isConnecting)
                }

                WatchCard {
                    VStack(spacing: 8) {
                        field(L10n.t("connect.server"), text: $model.server, placeholder: L10n.t("connect.serverPlaceholder"), secure: false)
                        field(L10n.t("connect.identity"), text: $model.identity, placeholder: L10n.t("connect.identityPlaceholder"), secure: false)
                        field(L10n.t("connect.password"), text: $model.password, placeholder: L10n.t("connect.passwordPlaceholder"), secure: true)
                        field(
                            L10n.t(model.needsServerPassword ? "connect.serverPasswordRequired" : "connect.serverPassword"),
                            text: $model.serverPassword,
                            placeholder: L10n.t("connect.serverPasswordPlaceholder"),
                            secure: true
                        )
                    }
                }

                Toggle(L10n.t("connect.rememberLogin"), isOn: $model.remembersLogin)
                    .font(.caption2)
                    .tint(WatchTheme.accent)

                Button {
                    Task {
                        await model.connect()
                    }
                } label: {
                    Group {
                        if model.isConnecting {
                            Text(L10n.t("connect.connecting"))
                        } else {
                            Text(model.needsServerPassword ? L10n.t("connect.joinServer") : L10n.t("connect.submit"))
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
                .disabled(model.isConnecting || (model.needsServerPassword && model.serverPassword.isEmpty))

                if let connectError = model.connectError {
                    Text(connectError)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.danger)
                        .multilineTextAlignment(.center)
                }

                if let credentialWarning = model.credentialWarning {
                    Text(credentialWarning)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.danger)
                        .multilineTextAlignment(.center)
                }

                NavigationLink {
                    WatchDiagnosticsView()
                } label: {
                    Label(L10n.t("settings.viewLogs"), systemImage: "doc.text")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(8)
            .background(WatchTheme.field, in: RoundedRectangle(cornerRadius: WatchTheme.fieldCorner, style: .continuous))
        }
    }
}
