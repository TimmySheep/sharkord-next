import SharkordCore
import SwiftUI

/// Routes between the connect screen and the workspace based on the session phase.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession

    var body: some View {
        Group {
            switch session.phase {
            case .disconnected, .awaitingServerPassword, .failed:
                ConnectView()
            case .connecting:
                connecting
            case .connected:
                WorkspaceView()
            }
        }
        .background(BrandBackground())
        .preferredColorScheme(session.phase == .connected ? .dark : nil)
        .animation(.easeInOut(duration: 0.18), value: model.isConnected)
    }

    private var connecting: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SharkordTheme.accentSoft)
            Text(L10n.t("connect.connecting"))
                .font(.subheadline)
                .foregroundStyle(SharkordTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
