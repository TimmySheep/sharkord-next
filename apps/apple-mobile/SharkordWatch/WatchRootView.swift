import SwiftUI
import SharkordCore

/// routing: connect -> channel list -> radio room. Same explicit lifecycle as the
/// product definition: joining a channel starts a radio session, leaving ends it.
struct WatchRootView: View {
    @EnvironmentObject private var session: SharkordSession

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .disconnected, .connecting, .awaitingServerPassword, .failed:
                    WatchConnectView()
                case .connected:
                    WatchChannelListView()
                }
            }
            .background(WatchTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WatchDiagnosticsView()
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel(L10n.t("settings.viewLogs"))
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
