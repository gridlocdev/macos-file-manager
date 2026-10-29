import Foundation
import FileManagerCore

/// Reads a folder off the main thread.
enum DirectoryLoader {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
        .creationDateKey, .addedToDirectoryDateKey, .fileSecurityKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadingKey,
    ]

    /// `showAllExtensions`: the Settings choice (see `name`).
    static func list(_ folder: URL, showAllExtensions: Bool) async -> Result<[FileItem], Error> {
        await Task.detached(priority: .userInitiated) {
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: keys, options: [])
                // Under the folder's path as opened, not the real one if it's through a symlink.
                return .success(urls.map {
                    item($0, showAllExtensions: showAllExtensions, shownAs: folder.appending(path: $0.lastPathComponent))
                })
            } catch {
                return .failure(error)
            }
        }.value
    }

    /// `shownAs`: the URL the item is listed under, if not `url` (see `URL.replacingFolder`).
    static func item(_ url: URL, showAllExtensions: Bool, shownAs: URL? = nil) -> FileItem {
        let values = try? url.resourceValues(forKeys: Set(keys))
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
            name: name(url, isFolder: isFolder, showAllExtensions: showAllExtensions),
            isFolder: isFolder,
            isHidden: values?.isHidden ?? url.lastPathComponent.hasPrefix("."),
            size: isFolder ? nil : values?.fileSize.map(Int64.init),
            modified: values?.contentModificationDate,
            kind: values?.localizedTypeDescription ?? "",
            created: values?.creationDate,
            added: values?.addedToDirectoryDate,
            permissions: permissions
        )
        // Tags come from an extended attribute that the listing's prefetch can hand back stale
        // just after they change (a tag set a moment ago would vanish), so read them afresh.
        var tagURL = url
        tagURL.removeCachedResourceValue(forKey: .tagNamesKey)
        item.tags = (try? tagURL.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
        if values?.isUbiquitousItem == true {
            item.cloud =
                values?.ubiquitousItemIsDownloading == true ? .downloading
                : values?.ubiquitousItemIsUploading == true ? .uploading
                : values?.ubiquitousItemDownloadingStatus == .current ? .current
                : .notDownloaded
        }
        return item
    }

    /// With "Show all file extensions" on (the default), the real name ("notes.txt"); apps
    /// still drop ".app", as everywhere on a Mac. Off, Finder's choice for each file.
    private static func name(_ url: URL, isFolder: Bool, showAllExtensions: Bool) -> String {
        let display = FileManager.default.displayName(atPath: url.path)
        guard showAllExtensions, !isFolder,
            url.pathExtension.lowercased() != "app", !url.pathExtension.isEmpty
        else { return display }
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
