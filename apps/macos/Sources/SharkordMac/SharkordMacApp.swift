import AppKit
import SharkordCore
import SwiftUI

@main
struct SharkordMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SharkordSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .frame(minWidth: 900, minHeight: 600)
                // the fixed dark palette relies on semantic text colors resolving for dark mode
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1160, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// A SwiftPM executable is not a bundled app by default, so the process starts as an
/// accessory. Promoting it to a regular app is what makes the window appear and focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SharkordSession

    var body: some View {
        switch session.phase {
        case .connected:
            MainWindow()
        default:
            ConnectView()
        }
    }
}
