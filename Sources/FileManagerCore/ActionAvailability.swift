import Foundation

/// What decides whether an action is available in a pane. `BrowserModel` provides it; tests use
/// a plain struct.
public protocol ActionState {
    var hasSelection: Bool { get }
    /// The selected items, in list order.
    var selectedItems: [FileItem] { get }
    var hasItems: Bool { get }
    /// The folder could be read (it isn't showing an error).
    var canReadFolder: Bool { get }
    var isTrashFolder: Bool { get }
    var isAtRoot: Bool { get }
    var hasOtherPane: Bool { get }
    var tabCount: Int { get }
    var hasClosedTabs: Bool { get }
    var clipboardHasFiles: Bool { get }
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
}

extension Action {
    /// Whether the action can run now. Unavailable actions beep; toolbar buttons grey out, menu
    /// items stay enabled (see the developer guide). Every case is listed, so a new action has
    /// to say when it's available.
    public func isAvailable(in state: some ActionState) -> Bool {
        switch self {
        case .open, .rename, .duplicate, .cut, .copy, .deleteImmediately, .quickLook: state.hasSelection
        case .invertSelection, .selectByPattern: state.hasItems
        case .copyToOtherPane, .moveToOtherPane: state.hasSelection && state.hasOtherPane
        case .compress, .moveToTrash: state.hasSelection && !state.isTrashFolder
        case .putBack: state.hasSelection && state.isTrashFolder
        case .extract: state.selectedItems.contains { !$0.isFolder && Archive.isArchive($0.url) }
        case .downloadNow: state.selectedItems.contains { $0.cloud == .notDownloaded }
        case .removeDownload: state.selectedItems.contains { $0.cloud == .current }
        case .openInNewTab: state.selectedItems.contains(where: \.isFolder)
        case .reopenClosedTab: state.hasClosedTabs
        case .nextTab, .previousTab, .showTab9: state.tabCount > 1
        case .showTab1, .showTab2, .showTab3, .showTab4, .showTab5, .showTab6, .showTab7, .showTab8:
            (tabNumber ?? 0) <= state.tabCount
        case .paste, .pasteMove: state.clipboardHasFiles && state.canReadFolder
        case .newFolder, .newTextFile: state.canReadFolder
        case .undo: state.canUndo
        case .redo: state.canRedo
        case .goBack: state.canGoBack
        case .goForward: state.canGoForward
        case .goUp: !state.isAtRoot
        case .newWindow, .newTab, .addToSidebar, .getInfo, .showInFinder, .showContextMenu, .toggleSplitView,
            .connectToServer, .copyPath, .selectAll, .find, .endSearch, .goHome, .goDesktop, .goDocuments,
            .goDownloads, .goApplications, .goTrash, .focusAddressBar, .focusNextArea, .focusPreviousArea, .refresh,
            .toggleHiddenFiles, .viewAsIcons, .viewAsDetails, .zoomIn, .zoomOut, .actualSize, .togglePreviewPane,
            .openTerminal:
            true
        }
    }
}
