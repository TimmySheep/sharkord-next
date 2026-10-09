import SwiftUI
import SharkordCore

/// shows the sign-in screen until the shared session connects to a server.
struct WatchRootView: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var model: WatchSessionModel
    @State private var isSearchActive = false

    var body: some View {
        let _ = model.language
        NavigationStack {
            Group {
                switch session.phase {
                case .disconnected, .connecting, .awaitingServerPassword, .failed:
                    WatchDisconnectedView()
                case .connected:
                    WatchChannelListView(isSearchActive: $isSearchActive)
                }
            }
            .background(WatchTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(L10n.t("nav.settings"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchActive.toggle()
                    } label: {
                        Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                    }
                    .accessibilityLabel(L10n.t(isSearchActive ? "search.close" : "search.open"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct WatchDiagnosticsView: View {
    @State private var logText = ""
    @State private var exportedURL: URL?
    @State private var exportError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("settings.diagnosticsHint"))
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.textSecondary)

                Text(logText.isEmpty ? L10n.t("settings.noLogs") : logText)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    do {
                        exportedURL = try DiagnosticsLogger.shared.exportURL()
                    } catch {
                        DiagnosticsLogger.shared.error("export", "diagnostic log export failed", error: error)
                        exportError = true
                    }
                } label: {
                    Label(L10n.t("settings.exportLogs"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                if let exportedURL {
                    ShareLink(item: exportedURL) {
                        Label(L10n.t("settings.shareLogs"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle(L10n.t("settings.diagnostics"))
        .task {
            logText = DiagnosticsLogger.shared.recentText()
        }
        .alert(L10n.t("settings.exportFailed"), isPresented: $exportError) {
            Button(L10n.t("common.done"), role: .cancel) {}
        }
    }
}
