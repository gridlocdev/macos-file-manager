import AppKit
import FileManagerCore
import Observation

/// One folder view: what's shown, history, selection. Every window and tab has one (tabs are
/// windows; see `Windows`).
@MainActor @Observable
final class BrowserModel {
    let id: UUID
    private(set) var url: URL
    private(set) var items: [FileItem] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    /// Bumped whenever `items` is replaced, so the table knows to reload.
    private(set) var listingVersion = 0
    private(set) var history: NavigationHistory

    var selection: Set<URL> = []
    var sort = FileSort() { didSet { if sort != oldValue { applyFilterAndSort() } } }
    var showHiddenFiles = false { didSet { if showHiddenFiles != oldValue { applyFilterAndSort() } } }

    /// Address bar text while editing; reset to the current folder on navigation or cancel.
    var addressText = ""
    /// Bumped to move keyboard focus to the address bar / the file list.
    private(set) var addressFocusRequest = 0
    private(set) var listFocusRequest = 0
    /// Scrolled to after the next load (the folder you came up from, a pasted item).
    private(set) var revealAfterLoad: URL?
    /// Bumped to toggle Quick Look / show the right-click menu from the keyboard.
    private(set) var quickLookRequest = 0
    private(set) var contextMenuRequest = 0
    /// Get Info asks the window to open an Info window for these.
    private(set) var infoRequest: [URL] = []
    private(set) var infoRequestCount = 0
    /// Free space on the current folder's disk, for the status bar.
    private(set) var freeSpace: Int64?
    /// Windows and tabs to open (the window calls `openWindow` for these).
    private(set) var openRequests: [WindowSpec] = []
    private(set) var openRequestCount = 0

    /// Bumped to start renaming `renameTarget` in the list.
    private(set) var renameRequest = 0
    private(set) var renameTarget: URL?

    /// The window this model lives in, for focus moves. Set by `KeyMonitor`.
    weak var window: NSWindow?

    let home = FileManager.default.homeDirectoryForCurrentUser
    private var allItems: [FileItem] = []
    private var loadTask: Task<Void, Never>?
    private var freeSpaceTask: Task<Void, Never>?
    private var watcher: DirectoryWatcher?
    /// Selected once the next load shows them (new, pasted or renamed items).
    private var pendingSelection: Set<URL> = []
    private var pendingRename: URL?
    private var started = false

    /// Cheap: SwiftUI may create throwaway models. Nothing is read until `start()`.
    init(start: URL? = nil, id: UUID = UUID()) {
        self.id = id
        let start = (start ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
        url = start
        history = NavigationHistory(start: start)
        addressText = PathInput.display(start, home: home)
    }

    /// Loads the first folder. Called once the window appears.
    func start() {
        guard !started else { return }
        started = true
        SidebarStore.shared.visited(url.path)
        load()
    }

    var title: String {
        url.path == "/" ? (volumeName(of: url) ?? "/") : FileManager.default.displayName(atPath: url.path)
    }

    // MARK: Navigation

    func navigate(to target: URL) {
        let target = target.standardizedFileURL
        guard target != url else { return }
        history.visit(target)
        show(target)
    }

    func goBack() { if let target = history.goBack() { show(target) } }
    func goForward() { if let target = history.goForward() { show(target) } }

    func goUp() {
        guard url.path != "/" else { return }
        navigate(to: url.deletingLastPathComponent())
    }

    func refresh() { load(keepSelection: true) }

    /// Reloads, then selects `urls` (and starts renaming `rename`) once they're listed.
    func refresh(selecting urls: [URL], rename: URL? = nil) {
        let urls = urls.map(\.normalized)
        pendingSelection = Set(urls)
        pendingRename = rename?.normalized
        revealAfterLoad = urls.first
        load()
    }

    private func show(_ target: URL) {
        let previous = url
        url = target
        addressText = PathInput.display(target, home: home)
        selection = []
        // Going up (or back to a parent) selects the folder you came from, like Explorer.
        let cameFromChild = previous.deletingLastPathComponent().standardizedFileURL == target
        revealAfterLoad = cameFromChild ? previous.normalized : nil
        pendingSelection = cameFromChild ? [previous.normalized] : []
        pendingRename = nil
        SidebarStore.shared.visited(target.path)
        Windows.shared.scheduleSave()
        load()
    }

    /// Opens folders here and everything else with its default app.
    func open(_ urls: Set<URL>) {
        let chosen = items.filter { urls.contains($0.url) }
        if let folder = chosen.first(where: \.isFolder) {
            navigate(to: folder.url)
        }
        let files = chosen.filter { !$0.isFolder }.map(\.url)
        for file in files { NSWorkspace.shared.open(file) }
    }

    // MARK: Address bar

    func focusAddressBar() { addressFocusRequest += 1 }
    func focusList() { listFocusRequest += 1 }

    func submitAddress() {
        guard let target = PathInput.resolve(addressText, relativeTo: url, home: home) else {
            cancelAddressEdit()
            return
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                navigate(to: target)
            } else {
                // A file: go to its folder and select it.
                navigate(to: target.deletingLastPathComponent())
                revealAfterLoad = target.normalized
                pendingSelection = [target.normalized]
            }
            addressText = PathInput.display(url, home: home)
            focusList()
        } else {
            NSSound.beep()
        }
    }

    func cancelAddressEdit() {
        addressText = PathInput.display(url, home: home)
        focusList()
    }

    func completeAddress() {
        let completed = PathInput.complete(addressText, relativeTo: url, home: home) { folder in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { name in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: folder.appendingPathComponent(name).path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
        }
        if let completed { addressText = completed } else { NSSound.beep() }
    }

    // MARK: Actions

    /// The Trash, or a volume's .Trashes folder.
    var isTrashFolder: Bool {
        url.path == home.appendingPathComponent(".Trash").path || url.path.contains("/.Trashes/")
    }

    /// Selected items in list order.
    var selectedURLs: [URL] { items.filter { selection.contains($0.url) }.map(\.url) }

    func canPerform(_ action: Action) -> Bool {
        let ops = FileOperations.shared
        switch action {
        case .open, .rename, .duplicate, .cut, .copy, .deleteImmediately, .quickLook: return !selection.isEmpty
        case .openInNewTab: return items.contains { selection.contains($0.url) && $0.isFolder }
        case .reopenClosedTab: return Windows.shared.hasClosedTabs
        case .nextTab, .previousTab: return (window?.tabGroup?.windows.count ?? 1) > 1
        case .showTab1, .showTab2, .showTab3, .showTab4, .showTab5, .showTab6, .showTab7, .showTab8, .showTab9:
            let count = window?.tabGroup?.windows.count ?? 1
            return action == .showTab9 ? count > 1 : (action.tabNumber ?? 0) <= count
        case .moveToTrash: return !selection.isEmpty && !isTrashFolder
        case .putBack: return !selection.isEmpty && isTrashFolder
        case .paste, .pasteMove: return Clipboard.shared.hasFiles && errorMessage == nil
        case .newFolder, .newTextFile: return errorMessage == nil
        case .undo: return ops.canUndo
        case .redo: return ops.canRedo
        case .goBack: return history.canGoBack
        case .goForward: return history.canGoForward
        case .goUp: return url.path != "/"
        default: return true
        }
    }

    func perform(_ action: Action) {
        guard canPerform(action) else {
            NSSound.beep()
            return
        }
        switch action {
        case .open: open(selection)
        case .goBack: goBack()
        case .goForward: goForward()
        case .goUp: goUp()
        case .goHome: navigate(to: home)
        case .goDesktop: navigate(to: home.appendingPathComponent("Desktop"))
        case .goDocuments: navigate(to: home.appendingPathComponent("Documents"))
        case .goDownloads: navigate(to: home.appendingPathComponent("Downloads"))
        case .goApplications: navigate(to: URL(fileURLWithPath: "/Applications"))
        case .focusAddressBar: focusAddressBar()
        case .focusNextArea: moveFocus(forward: true)
        case .focusPreviousArea: moveFocus(forward: false)
        case .newWindow: requestOpen(WindowSpec(path: url.path))
        case .newTab: requestOpen(WindowSpec(path: url.path, tabParent: id, select: true))
        case .openInNewTab: openInNewTabs(items.filter { selection.contains($0.url) && $0.isFolder }.map(\.url))
        case .reopenClosedTab:
            if let path = Windows.shared.popClosedTab() {
                requestOpen(WindowSpec(path: path, tabParent: id, select: true))
            }
        case .nextTab: showTab(offset: 1)
        case .previousTab: showTab(offset: -1)
        case .showTab1, .showTab2, .showTab3, .showTab4, .showTab5, .showTab6, .showTab7, .showTab8, .showTab9:
            let tabs = window?.tabGroup?.windows ?? []
            let index = action == .showTab9 ? tabs.count - 1 : (action.tabNumber ?? 1) - 1
            if tabs.indices.contains(index) { tabs[index].makeKeyAndOrderFront(nil) }
        case .addToSidebar:
            let folders = items.filter { selection.contains($0.url) && $0.isFolder }.map(\.url.path)
            SidebarStore.shared.pin(folders.isEmpty ? [url.path] : folders)
        case .refresh: refresh()
        case .toggleHiddenFiles: showHiddenFiles.toggle()
        case .openTerminal: TerminalLauncher.open(url)
        case .goTrash: navigate(to: home.appendingPathComponent(".Trash"))
        case .selectAll: selection = Set(items.map(\.url))
        case .copy: Clipboard.shared.copy(selectedURLs)
        case .cut: Clipboard.shared.cut(selectedURLs)
        case .copyPath:
            let paths = selection.isEmpty ? [url.path] : selectedURLs.map(\.path)
            Clipboard.shared.copyText(paths.joined(separator: "\n"))
        case .paste: paste(move: Clipboard.shared.isCut)
        case .pasteMove: paste(move: true)
        case .rename: startRename(selectedURLs[0])
        case .duplicate: duplicate()
        case .newFolder: create(folder: true)
        case .newTextFile: create(folder: false)
        case .moveToTrash: moveToTrash()
        case .deleteImmediately: deleteImmediately()
        case .putBack: putBack()
        case .undo: undoOrRedo(undo: true)
        case .redo: undoOrRedo(undo: false)
        case .getInfo:
            infoRequest = selection.isEmpty ? [url] : selectedURLs
            infoRequestCount += 1
        case .quickLook: quickLookRequest += 1
        case .showContextMenu: contextMenuRequest += 1
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting(selection.isEmpty ? [url] : selectedURLs)
        }
    }

    /// Files dropped on the list, a folder in it, or the sidebar.
    func drop(_ sources: [URL], into folder: URL, operation: DropRules.Operation) {
        guard operation != .none else { return }
        let here = url
        Task {
            let results = await ops.transfer(sources, into: folder, mode: operation == .copy ? .copy : .move, window: window)
            if folder.path == here.path, here == url { refresh(selecting: results) } else { refresh() }
        }
    }

    /// Total size of the selected files (folders aren't added up, as in Explorer's status bar).
    var selectionSize: Int64 {
        items.filter { selection.contains($0.url) && !$0.isFolder }.reduce(0) { $0 + ($1.size ?? 0) }
    }

    // MARK: Windows and tabs

    /// Next/previous tab, wrapping around. The Ctrl+Tab keys themselves are left to macOS (see
    /// `Action.isHandledByMacOS`); this is for other callers.
    private func showTab(offset: Int) {
        guard let window, let tabs = window.tabGroup?.windows, let index = tabs.firstIndex(of: window) else { return }
        tabs[(index + offset + tabs.count) % tabs.count].makeKeyAndOrderFront(nil)
    }

    func requestOpen(_ spec: WindowSpec) {
        openRequests.append(spec)
        openRequestCount += 1
    }

    func takeOpenRequests() -> [WindowSpec] {
        defer { openRequests = [] }
        return openRequests
    }

    /// Middle-click, Ctrl+Return or the menu: each folder in a tab of this window, in the
    /// background like a browser (this tab stays in front).
    func openInNewTabs(_ folders: [URL]) {
        for folder in folders { requestOpen(WindowSpec(path: folder.path, tabParent: id, select: false)) }
    }

    /// F6 / Shift+F6, like Explorer: file list → address bar → sidebar → file list.
    private func moveFocus(forward: Bool) {
        guard let window else { return }
        let responder = window.firstResponder
        let inList = responder is FileTableView
        let inAddress = responder is NSText
        let sidebar = Self.sidebarView(in: window.contentView)
        func focusSidebar() {
            if let sidebar { window.makeFirstResponder(sidebar) } else { focusList() }
        }
        switch (forward, inList, inAddress) {
        case (true, true, _): focusAddressBar()
        case (true, _, true): focusSidebar()
        case (false, true, _): focusSidebar()
        case (false, _, true): focusList()
        case (false, _, _): focusAddressBar()
        default: focusList()
        }
    }

    /// The sidebar list's AppKit view: the first table or outline that isn't the file list.
    private static func sidebarView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is NSTableView, !(view is FileTableView) { return view }
        for child in view.subviews {
            if let found = sidebarView(in: child) { return found }
        }
        return nil
    }

    // MARK: File operations

    private var ops: FileOperations { .shared }

    private func paste(move: Bool) {
        let sources = Clipboard.shared.fileURLs
        let folder = url
        let wasCut = move && Clipboard.shared.isCut
        Task {
            let results = await ops.transfer(sources, into: folder, mode: move ? .move : .copy, window: window)
            if wasCut, !results.isEmpty { Clipboard.shared.finishCut() }
            if folder == url { refresh(selecting: results) }
        }
    }

    private func duplicate() {
        let sources = selectedURLs
        let folder = url
        Task {
            let results = await ops.transfer(sources, into: folder, mode: .copy, window: window)
            if folder == url { refresh(selecting: results) }
        }
    }

    /// New Folder / New Text File: makes it, selects it and starts renaming, like Explorer.
    private func create(folder isFolder: Bool) {
        let names = Set(allItems.map(\.name) + allItems.map(\.url.lastPathComponent))
        let base = isFolder ? FileNaming.newFolderName : FileNaming.newTextFileName
        let target = url.appendingPathComponent(FileNaming.unique(base, isFolder: isFolder, existing: names))
        let folder = url
        Task {
            let outcome = await ops.run(
                isFolder ? "New Folder" : "New Text File",
                steps: [isFolder ? .createFolder(target) : .createFile(target)], window: window)
            if outcome.error == nil, folder == url { refresh(selecting: [target], rename: target) }
        }
    }

    func startRename(_ target: URL) {
        renameTarget = target
        renameRequest += 1
    }

    /// Called by the list when editing ends. Returns false (and explains) if the name can't be used.
    func commitRename(_ item: URL, to newName: String) {
        let oldName = item.lastPathComponent
        guard newName != oldName, newName != FileManager.default.displayName(atPath: item.path) else { return }
        if let problem = FileNaming.problem(with: newName) {
            showProblem("Can't rename “\(oldName)”", problem)
            return
        }
        let target = item.deletingLastPathComponent().appendingPathComponent(newName)
        let caseChangeOnly = newName.lowercased() == oldName.lowercased()
        if !caseChangeOnly, FileManager.default.fileExists(atPath: target.path) {
            showProblem("Can't rename “\(oldName)”", "There's already an item named “\(newName)” here.")
            return
        }
        Task {
            let outcome = await ops.run("Rename", steps: [.move(item, to: target)], window: window)
            if outcome.error == nil { refresh(selecting: [target]) }
        }
    }

    private func moveToTrash() {
        let targets = selectedURLs
        // Select whatever is next, so pressing Delete again keeps going down the list.
        let next = items.drop { !selection.contains($0.url) }.first { !selection.contains($0.url) }?.url
        let title = targets.count == 1 ? "Move “\(targets[0].lastPathComponent)” to Trash" : "Move \(targets.count) items to Trash"
        Task {
            await ops.run(title, steps: targets.map { .trash($0) }, window: window)
            refresh(selecting: next.map { [$0] } ?? [])
        }
    }

    private func deleteImmediately() {
        let targets = selectedURLs
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText =
            targets.count == 1
            ? "Delete “\(targets[0].lastPathComponent)” immediately?"
            : "Delete \(targets.count) items immediately?"
        alert.informativeText = "They won't go to the Trash, and you can't undo this."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        Task {
            guard await ops.present(alert, window: window) == .alertFirstButtonReturn else { return }
            await ops.run("Delete", steps: targets.map { .delete($0) }, history: .none, window: window)
            refresh()
        }
    }

    private func putBack() {
        let targets = selectedURLs
        Task {
            _ = await ops.putBack(targets, window: window)
            refresh()
        }
    }

    private func undoOrRedo(undo: Bool) {
        Task {
            let results = undo ? await ops.undo(window: window) : await ops.redo(window: window)
            let here = results.filter { $0.deletingLastPathComponent().path == url.path }
            refresh(selecting: here)
        }
    }

    private func showProblem(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        Task { _ = await ops.present(alert, window: window) }
    }

    // MARK: Loading

    private func load(keepSelection: Bool = false) {
        loadTask?.cancel()
        isLoading = true
        let target = url
        watcher = DirectoryWatcher(url: target) { [weak self] in self?.refresh() }
        loadTask = Task {
            let result = await DirectoryLoader.list(target)
            guard !Task.isCancelled, target == url else { return }
            isLoading = false
            updateFreeSpace(target)
            switch result {
            case .success(let listing):
                allItems = listing
                errorMessage = nil
            case .failure(let error):
                allItems = []
                errorMessage =
                    isTrashFolder
                    ? "File Manager needs Full Disk Access to show the Trash. Turn it on in System Settings → Privacy & Security → Full Disk Access."
                    : error.localizedDescription
            }
            applyFilterAndSort()
            let present = Set(items.map(\.url))
            let wanted = pendingSelection.intersection(present)
            if !wanted.isEmpty {
                selection = wanted
                pendingSelection = []
            } else if keepSelection || !pendingSelection.isEmpty {
                // Keep what's still there (pending items may arrive with the next refresh).
                selection = selection.intersection(present)
            } else {
                selection = []
            }
            if let rename = pendingRename, present.contains(rename) {
                pendingRename = nil
                startRename(rename)
            }
        }
    }

    /// Free space can take a moment to work out (it counts purgeable space), so it's filled in
    /// after the listing rather than holding it up.
    private func updateFreeSpace(_ folder: URL) {
        freeSpaceTask?.cancel()
        freeSpaceTask = Task {
            let free = await Task.detached {
                try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage
            }.value
            if !Task.isCancelled, folder == url { freeSpace = free }
        }
    }

    private func applyFilterAndSort() {
        let visible = showHiddenFiles ? allItems : allItems.filter { !$0.isHidden }
        items = sort.sorted(visible)
        listingVersion += 1
    }

    /// Clears the one-shot reveal once the table has scrolled to it.
    func didReveal() { revealAfterLoad = nil }

    private func volumeName(of url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName
    }
}
