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
    @State private var showsAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                connectCard
                if let banner = model.banner {
                    bannerView(banner)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                languageButton
            }

            ScreenTitle(text: L10n.t("connect.title"))

            Text(L10n.t("connect.subtitle"))
                .font(.subheadline)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languageButton: some View {
        Menu {
            ForEach(L10n.supportedLanguages, id: \.code) { language in
                Button {
                    model.setLanguage(language.code)
                } label: {
                    if model.language == language.code {
                        Label(language.nativeName, systemImage: "checkmark")
                    } else {
                        Text(language.nativeName)
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SharkordTheme.accentSoft)
                .frame(width: 56, height: 56)
                .background(SharkordTheme.card, in: Circle())
        }
        .accessibilityLabel(L10n.t("settings.language"))
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardHeading(icon: "server.rack", text: L10n.t("connect.cardTitle"))

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

            advancedToggle

            if showsAdvanced {
                SharkordField(
                    title: L10n.t("connect.serverPassword"),
                    placeholder: L10n.t("connect.serverPasswordPlaceholder"),
                    symbol: "key",
                    text: $serverPassword,
                    secure: true
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
        .sharkordCard(cornerRadius: 28)
    }

    private var advancedToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                showsAdvanced.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharkordTheme.accentSoft)

                Text(showsAdvanced ? L10n.t("connect.fewerOptions") : L10n.t("connect.moreOptions"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SharkordTheme.accentSoft)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .rotationEffect(.degrees(showsAdvanced ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SharkordTheme.danger)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharkordCard(cornerRadius: 18)
    }
}
