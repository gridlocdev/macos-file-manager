import CoreServices
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
                if folder.realPath.isSameFile(as: ICloudDrive.folder(home: home).realPath) {
                    for i in items.indices where ICloudDrive.isSyncedHomeFolder(items[i].url, home: home) {
                        items[i].isHidden = false
                    }
                    for url in ICloudDrive.appFolders(home: home) {
                        if Task.isCancelled { return .failure(CancellationError()) }
                        items.append(item(url, showAllExtensions: showAllExtensions))
                    }
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
        let guarded = url.isGuardedFolder(home: home) || ICloudDrive.isSyncedHomeFolder(url, home: home)
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

/// What Finder shows in iCloud Drive beyond the folder's own contents on disk.
enum ICloudDrive {
    static func folder(home: URL) -> URL { home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs") }

    /// Desktop and Documents, when they're kept in iCloud: links in iCloud Drive to the real
    /// folders in Home, marked hidden on disk but shown by Finder. Treated like the folders
    /// they point to (asked only the basics, so listing iCloud Drive brings up no prompt).
    static func isSyncedHomeFolder(_ url: URL, home: URL) -> Bool {
        guard url.isDirectlyInside(folder(home: home)), ["Desktop", "Documents"].contains(url.lastPathComponent),
            (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        else { return false }
        return url.resolvingSymlinksInPath().isGuardedFolder(home: home)
    }

    /// Apps' own iCloud folders (Numbers, TextEdit, Shortcuts…), which Finder lists in iCloud
    /// Drive under the app's name: the Documents folder of each container next to iCloud
    /// Drive's. iCloud marks hidden the containers Finder leaves out (apps' private data, and an
    /// app's folder while it's empty).
    static func appFolders(home: URL) -> [URL] {
        let containers = home.appending(path: "Library/Mobile Documents")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: containers, includingPropertiesForKeys: [.isHiddenKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.lastPathComponent != "com~apple~CloudDocs" }
            .map { containers.appending(path: $0.lastPathComponent + "/Documents") }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.normalized)
    }

    /// What's in iCloud Drive for lists of folders only (the sidebar's tree, the breadcrumbs'
    /// menus): the links to Desktop and Documents and the apps' folders.
    static func extraFolders(in folder: URL, home: URL) -> [URL] {
        guard folder.realPath.isSameFile(as: self.folder(home: home).realPath) else { return [] }
        let links = ["Desktop", "Documents"].map { folder.appending(path: $0).normalized }
            .filter { isSyncedHomeFolder($0, home: home) }
        return links + appFolders(home: home)
    }

    /// `subfolders` of `folder` (normalized), with `extraFolders` added in iCloud Drive, sorted
    /// by name: an app's folder by the app's name (they're all called "Documents" on disk).
    static func sortedFolders(_ subfolders: [URL], in folder: URL, home: URL) -> [URL] {
        let extras = extraFolders(in: folder, home: home)
        // The links are in iCloud Drive itself; the apps' folders aren't.
        let apps = extras.filter { !$0.isDirectlyInside(folder) }
        let folders = subfolders.filter { folder in !extras.contains { $0.isSameFile(as: folder) } } + extras
        return folders
            .map { url in (url, apps.contains(url) ? FileManager.default.displayName(atPath: url.path) : url.lastPathComponent) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
            .map(\.0)
    }

    @MainActor private static var appNames: [String: String] = [:]

    /// An app's name from its iCloud container's folder name ("com~apple~Numbers" → "Numbers"),
    /// as the system names the container's Documents folder. Asked once per container.
    @MainActor static func appName(container: String) -> String? {
        guard container != "com~apple~CloudDocs" else { return nil }
        if let name = appNames[container] { return name }
        let documents = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/\(container)/Documents")
        guard FileManager.default.fileExists(atPath: documents.path) else { return nil }
        let name = FileManager.default.displayName(atPath: documents.path)
        appNames[container] = name
        return name
    }

    /// The app's name for an app's folder (an `appFolders` URL), nil for any other folder.
    @MainActor static func appName(folder url: URL) -> String? {
        let containers = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Mobile Documents")
        let container = url.deletingLastPathComponent()
        guard url.lastPathComponent == "Documents", container.isDirectlyInside(containers) else { return nil }
        return appName(container: container.lastPathComponent)
    }

    /// Calls `onChange` (on the main actor, debounced) when an app's folder may have come or
    /// gone: a container in Mobile Documents added, removed, or shown or hidden by iCloud (a
    /// flag on the container, which the folder's own watcher doesn't see). One FSEvents stream
    /// over Mobile Documents; changes deeper down (apps syncing their data) are ignored.
    @MainActor final class AppFoldersWatcher {
        private nonisolated(unsafe) var stream: FSEventStreamRef?
        private let containers: String
        private let onChange: @MainActor () -> Void
        private let debounce = Debouncer()

        init(home: URL, onChange: @escaping @MainActor () -> Void) {
            containers = home.appending(path: "Library/Mobile Documents").realPath.path
            self.onChange = onChange
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
                guard let info else { return }
                let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                MainActor.assumeIsolated {
                    Unmanaged<AppFoldersWatcher>.fromOpaque(info).takeUnretainedValue().changed(paths.prefix(count))
                }
            }
            guard
                let stream = FSEventStreamCreate(
                    nil, callback, &context, [containers] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    0.3, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
            else { return }
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
            self.stream = stream
        }

        private func changed(_ paths: ArraySlice<String>) {
            let containers = URL(filePath: containers)
            let relevant = paths.contains {
                let url = URL(filePath: $0)
                return url.isDirectlyInside(containers) && url.lastPathComponent != "com~apple~CloudDocs"
            }
            if relevant { debounce.schedule(onChange) }
        }

        deinit {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
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
