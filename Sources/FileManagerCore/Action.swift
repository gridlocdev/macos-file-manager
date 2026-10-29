/// Every command the user can run. Menus, shortcuts and (later) the right-click menu all
/// refer to these, so each command is defined once.
public enum Action: String, CaseIterable, Sendable {
    case open
    case newWindow, newTab, openInNewTab, reopenClosedTab
    case nextTab, previousTab
    case showTab1, showTab2, showTab3, showTab4, showTab5, showTab6, showTab7, showTab8, showTab9
    case addToSidebar
    case newFolder, newTextFile
    case rename, duplicate
    case getInfo, quickLook, showInFinder, showContextMenu
    case moveToTrash, deleteImmediately, putBack
    case undo, redo
    case cut, copy, paste, pasteMove, copyPath, selectAll
    case goBack, goForward, goUp
    case goHome, goDesktop, goDocuments, goDownloads, goApplications, goTrash
    case focusAddressBar
    case focusNextArea, focusPreviousArea
    case refresh
    case toggleHiddenFiles
    case openTerminal

    public enum Menu: Sendable { case file, edit, view, go }

    /// Menu title; the docs' shortcut table uses the same words.
    public var title: String {
        switch self {
        case .open: "Open"
        case .newWindow: "New Window"
        case .newTab: "New Tab"
        case .openInNewTab: "Open in New Tab"
        case .reopenClosedTab: "Reopen Closed Tab"
        case .nextTab: "Show Next Tab"
        case .previousTab: "Show Previous Tab"
        case .showTab9: "Show Last Tab"
        case .showTab1, .showTab2, .showTab3, .showTab4, .showTab5, .showTab6, .showTab7, .showTab8:
            "Show Tab \(tabNumber ?? 0)"
        case .addToSidebar: "Add to Sidebar"
        case .newFolder: "New Folder"
        case .newTextFile: "New Text File"
        case .rename: "Rename"
        case .duplicate: "Duplicate"
        case .getInfo: "Get Info"
        case .quickLook: "Quick Look"
        case .showInFinder: "Show in Finder"
        case .showContextMenu: "Show Context Menu"
        case .moveToTrash: "Move to Trash"
        case .deleteImmediately: "Delete Immediately…"
        case .putBack: "Put Back"
        case .undo: "Undo"
        case .redo: "Redo"
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .pasteMove: "Move Items Here"
        case .copyPath: "Copy Path"
        case .selectAll: "Select All"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .goUp: "Enclosing Folder"
        case .goHome: "Home"
        case .goDesktop: "Desktop"
        case .goDocuments: "Documents"
        case .goDownloads: "Downloads"
        case .goApplications: "Applications"
        case .goTrash: "Trash"
        case .focusAddressBar: "Go to Location…"
        case .focusNextArea: "Focus Next Area"
        case .focusPreviousArea: "Focus Previous Area"
        case .refresh: "Refresh"
        case .toggleHiddenFiles: "Show Hidden Files"
        case .openTerminal: "Open Terminal Here"
        }
    }

    /// Where it appears in the menu bar; nil for keyboard-only actions.
    public var menu: Menu? {
        switch self {
        case .open, .newFolder, .newTextFile, .rename, .duplicate, .moveToTrash, .deleteImmediately, .putBack,
            .getInfo, .quickLook, .showInFinder, .newWindow, .newTab, .openInNewTab, .reopenClosedTab, .addToSidebar:
            .file
        case .undo, .redo, .cut, .copy, .paste, .pasteMove, .copyPath, .selectAll: .edit
        case .refresh, .toggleHiddenFiles: .view
        case .focusNextArea, .focusPreviousArea, .showContextMenu, .nextTab, .previousTab: nil
        case .showTab1, .showTab2, .showTab3, .showTab4, .showTab5, .showTab6, .showTab7, .showTab8, .showTab9: nil
        default: .go
        }
    }

    /// Acts on the selected files or changes the folder's contents. While text is being edited
    /// (the address bar, a rename), these are passed to the text instead (see `textSelector`)
    /// or ignored, so Cmd+C copies text and Cmd+Backspace doesn't trash files.
    public var actsOnFiles: Bool {
        switch self {
        case .open, .newFolder, .newTextFile, .rename, .duplicate, .moveToTrash, .deleteImmediately, .putBack,
            .undo, .redo, .cut, .copy, .paste, .pasteMove, .copyPath, .selectAll,
            .getInfo, .quickLook, .showInFinder, .showContextMenu, .openInNewTab, .addToSidebar:
            true
        default:
            false
        }
    }

    /// The standard text command to send instead while text is being edited.
    public var textSelector: String? {
        switch self {
        case .undo: "undo:"
        case .redo: "redo:"
        case .cut: "cut:"
        case .copy: "copy:"
        case .paste: "paste:"
        case .selectAll: "selectAll:"
        case .moveToTrash: "deleteToBeginningOfLine:"
        default: nil
        }
    }

    /// Shortcuts macOS already runs itself: Ctrl+Tab and Ctrl+Shift+Tab switch window tabs even
    /// when the app has handled the key, so handling them too would switch twice. They're in
    /// the keymap so the docs list them, but the key handler passes them on.
    public var isHandledByMacOS: Bool { self == .nextTab || self == .previousTab }

    /// 1…9 for the Show Tab actions (9 is the last tab, as in browsers).
    public var tabNumber: Int? {
        switch self {
        case .showTab1: 1
        case .showTab2: 2
        case .showTab3: 3
        case .showTab4: 4
        case .showTab5: 5
        case .showTab6: 6
        case .showTab7: 7
        case .showTab8: 8
        case .showTab9: 9
        default: nil
        }
    }

    /// Plain keys (Return, Delete) for these only work in the file list, so Return in the
    /// sidebar doesn't rename and Delete there doesn't trash the list's selection.
    public var needsFileListFocus: Bool {
        switch self {
        case .rename, .moveToTrash, .deleteImmediately, .open, .quickLook, .showContextMenu, .openInNewTab: true
        default: false
        }
    }
}
