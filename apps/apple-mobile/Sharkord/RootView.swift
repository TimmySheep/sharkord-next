import SharkordCore
import SwiftUI

/// Routes between the connect screen and the workspace based on the session phase.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SharkordSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !model.hasCompletedInitialLoginRestore {
                connecting
            } else {
                switch session.phase {
                case .disconnected, .awaitingServerPassword, .failed:
                    if model.hasSavedLoginCredentials {
                        savedLoginRecovery
                    } else {
                        ConnectView()
                    }
                case .connecting:
                    if model.hasConnected {
                        connectedWorkspace
                    } else {
                        connecting
                    }
                case .connected:
                    WorkspaceView()
                }
            }
        }
        .background(BrandBackground())
        .preferredColorScheme(nil)
        .animation(.easeInOut(duration: 0.18), value: model.isConnected)
        .task {
            await model.restoreSavedLoginIfNeeded()
        }
        .alert(
            L10n.t("loginRecovery.warningTitle"),
            isPresented: Binding(
                get: { model.loginCredentialsWarning != nil },
                set: { isPresented in
                    if !isPresented {
                        model.loginCredentialsWarning = nil
                    }
                }
            )
        ) {
            Button(L10n.t("common.done"), role: .cancel) {}
        } message: {
            Text(model.loginCredentialsWarning ?? "")
        }
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

    private var connectedWorkspace: some View {
        WorkspaceView()
            .safeAreaInset(edge: .top, spacing: 0) {
                if session.phase == .connecting {
                    reconnectingBanner
                }
            }
    }

    private var savedLoginRecovery: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenTitle(text: L10n.t("loginRecovery.title"))

            Text(model.banner ?? L10n.t("loginRecovery.body"))
                .font(.subheadline)
                .foregroundStyle(SharkordTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            SharkordPrimaryButton(
                title: L10n.t("loginRecovery.retry"),
                symbol: "arrow.clockwise"
            ) {
                Task { await model.retrySavedLogin() }
            }

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
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
