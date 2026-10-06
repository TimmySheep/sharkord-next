import SharkordCore
import SwiftUI

/// Settings: language (five in this version), the Dynamic Island preview, the connection
/// details and the disconnect action. Every group is a card with a tinted heading.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(text: L10n.t("nav.settings"))

                languageCard
                liveActivityCard
                connectionCard

                SharkordSecondaryButton(
                    title: L10n.t("settings.disconnect"),
                    symbol: "rectangle.portrait.and.arrow.right",
                    tint: SharkordTheme.danger,
                    background: SharkordTheme.dangerDeep
                ) {
                    model.disconnect()
                }

                Text(L10n.t("settings.disconnectHint"))
                    .font(.footnote)
                    .foregroundStyle(SharkordTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                aboutCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(icon: "globe", text: L10n.t("settings.language"), tint: SharkordTheme.accentSoft)

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
                HStack {
                    Text(currentLanguageName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SharkordTheme.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SharkordTheme.accentSoft)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text(L10n.t("settings.languageHint"))
                .font(.footnote)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sharkordCard(cornerRadius: 24)
    }

    private var currentLanguageName: String {
        L10n.supportedLanguages.first { $0.code == model.language }?.nativeName
            ?? L10n.supportedLanguages[0].nativeName
    }

    private var liveActivityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(
                icon: "waveform",
                text: L10n.t("settings.liveActivity"),
                tint: SharkordTheme.accentSoft
            )

            if model.liveActivityRunning {
                SharkordSecondaryButton(
                    title: L10n.t("settings.liveActivityStop"),
                    symbol: "stop.fill",
                    tint: SharkordTheme.danger,
                    background: SharkordTheme.dangerDeep
                ) {
                    model.stopPreviewLiveActivity()
                }
            } else {
                SharkordSecondaryButton(
                    title: L10n.t("settings.liveActivityStart"),
                    symbol: "waveform",
                    tint: SharkordTheme.accentSoft,
                    background: SharkordTheme.field
                ) {
                    model.startPreviewLiveActivity()
                }
            }

            Text(L10n.t("settings.liveActivityHint"))
                .font(.footnote)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sharkordCard(cornerRadius: 24)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(
                icon: "network",
                text: L10n.t("settings.connection"),
                tint: SharkordTheme.accentSoft
            )

            infoRow(label: L10n.t("settings.server"), value: model.serverDisplayName)

            if let user = session.ownUser {
                infoRow(label: L10n.t("settings.account"), value: user.name)
            }
        }
        .sharkordCard(cornerRadius: 24)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(SharkordTheme.textSecondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(SharkordTheme.textPrimary)
                .lineLimit(1)
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeading(icon: "info.circle", text: L10n.t("settings.about"), tint: SharkordTheme.accentSoft)

            Text(L10n.t("settings.aboutBody"))
                .font(.footnote)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sharkordCard(cornerRadius: 24)
    }
}
