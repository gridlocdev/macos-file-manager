import Foundation
import FileManagerCore
import Observation

/// Find (Cmd+F) for one pane: whether the bar is open, what it looks for and where, and the
/// results of a subfolder search. Filtering the folder's own listing is left to `BrowserModel`.
@MainActor @Observable
final class SearchSession {
    enum Scope: Hashable { case folder, subfolders }

    private(set) var isOpen = false
    var criteria = SearchCriteria() { didSet { if criteria != oldValue { changed() } } }
    var scope = Scope.folder { didSet { if scope != oldValue { changed() } } }
    /// A subfolder search is still finding things.
    private(set) var isSearching = false
    private(set) var hitLimit = false
    /// What a subfolder search has found so far.
    private(set) var results: [FileItem] = []

    /// Where a subfolder search starts, and whether it includes hidden files.
    @ObservationIgnored var context: () -> (root: URL, showHidden: Bool) = { (URL(filePath: "/"), false) }
    /// Called when what the list should show changes: the criteria, or results came in (`found`,
    /// empty when results were dropped).
    @ObservationIgnored var onUpdate: (_ found: [FileItem]) -> Void = { _ in }

    /// The last search's results stay up until the new one finds something, so refreshing or
    /// typing another letter doesn't blank the list.
    @ObservationIgnored private var resultsAreStale = false
    @ObservationIgnored private var folderSearch: FolderSearch?
    @ObservationIgnored private var delay: Task<Void, Never>?

    /// Results come from the whole tree under the folder rather than its listing.
    var isSearchingSubfolders: Bool { isOpen && scope == .subfolders && !criteria.isEmpty }
    /// The list shows only matching items.
    var isFiltering: Bool { isOpen && !criteria.isEmpty }

    func open() {
        isOpen = true
    }

    /// Closes the bar and forgets the criteria.
    func close() {
        guard isOpen else { return }
        isOpen = false
        criteria = SearchCriteria()
        stop()
    }

    /// Starts the subfolder search again (the folder changed, or hidden files were toggled).
    func restart() {
        stop(keepingResults: true)
        resultsAreStale = true
        isSearching = true
        let (root, showHidden) = context()
        let search = FolderSearch(
            root: root, criteria: criteria, showHidden: showHidden,
            onResults: { [weak self] found in self?.add(found) },
            onFinish: { [weak self] in
                guard let self else { return }
                isSearching = false
                hitLimit = folderSearch?.hitLimit ?? false
                if resultsAreStale {
                    resultsAreStale = false
                    results = []
                    onUpdate([])
                }
            })
        folderSearch = search
        search.start()
    }

    /// Applies tags changed by a file operation. Returns true if any result changed.
    func updateTags(_ tags: [String: [String]]) -> Bool { results.updateTags(tags) }

    private func changed() {
        if isSearchingSubfolders {
            // Wait for a pause in typing before walking a whole tree.
            delay?.cancel()
            delay = Task {
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { restart() }
            }
        } else {
            stop()
        }
        onUpdate([])
    }

    private func stop(keepingResults: Bool = false) {
        if !keepingResults { delay?.cancel() }
        folderSearch?.cancel()
        folderSearch = nil
        if !keepingResults { results = [] }
        isSearching = false
        hitLimit = false
    }

    private func add(_ found: [FileItem]) {
        if resultsAreStale {
            resultsAreStale = false
            results = []
        }
        results += found
        onUpdate(found)
    }
}
