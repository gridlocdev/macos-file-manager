import AppKit
import SwiftUI

@main
struct FileManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() { SettingsKey.registerDefaults() }

    var body: some Scene {
        WindowGroup(for: WindowSpec.self) { $spec in
            BrowserWindow(spec: spec)
        } defaultValue: {
            MainActor.assumeIsolated { Windows.shared.launchSpec() }
        }
        // File Manager reopens windows and tabs itself (Windows), so SwiftUI mustn't as well.
        .restorationBehavior(.disabled)
        // Folders opened from other apps go to the app delegate (Windows.openFromElsewhere);
        // without this SwiftUI would also make an extra blank window for each.
        .handlesExternalEvents(matching: [])
        .commands { AppCommands() }

        WindowGroup("Info", id: InfoWindow.id, for: [URL].self) { $urls in
            InfoWindow(urls: urls ?? [])
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])

        Window("File Operations", id: OperationsWindow.id) {
            OperationsWindow()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .handlesExternalEvents(matching: [])

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

    private let services = ServiceProvider()

    /// Open With File Manager, folders dropped on the Dock icon, `open -a "File Manager" folder`.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { Windows.shared.openFromElsewhere(urls) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Services ▸ Open in File Manager (declared in Info.plist).
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        // Run from `swift run` or the debugger (no .app bundle) it would otherwise start
        // without a Dock icon or menu bar focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        #if DEBUG
        DebugSnapshot.runIfRequested()
        #endif
    }
}

/// The "Open in File Manager" Service, for files and folders selected in Finder and other apps.
final class ServiceProvider: NSObject {
    @objc func openInFileManager(
        _ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "Nothing to open." as NSString
            return
        }
        MainActor.assumeIsolated { Windows.shared.openFromElsewhere(urls) }
    }
}
