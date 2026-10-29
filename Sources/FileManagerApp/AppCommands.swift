import AppKit
import FileManagerCore
import SwiftUI

/// The menu bar. Items come from `Action`, with shortcuts from the keymap.
struct AppCommands: Commands {
    private var browser: BrowserModel? { ActiveBrowser.shared.model }
    @Environment(\.openWindow) private var openWindow
    private let keymap = Keymap.standard

    var body: some Commands {
        // Cmd+H shows hidden files (Linux habit), so Hide loses its shortcut.
        CommandGroup(replacing: .appVisibility) {
            Button("Hide File Manager") { NSApp.hide(nil) }
            Button("Hide Others") { NSApp.hideOtherApplications(nil) }
                .keyboardShortcut("h", modifiers: [.command, .option])
            Button("Show All") { NSApp.unhideAllApplications(nil) }
        }

        CommandGroup(replacing: .newItem) {
            button(.newWindow)
            button(.newTab)
            button(.openInNewTab)
            button(.reopenClosedTab)
        }

        CommandGroup(after: .newItem) {
            Divider()
            button(.newFolder)
            button(.newTextFile)
            Divider()
            button(.open)
            button(.quickLook)
            button(.getInfo)
            button(.showInFinder)
            button(.addToSidebar)
            Divider()
            button(.rename)
            button(.duplicate)
            Divider()
            button(.moveToTrash)
            button(.deleteImmediately)
            button(.putBack)
        }

        // Edit acts on files in the list and on text while typing (address bar, rename).
        CommandGroup(replacing: .undoRedo) {
            button(.undo)
            button(.redo)
        }
        CommandGroup(replacing: .pasteboard) {
            button(.cut)
            button(.copy)
            button(.paste)
            button(.pasteMove)
            Divider()
            button(.copyPath)
            button(.selectAll)
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
            button(.goTrash)
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
        Button(action.title) { run(action) }
            .keyboardShortcut(keymap.menuChord(for: action)?.keyboardShortcut)
    }

    /// Menu shortcuts reach here even while text is being edited (menus see keys first), so
    /// Cmd+C in the address bar must copy text, not files, and Cmd+Backspace must not trash.
    private func run(_ action: Action) {
        let keyWindow = NSApp.keyWindow
        let editingText = keyWindow?.firstResponder is NSText
        let inBrowser = keyWindow != nil && keyWindow === browser?.window
        if action.actsOnFiles, editingText || !inBrowser {
            if let selector = action.textSelector {
                NSApp.sendAction(Selector(selector), to: nil, from: nil)
            } else if editingText {
                NSSound.beep()
            }
            return
        }
        if let browser {
            browser.perform(action)
        } else if action == .newWindow || action == .newTab {
            // No window open: still make one.
            openWindow(value: WindowSpec())
        } else if action == .reopenClosedTab, let path = Windows.shared.popClosedTab() {
            openWindow(value: WindowSpec(path: path))
        } else {
            NSSound.beep()
        }
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
