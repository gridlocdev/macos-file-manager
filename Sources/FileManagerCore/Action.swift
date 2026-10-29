/// Every command the user can run. Menus, shortcuts and (later) the right-click menu all
/// refer to these, so each command is defined once.
public enum Action: String, CaseIterable, Sendable {
    case open
    case goBack, goForward, goUp
    case goHome, goDesktop, goDocuments, goDownloads, goApplications
    case focusAddressBar
    case focusNextArea, focusPreviousArea
    case refresh
    case toggleHiddenFiles
    case openTerminal

    public enum Menu: Sendable { case file, view, go }

    /// Menu title; the docs' shortcut table uses the same words.
    public var title: String {
        switch self {
        case .open: "Open"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .goUp: "Enclosing Folder"
        case .goHome: "Home"
        case .goDesktop: "Desktop"
        case .goDocuments: "Documents"
        case .goDownloads: "Downloads"
        case .goApplications: "Applications"
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
        case .open: .file
        case .refresh, .toggleHiddenFiles: .view
        case .focusNextArea, .focusPreviousArea: nil
        default: .go
        }
    }
}
