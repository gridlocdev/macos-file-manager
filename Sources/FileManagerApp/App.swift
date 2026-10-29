import AppKit
import SwiftUI

@main
struct FileManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(for: WindowSpec.self) { $spec in
            BrowserWindow(spec: spec)
        } defaultValue: {
            MainActor.assumeIsolated { Windows.shared.launchSpec() }
        }
        // File Manager reopens windows and tabs itself (Windows), so SwiftUI mustn't as well.
        .restorationBehavior(.disabled)
        .commands { AppCommands() }

        WindowGroup("Info", id: InfoWindow.id, for: [URL].self) { $urls in
            InfoWindow(urls: urls ?? [])
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("File Operations", id: OperationsWindow.id) {
            OperationsWindow()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save windows and tabs while they're all still open.
        MainActor.assumeIsolated { Windows.shared.saveForQuit() }
        return .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run from `swift run` or the debugger (no .app bundle) it would otherwise start
        // without a Dock icon or menu bar focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        #if DEBUG
        DebugSnapshot.runIfRequested()
        #endif
    }
}
