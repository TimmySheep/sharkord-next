import SharkordCore
import SwiftUI
import WatchConnectivity

struct WatchSettingsView: View {
    @EnvironmentObject private var model: WatchSessionModel
    @EnvironmentObject private var session: SharkordSession
    @State private var selectedLanguage = L10n.current
    @State private var isCheckingConnectivity = false
    @State private var connectivityResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(L10n.t("settings.language"), selection: $selectedLanguage) {
                            ForEach(L10n.supportedLanguages, id: \.code) { language in
                                Text(language.nativeName).tag(language.code)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .tint(WatchTheme.accentSoft)
                        .onChange(of: selectedLanguage) { _, language in
                            model.setLanguage(language)
                        }
                    }
                }

                WatchCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t("watch.settingsConnectivity"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WatchTheme.textSecondary)

                        Button {
                            Task {
                                await checkConnectivity()
                            }
                        } label: {
                            Label(
                                isCheckingConnectivity ? L10n.t("watch.checkingConnectivity") : L10n.t("watch.checkConnectivity"),
                                systemImage: "network"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .disabled(isCheckingConnectivity)

                        if let connectivityResult {
                            Text(connectivityResult)
                                .font(.caption2)
                                .foregroundStyle(WatchTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                NavigationLink {
                    WatchDiagnosticsView()
                } label: {
                    WatchCard {
                        Label(L10n.t("settings.diagnostics"), systemImage: "doc.text.magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WatchTheme.textPrimary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle(L10n.t("nav.settings"))
    }

    @MainActor
    private func checkConnectivity() async {
        isCheckingConnectivity = true
        defer { isCheckingConnectivity = false }

        guard let url = serverURL else {
            connectivityResult = L10n.t("watch.serverNotConfigured")
            return
        }

        do {
            _ = try await SharkordHTTPClient(baseURL: url).serverInfo()
            let phoneReachable = WCSession.default.isReachable
            connectivityResult = L10n.t(phoneReachable ? "watch.serverAndPhoneReachable" : "watch.serverReachable")
        } catch {
            connectivityResult = L10n.t("watch.serverUnreachable")
        }
    }

    private var serverURL: URL? {
        let storedHost = session.linkedDeviceHost ?? model.server
        let trimmed = storedHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let value = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil
        else {
            return nil
        }
        return components.url
    }
}
