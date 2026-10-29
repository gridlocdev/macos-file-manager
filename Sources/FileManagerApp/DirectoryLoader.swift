import Foundation
import FileManagerCore

/// Reads a folder off the main thread.
enum DirectoryLoader {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
    ]

    static func list(_ folder: URL) async -> Result<[FileItem], Error> {
        await Task.detached(priority: .userInitiated) {
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: keys, options: [])
                return .success(urls.map(item))
            } catch {
                return .failure(error)
            }
        }.value
    }

    private static func item(_ url: URL) -> FileItem {
        let values = try? url.resourceValues(forKeys: Set(keys))
        var isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        // A symlink to a folder opens like a folder.
        if values?.isSymbolicLink == true {
            let target = url.resolvingSymlinksInPath()
            let targetValues = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            isFolder = (targetValues?.isDirectory ?? false) && !(targetValues?.isPackage ?? false)
        }
        return FileItem(
            url: url,
            name: FileManager.default.displayName(atPath: url.path),
            isFolder: isFolder,
            isHidden: values?.isHidden ?? url.lastPathComponent.hasPrefix("."),
            size: isFolder ? nil : values?.fileSize.map(Int64.init),
            modified: values?.contentModificationDate,
            kind: values?.localizedTypeDescription ?? ""
        )
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
