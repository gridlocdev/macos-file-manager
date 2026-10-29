/// Every command the user can run. Menus, shortcuts and (later) the right-click menu all
/// refer to these, so each command is defined once.
public enum Action: String, CaseIterable, Sendable {
    case open
    case newFolder, newTextFile
    case rename, duplicate
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
        case .newFolder: "New Folder"
        case .newTextFile: "New Text File"
        case .rename: "Rename"
        case .duplicate: "Duplicate"
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
        case .open, .newFolder, .newTextFile, .rename, .duplicate, .moveToTrash, .deleteImmediately, .putBack: .file
        case .undo, .redo, .cut, .copy, .paste, .pasteMove, .copyPath, .selectAll: .edit
        case .refresh, .toggleHiddenFiles: .view
        case .focusNextArea, .focusPreviousArea: nil
        default: .go
        }
    }

    /// Acts on the selected files or changes the folder's contents. While text is being edited
    /// (the address bar, a rename), these are passed to the text instead (see `textSelector`)
    /// or ignored, so Cmd+C copies text and Cmd+Backspace doesn't trash files.
    public var actsOnFiles: Bool {
        switch self {
        case .open, .newFolder, .newTextFile, .rename, .duplicate, .moveToTrash, .deleteImmediately, .putBack,
            .undo, .redo, .cut, .copy, .paste, .pasteMove, .copyPath, .selectAll:
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

    /// Plain keys (Return, Delete) for these only work in the file list, so Return in the
    /// sidebar doesn't rename and Delete there doesn't trash the list's selection.
    public var needsFileListFocus: Bool {
        switch self {
        case .rename, .moveToTrash, .deleteImmediately, .open: true
        default: false
        }
    }
}
