import Foundation
import FileManagerCore

/// Reads a folder off the main thread.
enum DirectoryLoader {
    /// What's asked of Desktop, Documents and Downloads in Home (see `isGuardedFolder`).
    static let basicKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .fileSecurityKey,
    ]
    static let keys: [URLResourceKey] = basicKeys + [
        .localizedTypeDescriptionKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey, .ubiquitousItemIsUploadingKey,
    ]
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// `showAllExtensions`: the Settings choice (see `name`). Cancelling the calling task stops
    /// the read between items (a folder replaced by another, or read again, mid-way).
    static func list(_ folder: URL, showAllExtensions: Bool) async -> Result<[FileItem], Error> {
        let read = Task.detached(priority: .userInitiated) { () -> Result<[FileItem], Error> in
            do {
                // Home's prefetch would ask the guarded folders everything; the rest is read per item.
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: folder.isSameFile(as: home) ? basicKeys : keys, options: [])
                var items: [FileItem] = []
                items.reserveCapacity(urls.count)
                for url in urls {
                    if Task.isCancelled { return .failure(CancellationError()) }
                    // Under the folder's path as opened, not the real one if it's through a symlink.
                    items.append(
                        item(url, showAllExtensions: showAllExtensions, shownAs: folder.appending(path: url.lastPathComponent)))
                }
                return .success(items)
            } catch {
                return .failure(error)
            }
        }
        return await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
    }

    /// `shownAs`: the URL the item is listed under, if not `url` (see `URL.replacingFolder`).
    static func item(_ url: URL, showAllExtensions: Bool, shownAs: URL? = nil) -> FileItem {
        let guarded = url.isGuardedFolder(home: home)
        let values = try? url.resourceValues(forKeys: Set(guarded ? basicKeys : keys))
        var isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        // A symlink to a folder opens like a folder.
        if values?.isSymbolicLink == true {
            let target = url.resolvingSymlinksInPath()
            let targetValues = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            isFolder = (targetValues?.isDirectory ?? false) && !(targetValues?.isPackage ?? false)
        }
        var permissions: Int?
        if let security = values?.fileSecurity {
            var mode: mode_t = 0
            if CFFileSecurityGetMode(security as CFFileSecurity, &mode) { permissions = Int(mode & 0o7777) }
        }
        var item = FileItem(
            url: (shownAs ?? url).normalized,
            name: guarded ? url.lastPathComponent : name(url, isFolder: isFolder, showAllExtensions: showAllExtensions),
            isFolder: isFolder,
            isHidden: values?.isHidden ?? url.lastPathComponent.hasPrefix("."),
            size: isFolder ? nil : values?.fileSize.map(Int64.init),
            modified: values?.contentModificationDate,
            kind: guarded ? "Folder" : values?.localizedTypeDescription ?? "",
            created: values?.creationDate,
            added: values?.addedToDirectoryDate,
            permissions: permissions
        )
        // Tags come from an extended attribute that the listing's prefetch can hand back stale
        // just after they change (a tag set a moment ago would vanish), so read them afresh.
        // Not for Desktop, Documents and Downloads: reading their tags is what brings up the
        // folder-access prompt (checked with a fresh app), just for listing Home.
        if !guarded {
            var tagURL = url
            tagURL.removeCachedResourceValue(forKey: .tagNamesKey)
            item.tags = (try? tagURL.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
        }
        item.cloud = values.flatMap(cloudStatus)
        return item
    }

    /// The iCloud state read afresh (the URL's cached values would hand back the old one).
    static func cloudStatus(of url: URL) -> CloudStatus? {
        var url = url
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: Set(keys))).flatMap(cloudStatus)
    }

    private static func cloudStatus(_ values: URLResourceValues) -> CloudStatus? {
        guard values.isUbiquitousItem == true else { return nil }
        return values.ubiquitousItemIsDownloading == true ? .downloading
            : values.ubiquitousItemIsUploading == true ? .uploading
            : values.ubiquitousItemDownloadingStatus == .current ? .current
            : .notDownloaded
    }

    /// With "Show all file extensions" on (the default), the real name ("notes.txt"); apps
    /// still drop ".app", as everywhere on a Mac. Off, Finder's choice for each file.
    /// Finder's display name is a LaunchServices lookup, so it's only asked for when needed.
    private static func name(_ url: URL, isFolder: Bool, showAllExtensions: Bool) -> String {
        guard showAllExtensions, !isFolder,
            url.pathExtension.lowercased() != "app", !url.pathExtension.isEmpty
        else { return FileManager.default.displayName(atPath: url.path) }
        return url.lastPathComponent
    }
}

/// Calls `onChange` (on the main actor, debounced) when entries are added, removed or renamed
/// in a folder. Stops when released.
final class DirectoryWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            source = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        let debounce = Debouncer()
        source.setEventHandler {
            MainActor.assumeIsolated { debounce.schedule(onChange) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit { source?.cancel() }
}

@MainActor private final class Debouncer {
    private var task: Task<Void, Never>?

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
