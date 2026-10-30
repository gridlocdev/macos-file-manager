import Foundation
import FileManagerCore
import Observation

/// A folder's contents as read from disk: the items, whether they're still loading or couldn't
/// be read, and the disk's free space. Watches the folder for changes. Knows nothing about
/// filters, sorting or selection (`BrowserModel` does that).
@MainActor @Observable
final class FolderListing {
    private(set) var items: [FileItem] = []
    private(set) var error: Error?
    private(set) var isLoading = false
    /// Free space on the folder's disk, for the status bar.
    private(set) var freeSpace: Int64?

    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var freeSpaceTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: DirectoryWatcher?

    /// Reads `folder`, replacing any load still running, then calls `loaded`. `changed` is called
    /// whenever the folder changes on disk afterwards.
    func load(
        _ folder: URL, showAllExtensions: Bool, changed: @escaping @MainActor () -> Void,
        loaded: @escaping @MainActor () -> Void
    ) {
        loadTask?.cancel()
        if folder != self.folder {
            // Another folder: the last one's items mustn't stay up (or be acted on) meanwhile.
            items = []
            error = nil
            watcher = nil
        }
        self.folder = folder
        isLoading = true
        // A refresh keeps watching with the watcher it has (opening one can stall on a network
        // share). A change reported late, after moving on or stopping, is dropped.
        if watcher == nil {
            watcher = DirectoryWatcher(url: folder) { [weak self] in
                if let self, self.folder == folder, watcher != nil { changed() }
            }
        }
        loadTask = Task {
            let result = await DirectoryLoader.list(folder, showAllExtensions: showAllExtensions)
            guard !Task.isCancelled else { return }
            isLoading = false
            updateFreeSpace(folder)
            switch result {
            case .success(let listing):
                items = listing
                error = nil
            case .failure(let failure):
                items = []
                error = failure
            }
            loaded()
        }
    }

    /// Stops loading and watching.
    func stop() {
        loadTask?.cancel()
        freeSpaceTask?.cancel()
        watcher = nil
    }

    /// Applies tags changed by a file operation. Returns true if any item here changed.
    func updateTags(_ tags: [String: [String]]) -> Bool { items.updateTags(tags) }

    /// Free space can take a moment to work out (it counts purgeable space), so it's filled in
    /// after the listing rather than holding it up.
    private func updateFreeSpace(_ folder: URL) {
        freeSpaceTask?.cancel()
        freeSpaceTask = Task {
            let free = await Task.detached { () -> Int64? in
                let values = try? folder.resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                // Network shares report 0 for the "important usage" figure (it counts purgeable
                // space on local disks only); their plain free space is right.
                if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
                return values?.volumeAvailableCapacity.map(Int64.init)
            }.value
            if !Task.isCancelled, folder == self.folder { freeSpace = free }
        }
    }
}

extension [FileItem] {
    /// Sets the tags of items whose path is in `tags`. Returns true if any changed.
    mutating func updateTags(_ tags: [String: [String]]) -> Bool {
        var changed = false
        for i in indices {
            if let new = tags[self[i].url.path], new != self[i].tags {
                self[i].tags = new
                changed = true
            }
        }
        return changed
    }
}
