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
    /// Bumped whenever `items` is replaced, so the table knows to reload.
    private(set) var listingVersion = 0
    private(set) var history: NavigationHistory

    var selection: Set<URL> = []
    /// How this folder is shown (icons or details, sort, groups, zoom); remembered per folder.
    var view = FolderView() {
        didSet {
            guard view != oldValue else { return }
            if view.sort != oldValue.sort || view.groupBy != oldValue.groupBy { applyFilterAndSort() }
            if !restoringView { services.folderViews.remember(view, for: url.path) }
        }
    }
    /// The Settings choice, applied to every folder's sort.
    var foldersFirst = true { didSet { if foldersFirst != oldValue { applyFilterAndSort() } } }
    var sort: FileSort {
        FileSort(column: view.sortColumn, ascending: view.ascending, foldersFirst: foldersFirst)
    }
    /// What the list shows: group headings (when grouping) and items, in order.
    private(set) var rows: [ListRow] = []
    var showHiddenFiles = false {
        didSet {
            guard showHiddenFiles != oldValue else { return }
            if isSearchingSubfolders { search.restart() }
            applyFilterAndSort()
        }
    }

    /// The folder as read from disk; this model filters, sorts and selects in it.
    let listing = FolderListing()
    /// Find (Cmd+F).
    let search = SearchSession()
    /// Rename with several items selected opens the batch rename sheet.
    var batchRename: BatchRenameRequest?

    /// Address bar text while editing; reset to the current folder on navigation or cancel.
    var addressText = ""
    /// Scrolled to after the next load (the folder you came up from, a pasted item).
    private(set) var revealAfterLoad: URL?
    /// Requests to this pane's views and window (focus, rename, Quick Look, new windows…).
    private(set) var commands = CommandLog<PaneCommand>()

    /// The window this model lives in, for tabs, focus moves and alerts. Set by `KeyMonitor`.
    var window: NSWindow? {
        get { controls.window }
        set { controls.window = newValue }
    }
    private let controls: WindowControls
    private let presenter: any BrowserPresenter

    // MARK: Split view
    /// The window's main pane, when this is the right-hand pane of a split view.
    var hostID: UUID?
    /// The other pane while the window is split (F3).
    weak var otherPane: BrowserModel?
    /// Called when this pane's file list takes the keyboard focus (it becomes the active pane).
    var onFocused: (() -> Void)?
    /// Tabs and windows opened from this pane belong to the window's main pane.
    var windowID: UUID { hostID ?? id }

    let home = FileManager.default.homeDirectoryForCurrentUser
    /// Selected once the next load shows them (new, pasted or renamed items).
    private var pendingSelection: Set<URL> = []
    private var pendingRename: URL?
    private var started = false
    private var lastSelectPattern = ""
    private var restoringView = false
    @ObservationIgnored private var tagsObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var downloadCheck: Task<Void, Never>?
    /// The window or pane closed; nothing more is loaded.
    private var stopped = false

    private let services: BrowserServices

    /// Cheap: SwiftUI may create throwaway models. Nothing is read until `start()`.
    /// `presenter` defaults to alerts on the model's window.
    init(
        start: URL? = nil, id: UUID = UUID(), services: BrowserServices = .live,
        presenter: (any BrowserPresenter)? = nil
    ) {
        self.id = id
        self.services = services
        let start = (start ?? StartFolder.url(services.preferences)).canonical
        url = start
        history = NavigationHistory(start: start)
        addressText = PathInput.display(start, home: home)
        let controls = WindowControls()
        self.controls = controls
        self.presenter = presenter ?? AlertPresenter(controls: controls, operations: services.operations)
        search.context = { [weak self] in
            SearchSession.Context(
                root: self?.url ?? start, showHidden: self?.showHiddenFiles ?? false,
                showAllExtensions: services.preferences.showAllExtensions)
        }
        search.onUpdate = { [weak self] found in self?.searchUpdated(found) }
    }

    isolated deinit {
        if let tagsObserver { NotificationCenter.default.removeObserver(tagsObserver) }
    }

    /// The window or split pane closed: stop loading, watching and searching. File operations
    /// already started carry on. A window's main pane also stops its split pane.
    func stop() {
        stopped = true
        listing.stop()
        search.close()
        downloadCheck?.cancel()
        if hostID == nil { otherPane?.stop() }
    }

    /// Loads the first folder. Called once the window appears.
    func start() {
        guard !started else { return }
        started = true
        tagsObserver = NotificationCenter.default.addObserver(of: services.operations, for: TagsChanged.self) {
            [weak self] message in self?.tagsChanged(message.tags)
        }
        restoreView(for: url)
        services.sidebar.visited(url.path)
        load()
    }

    var title: String {
        url.isFileSystemRoot ? (volumeName(of: url) ?? "/") : FileManager.default.displayName(atPath: url.path)
    }

    // MARK: Navigation

    func navigate(to target: URL) {
        let target = target.canonical
        guard target != url else { return }
        history.visit(target)
        show(target)
    }

    func goBack() { if let target = history.goBack() { show(target) } }
    func goForward() { if let target = history.goForward() { show(target) } }

    func goUp() {
        guard !url.isFileSystemRoot else { return }
        navigate(to: url.deletingLastPathComponent())
    }

    func refresh() {
        if isSearchingSubfolders { search.restart() }
        load(keepSelection: true)
    }

    /// Reloads, then selects `urls` (and starts renaming `rename`) once they're listed.
    func refresh(selecting urls: [URL], rename: URL? = nil) {
        let urls = urls.map(\.normalized)
        pendingSelection = Set(urls)
        pendingRename = rename?.normalized
        revealAfterLoad = urls.first
        if isSearchingSubfolders { search.restart() }
        load()
    }

    private func show(_ target: URL) {
        let previous = url
        url = target
        addressText = PathInput.display(target, home: home)
        selection = []
        search.close()
        restoreView(for: target)
        // Going up (or back to a parent) selects the folder you came from, like Explorer.
        let cameFromChild = previous.isDirectlyInside(target)
        revealAfterLoad = cameFromChild ? previous.normalized : nil
        pendingSelection = cameFromChild ? [previous.normalized] : []
        pendingRename = nil
        services.sidebar.visited(target.path)
        services.windows.scheduleSave()
        load()
        // The new folder's listing is empty until read: Select All and Delete can't reach the
        // folder just left.
        applyFilterAndSort()
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

    func focusAddressBar() { send(.focusAddressBar) }
    func focusList() { send(.focusList) }

    func send(_ command: PaneCommand) { commands.send(command) }

    /// The file list or icon view's commands since it last looked. The place it got to is kept
    /// here, not in the view, so a view that replaces the other (icons ↔ details) still gets
    /// what was sent while it was being made, such as the focus.
    func takeFileViewCommands() -> [PaneCommand] {
        defer { fileViewSeenCommand = commands.last }
        return commands.commands(after: fileViewSeenCommand)
    }
    @ObservationIgnored private var fileViewSeenCommand = 0

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
            presenter.beep()
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
        if let completed { addressText = completed } else { presenter.beep() }
    }

    // MARK: Actions

    /// The Trash, or a volume's .Trashes folder.
    var isTrashFolder: Bool {
        url.isTrashFolder(home: home)
    }

    /// Selected items in list order.
    var selectedURLs: [URL] { selectedItems.map(\.url) }
    var selectedItems: [FileItem] { items.filter { selection.contains($0.url) } }

    /// See `Action.isAvailable(in:)`.
    func canPerform(_ action: Action) -> Bool { action.isAvailable(in: self) }

    func perform(_ action: Action) {
        guard canPerform(action) else {
            presenter.beep()
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
        case .newTab: requestOpen(WindowSpec(path: url.path, tabParent: windowID, select: true))
        case .openInNewTab: openInNewTabs(items.filter { selection.contains($0.url) && $0.isFolder }.map(\.url))
        case .reopenClosedTab:
            if let path = services.windows.popClosedTab() {
                requestOpen(WindowSpec(path: path, tabParent: windowID, select: true))
            }
        // The Ctrl+Tab keys themselves are left to macOS (see `Action.isHandledByMacOS`).
        case .nextTab: controls.showTab(offset: 1)
        case .previousTab: controls.showTab(offset: -1)
        case .showTab1, .showTab2, .showTab3, .showTab4, .showTab5, .showTab6, .showTab7, .showTab8, .showTab9:
            controls.showTab(at: action == .showTab9 ? controls.tabCount - 1 : (action.tabNumber ?? 1) - 1)
        case .addToSidebar:
            let folders = items.filter { selection.contains($0.url) && $0.isFolder }.map(\.url.path)
            services.sidebar.pin(folders.isEmpty ? [url.path] : folders)
        case .refresh: refresh()
        case .toggleHiddenFiles: showHiddenFiles.toggle()
        case .viewAsIcons: view.mode = .icons
        case .viewAsDetails: view.mode = .details
        case .zoomIn: if !view.zoom(in: true) { presenter.beep() }
        case .zoomOut: if !view.zoom(in: false) { presenter.beep() }
        case .actualSize: view.resetZoom()
        case .togglePreviewPane: services.preferences.showPreviewPane.toggle()
        case .openTerminal: TerminalLauncher.open(url)
        case .goTrash: navigate(to: home.appendingPathComponent(".Trash"))
        case .selectAll: selection = Set(items.map(\.url))
        case .invertSelection: selection = Selection.inverted(selection, in: items.map(\.url))
        case .selectByPattern: selectByPattern()
        case .compress: compress()
        case .toggleSplitView: send(.toggleSplit)
        case .connectToServer: send(.connectToServer)
        case .copyToOtherPane, .moveToOtherPane:
            if let other = otherPane { sendToOtherPane(other, move: action == .moveToOtherPane) }
        case .extract: extract()
        case .downloadNow: setDownloaded(true)
        case .removeDownload: setDownloaded(false)
        case .find: openSearch()
        case .endSearch: endSearch()
        case .copy: services.clipboard.copy(selectedURLs)
        case .cut: services.clipboard.cut(selectedURLs)
        case .copyPath:
            let paths = selection.isEmpty ? [url.path] : selectedURLs.map(\.path)
            services.clipboard.copyText(paths.joined(separator: "\n"))
        case .paste: paste(move: services.clipboard.isCut)
        case .pasteMove: paste(move: true)
        case .rename:
            if selection.count > 1 { startBatchRename() } else { startRename(selectedURLs[0]) }
        case .duplicate: duplicate()
        case .newFolder: create(folder: true)
        case .newTextFile: create(folder: false)
        case .moveToTrash: moveToTrash()
        case .deleteImmediately: deleteImmediately()
        case .putBack: putBack()
        case .undo: undoOrRedo(undo: true)
        case .redo: undoOrRedo(undo: false)
        case .getInfo:
            send(.getInfo(selection.isEmpty ? [url] : selectedURLs))
        case .quickLook: send(.quickLook)
        case .showContextMenu: send(.contextMenu)
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting(selection.isEmpty ? [url] : selectedURLs)
        }
    }

    /// Files dropped on the list, a folder in it, or the sidebar.
    func drop(_ sources: [URL], into folder: URL, operation: DropRules.Operation) {
        guard operation != .none else { return }
        Task {
            let results = await ops.transfer(sources, into: folder, mode: operation == .copy ? .copy : .move, window: window)
            if folder.isSameFile(as: url) { refresh(selecting: results) } else { refresh() }
        }
    }

    /// Total size of the selected files (folders aren't added up, as in Explorer's status bar).
    var selectionSize: Int64 {
        items.filter { selection.contains($0.url) && !$0.isFolder }.reduce(0) { $0 + ($1.size ?? 0) }
    }

    // MARK: Windows and tabs

    /// Asks the window to open a window or tab.
    func requestOpen(_ spec: WindowSpec) { send(.open(spec)) }

    /// Middle-click, Ctrl+Return or the menu: each folder in a tab of this window, in the
    /// background like a browser (this tab stays in front).
    func openInNewTabs(_ folders: [URL]) {
        for folder in folders { requestOpen(WindowSpec(path: folder.path, tabParent: windowID, select: false)) }
    }

    /// F6 / Shift+F6 (see `FocusCycle`).
    private func moveFocus(forward: Bool) {
        guard window != nil else { return }
        // This is the active pane (the one the keys go to); work out which side it is.
        let left = hostID == nil ? self : (otherPane ?? self)
        let right = hostID == nil ? otherPane : self
        let current: FocusCycle.Area? =
            switch controls.focus {
            case .fileList: right === self ? .rightList : .leftList
            case .textField: .addressBar
            case .other: nil
            }
        switch FocusCycle.next(from: current, forward: forward, isSplit: right != nil) {
        case .leftList: left.focusList()
        case .rightList: (right ?? left).focusList()
        case .addressBar: focusAddressBar()
        case .sidebar: if !controls.focusSidebar() { focusList() }
        }
    }

    /// Copy / Move to Other Pane: the selection goes into the folder the other pane shows.
    private func sendToOtherPane(_ other: BrowserModel, move: Bool) {
        let sources = selectedURLs
        let folder = other.url
        Task {
            let results = await ops.transfer(sources, into: folder, mode: move ? .move : .copy, window: window)
            other.refresh(selecting: results)
            refresh()
        }
    }

    // MARK: File operations

    private var ops: FileOperations { services.operations }

    private func paste(move: Bool) {
        let sources = services.clipboard.fileURLs
        let folder = url
        let wasCut = move && services.clipboard.isCut
        Task {
            let results = await ops.transfer(sources, into: folder, mode: move ? .move : .copy, window: window)
            if wasCut, !results.isEmpty { services.clipboard.finishCut() }
            if folder.isSameFile(as: url) { refresh(selecting: results) }
        }
    }

    private func duplicate() {
        let sources = selectedURLs
        let folder = url
        Task {
            let results = await ops.transfer(sources, into: folder, mode: .copy, window: window)
            if folder.isSameFile(as: url) { refresh(selecting: results) }
        }
    }

    /// New Folder / New Text File: makes it, selects it and starts renaming, like Explorer.
    private func create(folder isFolder: Bool) {
        let names = Set(listing.items.map(\.name) + listing.items.map(\.url.lastPathComponent))
        let base = isFolder ? FileNaming.newFolderName : FileNaming.newTextFileName
        let target = url.appendingPathComponent(FileNaming.unique(base, isFolder: isFolder, existing: names))
        let folder = url
        Task {
            let outcome = await ops.run(
                isFolder ? "New Folder" : "New Text File",
                steps: [isFolder ? .createFolder(target) : .createFile(target)], window: window)
            if outcome.error == nil, folder.isSameFile(as: url) { refresh(selecting: [target], rename: target) }
        }
    }

    func startRename(_ target: URL) {
        send(.rename(target))
    }

    /// Called by the list when editing ends. Returns false (and explains) if the name can't be used.
    func commitRename(_ item: URL, to newName: String) {
        let oldName = item.lastPathComponent
        guard newName != oldName, newName != FileManager.default.displayName(atPath: item.path) else { return }
        if let problem = FileNaming.problem(with: newName) {
            presenter.showProblem("Can't rename “\(oldName)”", detail: problem)
            return
        }
        let target = item.deletingLastPathComponent().appendingPathComponent(newName)
        // A change of case finds the item itself on a case-insensitive disk; on a case-sensitive
        // one the new name can be another item.
        if FileManager.default.fileExists(atPath: target.path), !target.isSameItem(as: item) {
            presenter.showProblem("Can't rename “\(oldName)”", detail: "There's already an item named “\(newName)” here.")
            return
        }
        Task {
            let outcome = await ops.run("Rename", steps: [.move(item, to: target)], window: window)
            if outcome.error == nil { refresh(selecting: [target]) }
        }
    }

    private func moveToTrash() {
        let targets = selectedURLs
        if services.preferences.confirmTrash {
            let title =
                targets.count == 1
                ? "Move “\(targets[0].lastPathComponent)” to the Trash?" : "Move \(targets.count) items to the Trash?"
            Task {
                guard await presenter.confirm(
                    title, detail: "You can undo this, or put them back from the Trash.", button: "Move to Trash",
                    destructive: false)
                else { return }
                trash(targets)
            }
            return
        }
        trash(targets)
    }

    private func trash(_ targets: [URL]) {
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
        let title =
            targets.count == 1
            ? "Delete “\(targets[0].lastPathComponent)” immediately?"
            : "Delete \(targets.count) items immediately?"
        Task {
            guard await presenter.confirm(
                title, detail: "They won't go to the Trash, and you can't undo this.", button: "Delete", destructive: true)
            else { return }
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
            let here = results.filter { $0.isDirectlyInside(url) }
            refresh(selecting: here)
        }
    }

    // MARK: Loading

    private func load(keepSelection: Bool = false) {
        guard !stopped else { return }
        listing.load(url, showAllExtensions: services.preferences.showAllExtensions, changed: { [weak self] in self?.refresh() }) { [weak self] in
            self?.listed(keepSelection: keepSelection)
        }
    }

    /// The listing is in: show it, and select what was waiting for it.
    private func listed(keepSelection: Bool) {
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

    var isLoading: Bool { listing.isLoading }
    var freeSpace: Int64? { listing.freeSpace }
    var errorMessage: String? {
        listing.error.map { error in
            isTrashFolder
                ? "File Manager needs Full Disk Access to show the Trash. Turn it on in System Settings → Privacy & Security → Full Disk Access."
                : error.localizedDescription
        }
    }

    private func applyFilterAndSort() {
        let source = isSearchingSubfolders ? search.results : listing.items
        var visible = showHiddenFiles ? source : source.filter { !$0.isHidden }
        if isSearchOpen { visible = criteria.filter(visible) }
        rows = Grouping.rows(sort.sorted(visible), by: view.groupBy)
        items = rows.compactMap(\.item)
        listingVersion += 1
        // Nothing hidden by a filter stays selected (it would be trashed unseen).
        let shown = Set(items.map(\.url))
        if !selection.isSubset(of: shown) { selection.formIntersection(shown) }
    }

    // MARK: Find

    typealias SearchScope = SearchSession.Scope

    var isSearchOpen: Bool { search.isOpen }
    var criteria: SearchCriteria {
        get { search.criteria }
        set { search.criteria = newValue }
    }
    var searchScope: SearchScope {
        get { search.scope }
        set { search.scope = newValue }
    }
    var isSearching: Bool { search.isSearching }
    var searchHitLimit: Bool { search.hitLimit }
    var isSearchingSubfolders: Bool { search.isSearchingSubfolders }
    var isFiltering: Bool { search.isFiltering }
    /// Tags used in this folder, for the find bar's Tag filter.
    var folderTags: [String] { Array(Set(listing.items.flatMap(\.tags))) }
    /// Items in the folder itself, before any filter (for "3 of 40 items").
    var folderItemCount: Int {
        showHiddenFiles ? listing.items.count : listing.items.count(where: { !$0.isHidden })
    }

    func openSearch() {
        search.open()
        send(.focusSearch)
    }

    /// Esc or the bar's close button: back to the whole folder.
    func endSearch() {
        guard search.isOpen else { return }
        search.close()
        applyFilterAndSort()
        focusList()
    }

    private func searchUpdated(_ found: [FileItem]) {
        applyFilterAndSort()
        // Renamed or pasted items show up here rather than in the folder's listing.
        let wanted = pendingSelection.intersection(found.map(\.url))
        if !wanted.isEmpty {
            selection.formUnion(wanted)
            pendingSelection.subtract(wanted)
        }
    }

    /// Down arrow or Return in the find field: on to the results.
    func focusResults() {
        if selection.isEmpty, let first = items.first { selection = [first.url] }
        focusList()
    }

    // MARK: Selecting

    /// Select by Pattern (Cmd+S): "*.jpg" selects every JPEG, like Total Commander's Num+.
    private func selectByPattern() {
        Task {
            guard let (text, adding) = await presenter.askForPattern(initial: lastSelectPattern) else { return }
            lastSelectPattern = text
            let pattern = NamePattern(text)
            let matching = Set(items.filter { pattern.matches($0.name) }.map(\.url))
            if matching.isEmpty { presenter.beep() }
            selection = adding ? selection.union(matching) : matching
            if let first = items.first(where: { matching.contains($0.url) }) { revealAfterLoad = first.url }
            focusList()
        }
    }

    // MARK: Archives, tags, iCloud

    /// Compress: one item gives "name.zip", several give "Archive.zip", next to them.
    private func compress() {
        let sources = selectedURLs
        guard let folder = sources.first?.deletingLastPathComponent() else { return }
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let archive = folder.appendingPathComponent(
            Archive.archiveName(for: sources.map(\.lastPathComponent), existing: existing))
        Task {
            let outcome = await ops.run("Compress", steps: [.compress(sources, to: archive)], window: window)
            if outcome.error == nil { refresh(selecting: [archive]) }
        }
    }

    /// Extract: each selected zip opens next to itself.
    private func extract() {
        let archives = selectedURLs.filter(Archive.isArchive)
        let steps: [FileStep] = archives.map {
            .extract($0, suggested: $0.deletingLastPathComponent().appendingPathComponent(Archive.folderName(for: $0.lastPathComponent)))
        }
        Task {
            let outcome = await ops.run("Extract", steps: steps, window: window)
            refresh(selecting: outcome.executed.compactMap(\.resultURL))
        }
    }

    /// Adds or removes a Finder tag on the selection, as one undoable change.
    func toggleTag(_ tag: String) {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        // Like Finder: if every item has it, take it off; otherwise put it on all of them.
        let remove = chosen.allSatisfy { $0.tags.contains(tag) }
        let steps: [FileStep] = chosen.map { item in
            .setTags(item.url, remove ? item.tags.filter { $0 != tag } : item.tags.contains(tag) ? item.tags : item.tags + [tag])
        }
        Task {
            await ops.run(remove ? "Remove Tag “\(tag)”" : "Tag “\(tag)”", steps: steps, window: window)
            refresh(selecting: chosen.map(\.url))
        }
    }

    /// Tags changed by a file operation (in any window), keyed by path.
    private func tagsChanged(_ tags: [String: [String]]) {
        let inFolder = listing.updateTags(tags)
        let inResults = search.updateTags(tags)
        if inFolder || inResults { applyFilterAndSort() }
    }

    /// Download Now / Remove Download for iCloud Drive items. Only their local copy changes,
    /// so this isn't a file operation and can't be undone.
    private func setDownloaded(_ download: Bool) {
        let fm = FileManager.default
        for item in selectedItems where item.cloud != nil {
            do {
                if download {
                    try fm.startDownloadingUbiquitousItem(at: item.url)
                } else {
                    try fm.evictUbiquitousItem(at: item.url)
                }
            } catch {
                presenter.showError(error, title: "Can't change “\(item.name)”")
                return
            }
        }
        // The folder doesn't change, so its watcher won't notice; check back a few times.
        downloadCheck?.cancel()
        downloadCheck = Task { [weak self] in
            for delay in [1, 3, 8] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    // MARK: Batch rename

    private func startBatchRename() {
        let chosen = items.filter { selection.contains($0.url) }
        batchRename = BatchRenameRequest(items: chosen.map { BatchRename.Item(url: $0.url, isFolder: $0.isFolder) })
    }

    /// Runs a batch rename as one job, so a single Undo puts every name back.
    func commitBatchRename(_ entries: [BatchRename.Entry]) {
        let moves = BatchRename.moves(entries)
        let targets = entries.filter(\.isChanged).map(\.target)
        let title = "Rename \(targets.count) items"
        Task {
            let outcome = await ops.run(title, steps: moves.map { .move($0.from, to: $0.to) }, window: window)
            if outcome.error == nil { refresh(selecting: targets) } else { refresh() }
        }
    }

    /// The folder's remembered view, or the default for folders not set up yet.
    private func restoreView(for folder: URL) {
        restoringView = true
        view = services.folderViews.view(for: folder.path)
        restoringView = false
    }

    /// Clears the one-shot reveal once the table has scrolled to it.
    func didReveal() { revealAfterLoad = nil }

    private func volumeName(of url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName
    }
}

extension BrowserModel: @MainActor ActionState {
    var hasSelection: Bool { !selection.isEmpty }
    var hasItems: Bool { !items.isEmpty }
    var canReadFolder: Bool { listing.error == nil }
    var isAtRoot: Bool { url.isFileSystemRoot }
    var hasOtherPane: Bool { otherPane != nil }
    var tabCount: Int { controls.tabCount }
    var hasClosedTabs: Bool { services.windows.hasClosedTabs }
    var clipboardHasFiles: Bool { services.clipboard.hasFiles }
    var canUndo: Bool { ops.canUndo }
    var canRedo: Bool { ops.canRedo }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
}

struct BatchRenameRequest: Identifiable {
    let id = UUID()
    var items: [BatchRename.Item]
}
