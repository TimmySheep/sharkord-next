import SharkordCore
import SwiftUI

/// Sign in to a Sharkord server. Nothing is faked here: the address is checked, the
/// account is logged in over `POST /login` and the session joins the server over the
/// tRPC websocket, exactly like the web client.
struct ConnectView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    @State private var host = ""
    @State private var identity = ""
    @State private var password = ""
    @State private var serverPassword = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                fields
                submit
                if let banner = model.banner {
                    bannerView(banner)
                }
            }
            .padding(22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("🦈")
                .font(.system(size: 44))
                .accessibilityHidden(true)

            Text(L10n.t("connect.title"))
                .font(.largeTitle.weight(.bold))

            Text(L10n.t("connect.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fields: some View {
        VStack(spacing: 15) {
            SharkordField(
                title: L10n.t("connect.server"),
                placeholder: L10n.t("connect.serverPlaceholder"),
                symbol: "globe",
                text: $host,
                keyboardType: .URL
            )

            SharkordField(
                title: L10n.t("connect.identity"),
                placeholder: L10n.t("connect.identityPlaceholder"),
                symbol: "person",
                text: $identity
            )

            SharkordField(
                title: L10n.t("connect.password"),
                placeholder: L10n.t("connect.passwordPlaceholder"),
                symbol: "lock",
                text: $password,
                secure: true
            )

            SharkordField(
                title: L10n.t("connect.serverPassword"),
                placeholder: L10n.t("connect.serverPasswordPlaceholder"),
                symbol: "key",
                text: $serverPassword,
                secure: true
            )
        }
    }

    private var submit: some View {
        SharkordPrimaryButton(
            title: L10n.t("connect.submit"),
            symbol: "arrow.right",
            enabled: canSubmit
        ) {
            model.banner = nil
            Task {
                await model.connect(
                    host: host,
                    identity: identity,
                    password: password,
                    serverPassword: serverPassword
                )
            }
        }
    }

    private var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !identity.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 4
    }

    private func bannerView(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharkordGlassCard(cornerRadius: 16)
    }
}
