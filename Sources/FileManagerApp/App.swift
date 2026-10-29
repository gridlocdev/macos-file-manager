import AppKit
import SwiftUI

@main
struct FileManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
        }
        .commands { AppCommands() }

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
