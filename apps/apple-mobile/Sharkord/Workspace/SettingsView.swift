import SharkordCore
import SwiftUI

/// Settings: language (five in this version), the Dynamic Island preview, the connection
/// details and the disconnect action.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.t("settings.language")) {
                    Picker(L10n.t("settings.language"), selection: languageBinding) {
                        ForEach(L10n.supportedLanguages, id: \.code) { language in
                            Text(language.nativeName).tag(language.code)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(L10n.t("settings.languageHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.t("settings.liveActivity")) {
                    if model.liveActivityRunning {
                        Button {
                            model.stopPreviewLiveActivity()
                        } label: {
                            Label(L10n.t("settings.liveActivityStop"), systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            model.startPreviewLiveActivity()
                        } label: {
                            Label(L10n.t("settings.liveActivityStart"), systemImage: "island")
                        }
                    }

                    Text(L10n.t("settings.liveActivityHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.t("settings.connection")) {
                    LabeledContent(L10n.t("settings.server"), value: model.serverDisplayName)

                    if let user = session.ownUser {
                        LabeledContent(L10n.t("settings.account"), value: user.name)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        model.disconnect()
                    } label: {
                        Label(L10n.t("settings.disconnect"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text(L10n.t("settings.disconnectHint"))
                }

                Section(L10n.t("settings.about")) {
                    Text(L10n.t("settings.aboutBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.t("nav.settings"))
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { model.language },
            set: { model.setLanguage($0) }
        )
    }
}
