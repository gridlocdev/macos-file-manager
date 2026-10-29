import AppKit
import FileManagerCore
import Observation

/// One folder view: what's shown, history, selection. A window has one now; tabs (M4) and
/// split view (M8) will each get their own.
@MainActor @Observable
final class BrowserModel {
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
    /// Selected and scrolled to after the next load (the folder you came up from).
    private(set) var revealAfterLoad: URL?

    /// The window this model lives in, for focus moves. Set by `KeyMonitor`.
    weak var window: NSWindow?

    let home = FileManager.default.homeDirectoryForCurrentUser
    private var allItems: [FileItem] = []
    private var loadTask: Task<Void, Never>?
    private var watcher: DirectoryWatcher?

    init(start: URL? = nil) {
        let start = start ?? FileManager.default.homeDirectoryForCurrentUser
        url = start
        history = NavigationHistory(start: start)
        addressText = PathInput.display(start, home: home)
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

    private func show(_ target: URL) {
        let previous = url
        url = target
        addressText = PathInput.display(target, home: home)
        selection = []
        // Going up (or back to a parent) selects the folder you came from, like Explorer.
        revealAfterLoad = previous.deletingLastPathComponent().standardizedFileURL == target ? previous : nil
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
                revealAfterLoad = target
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

    func canPerform(_ action: Action) -> Bool {
        switch action {
        case .open: !selection.isEmpty
        case .goBack: history.canGoBack
        case .goForward: history.canGoForward
        case .goUp: url.path != "/"
        default: true
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
        case .focusNextArea: window?.selectNextKeyView(nil)
        case .focusPreviousArea: window?.selectPreviousKeyView(nil)
        case .refresh: refresh()
        case .toggleHiddenFiles: showHiddenFiles.toggle()
        case .openTerminal: TerminalLauncher.open(url)
        }
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
            switch result {
            case .success(let listing):
                allItems = listing
                errorMessage = nil
            case .failure(let error):
                allItems = []
                errorMessage = error.localizedDescription
            }
            applyFilterAndSort()
            let present = Set(items.map(\.url))
            if keepSelection {
                selection = selection.intersection(present)
            } else if let reveal = revealAfterLoad, present.contains(reveal) {
                selection = [reveal]
            }
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
