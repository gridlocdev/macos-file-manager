import AppKit
import FileManagerCore
import SwiftUI

/// The menu bar. Items come from `Action`, with shortcuts from the keymap.
struct AppCommands: Commands {
    private var browser: BrowserModel? { ActiveBrowser.shared.model }
    private let keymap = Keymap.standard

    var body: some Commands {
        // Cmd+H shows hidden files (Linux habit), so Hide loses its shortcut.
        CommandGroup(replacing: .appVisibility) {
            Button("Hide File Manager") { NSApp.hide(nil) }
            Button("Hide Others") { NSApp.hideOtherApplications(nil) }
                .keyboardShortcut("h", modifiers: [.command, .option])
            Button("Show All") { NSApp.unhideAllApplications(nil) }
        }

        CommandGroup(after: .newItem) {
            Divider()
            button(.open)
        }

        CommandGroup(before: .sidebar) {
            Menu("Sort By") {
                ForEach(FileSort.Column.allCases, id: \.self) { column in
                    Button(column.title) { browser?.sort.column = column }
                }
            }
            // A plain button: a menu Toggle (or a Show/Hide title) would go stale, and a stale
            // Toggle writes itself back, undoing Cmd+H. The status bar says when they're shown.
            button(.toggleHiddenFiles)
            button(.refresh)
            Divider()
        }

        CommandMenu("Go") {
            button(.goBack)
            button(.goForward)
            button(.goUp)
            Divider()
            button(.goHome)
            button(.goDesktop)
            button(.goDocuments)
            button(.goDownloads)
            button(.goApplications)
            Divider()
            button(.focusAddressBar)
            button(.openTerminal)
        }

        CommandGroup(replacing: .help) {
            Button("File Manager Help") { openDocs("Home") }
            Button("Keyboard Shortcuts") { openDocs("Keyboard-Shortcuts") }
        }
    }

    /// Always enabled: SwiftUI doesn't re-evaluate menu items when the key window's model
    /// changes, and a stale disabled item swallows its shortcut. `perform` beeps instead.
    private func button(_ action: Action) -> some View {
        Button(action.title) {
            if let browser { browser.perform(action) } else { NSSound.beep() }
        }
        .keyboardShortcut(keymap.menuChord(for: action)?.keyboardShortcut)
    }

    /// The docs ship inside the .app; when running from the build folder, use the repo's.
    private func openDocs(_ page: String) {
        let bundled = Bundle.main.url(forResource: page, withExtension: "md", subdirectory: "docs")
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/\(page).md")
        if let url = bundled ?? (FileManager.default.fileExists(atPath: repo.path) ? repo : nil) {
            NSWorkspace.shared.open(url)
        }
    }
}
