import AppKit
import SharkordCore
import SwiftUI

@main
struct SharkordMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SharkordSession()
    @StateObject private var voiceMedia = VoiceMediaController()
    @StateObject private var notifications = DesktopNotificationController()
    @StateObject private var pushToTalk = PushToTalkController()
    @StateObject private var keyboardShortcuts = KeyboardShortcutsController()
    @AppStorage("app.appearance") private var appearance = "system"

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(session)
                .environmentObject(voiceMedia)
                .environmentObject(notifications)
                .environmentObject(pushToTalk)
                .environmentObject(keyboardShortcuts)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1160, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarStatusView()
                .environmentObject(session)
                .environmentObject(voiceMedia)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform")

                let unreadCount = session.unreadByChannel.values.reduce(0) { $0 + max(0, $1) }

                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : String(unreadCount))
                        .font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// A SwiftPM executable is not a bundled app by default, so the process starts as an
/// accessory. Promoting it to a regular app is what makes the window appear and focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let osMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        ClientLogStore.shared.recordInfo("app.launched", code: "macos.\(osMajorVersion)")
        NSSetUncaughtExceptionHandler { exception in
            ClientLogStore.shared.recordFailure("app.uncaught_exception", code: exception.name.rawValue)
        }

        if Bundle.main.bundleURL.pathExtension != "app",
           let iconURL = Bundle.module.url(forResource: "cove", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SharkordSession
    @EnvironmentObject private var voiceMedia: VoiceMediaController
    @EnvironmentObject private var notifications: DesktopNotificationController
    @EnvironmentObject private var pushToTalk: PushToTalkController
    @EnvironmentObject private var keyboardShortcuts: KeyboardShortcutsController
    @Environment(\.openWindow) private var openWindow
    @AppStorage("login.autoLoginEnabled") private var autoLoginEnabled = true

    var body: some View {
        Group {
            switch session.phase {
            case .connected:
                MainWindow()
            default:
                ConnectView()
            }
        }
        .onAppear {
            voiceMedia.bind(to: session)
            notifications.bind(to: session)
            notifications.requestAuthorizationIfNeeded()
            notifications.setOpenClientHandler {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            pushToTalk.bind(to: session, voiceMedia: voiceMedia)
            pushToTalk.restoreEnabled(UserDefaults.standard.bool(forKey: "voice.pushToTalkEnabled"))
            keyboardShortcuts.startMonitoring(session: session, voiceMedia: voiceMedia)

            Task {
                await session.attemptAutomaticLogin(enabled: autoLoginEnabled)
            }
        }
        .alert(
            L10n.t("credentialStorageFailed", ns: "macos"),
            isPresented: Binding(
                get: { session.phase == .connected && session.loginCredentialsSaveFailed },
                set: { isPresented in
                    if !isPresented {
                        session.dismissLoginCredentialsSaveFailure()
                    }
                }
            )
        ) {
            Button(L10n.t("close", ns: "common"), role: .cancel) {
                session.dismissLoginCredentialsSaveFailure()
            }
        }
    }
}
