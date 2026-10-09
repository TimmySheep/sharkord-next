import SharkordCore
import SwiftUI

/// Routes between the connect screen and the workspace based on the session phase.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.hasConnected && (session.phase == .connected || session.phase == .connecting) {
                WorkspaceView()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if session.phase == .connecting {
                            reconnectingBanner
                        }
                    }
            } else {
                switch session.phase {
                case .disconnected, .awaitingServerPassword, .failed:
                    ConnectView()
                case .connecting:
                    connecting
                case .connected:
                    WorkspaceView()
                }
            }
        }
        .background(BrandBackground())
        .preferredColorScheme(nil)
        .animation(.easeInOut(duration: 0.18), value: model.isConnected)
        .onOpenURL { url in
            model.handleLiveActivityURL(url)
        }
        .onAppear {
            model.setAppActive(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            model.setAppActive(phase == .active)
        }
    }

    private var connecting: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SharkordTheme.accentSoft)
            Text(L10n.t(model.isReconnecting ? "connect.reconnecting" : "connect.connecting"))
                .font(.subheadline)
                .foregroundStyle(SharkordTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reconnectingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(SharkordTheme.accentSoft)
            Text(L10n.t("connect.reconnecting"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(SharkordTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SharkordTheme.card)
    }
}
