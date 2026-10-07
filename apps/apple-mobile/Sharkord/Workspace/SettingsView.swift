import SharkordCore
import SwiftUI

/// settings for language, connection and developer-only tools.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                languageCard
                connectionCard
                developerCard

                SharkordSecondaryButton(
                    title: L10n.t("settings.disconnect"),
                    symbol: "rectangle.portrait.and.arrow.right",
                    tint: SharkordTheme.danger,
                    background: SharkordTheme.dangerDeep
                ) {
                    model.disconnect()
                }

            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(L10n.t("nav.settings"))
        .navigationBarTitleDisplayMode(.large)
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

        }
        .sharkordCard(cornerRadius: 24)
    }

    private var currentLanguageName: String {
        L10n.supportedLanguages.first { $0.code == model.language }?.nativeName
            ?? L10n.supportedLanguages[0].nativeName
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

    private var developerCard: some View {
        NavigationLink {
            DeveloperSettingsView()
        } label: {
            HStack {
                Label(L10n.t("settings.developer"), systemImage: "wrench.and.screwdriver")
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(SharkordTheme.textPrimary)
            .padding(18)
            .sharkordCard(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }
}

private struct DeveloperSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                liveActivityCard
                diagnosticsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(L10n.t("settings.developer"))
        .navigationBarTitleDisplayMode(.inline)
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

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(icon: "doc.text.magnifyingglass", text: L10n.t("settings.diagnostics"), tint: SharkordTheme.accentSoft)

            NavigationLink {
                DiagnosticsLogView()
            } label: {
                HStack {
                    Label(L10n.t("settings.viewLogs"), systemImage: "doc.text")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(SharkordTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(SharkordTheme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .sharkordCard(cornerRadius: 24)
    }
}

struct DiagnosticsLogView: View {
    @State private var logText = ""
    @State private var exportedURL: URL?
    @State private var showShareSheet = false
    @State private var showExportError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(logText.isEmpty ? L10n.t("settings.noLogs") : logText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(SharkordTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SharkordSecondaryButton(
                    title: L10n.t("settings.exportLogs"),
                    symbol: "square.and.arrow.up",
                    tint: SharkordTheme.accentSoft,
                    background: SharkordTheme.field,
                    action: prepareExport
                )
            }
            .padding(20)
        }
        .background(BrandBackground())
        .navigationTitle(L10n.t("settings.diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            logText = DiagnosticsLogger.shared.recentText()
        }
        .sheet(isPresented: $showShareSheet) {
            VStack(spacing: 18) {
                Text(L10n.t("settings.exportLogs"))
                    .font(.headline)
                if let exportedURL {
                    ShareLink(item: exportedURL) {
                        Label(L10n.t("settings.shareLogs"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .presentationDetents([.medium])
        }
        .alert(L10n.t("settings.exportFailed"), isPresented: $showExportError) {
            Button(L10n.t("common.done"), role: .cancel) {}
        }
    }

    private func prepareExport() {
        do {
            exportedURL = try DiagnosticsLogger.shared.exportURL()
            showShareSheet = true
        } catch {
            DiagnosticsLogger.shared.error("export", "diagnostic log export failed", error: error)
            showExportError = true
        }
    }
}
