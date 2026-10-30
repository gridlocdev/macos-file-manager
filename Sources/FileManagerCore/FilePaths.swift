import Foundation

/// How the app tells whether two URLs are the same file or folder. Compare with these rather
/// than `URL ==` (which a trailing "/" breaks) or `.path` strings.
extension URL {
    /// The same file URL without a trailing "/", so a folder compares equal however its URL
    /// was made (listings add the slash, appendingPathComponent may not). Cheap: it doesn't
    /// touch the disk, so listings use it for every item. Selection relies on it.
    public var normalized: URL { URL(filePath: path, directoryHint: .notDirectory) }

    /// A folder or file to show or remember: ".." and "." resolved, "/private/tmp" as "/tmp",
    /// no trailing "/". For where the user navigates, not for every listed item.
    public var canonical: URL { standardizedFileURL.normalized }

    /// Same file or folder as `other`, ignoring a trailing "/".
    public func isSameFile(as other: URL) -> Bool { path == other.path }

    /// The same item on disk as `other`, however each is spelled: through a symlinked folder
    /// ("/Users/me/link/x"), or in other case on a case-insensitive disk ("/users/me"). Reads the
    /// disk (`isSameFile` doesn't); a last component that is a symlink is the link itself.
    public func isSameItem(as other: URL) -> Bool {
        if isSameFile(as: other) { return true }
        func identifier(_ url: URL) -> NSObject? {
            var url = url
            url.removeCachedResourceValue(forKey: .fileResourceIdentifierKey)
            return (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject
        }
        guard let mine = identifier(self), let theirs = identifier(other) else { return false }
        return mine.isEqual(theirs)
    }

    /// `folder` itself or somewhere inside it, by `isSameItem`: whether `folder` is this URL or
    /// one of the folders above it. Use on a `realPath`: a symlinked folder on the way up would
    /// otherwise be compared as the link.
    public func isItemOrInside(_ folder: URL, isSameItem: (URL, URL) -> Bool) -> Bool {
        var current = self.normalized
        while true {
            if isSameItem(current, folder) { return true }
            let up = current.deletingLastPathComponent().normalized
            if up.path == current.path || current.path == "/" { return false }
            current = up
        }
    }

    /// Somewhere below `folder` (not `folder` itself).
    public func isInside(_ folder: URL) -> Bool {
        let base = folder.path == "/" ? "" : folder.path
        return path.hasPrefix(base + "/") && !isSameFile(as: folder)
    }

    /// Directly in `folder`.
    public func isDirectlyInside(_ folder: URL) -> Bool { deletingLastPathComponent().isSameFile(as: folder) }

    /// This URL with `old` at the start of its path changed to `new`; unchanged if it isn't in
    /// `old`. Folders reached through a symlink (/tmp is really /private/tmp) list their items
    /// under the real path, and this puts them back under the path the folder was opened by.
    public func replacingFolder(_ old: URL, with new: URL) -> URL {
        if isSameFile(as: old) { return new.normalized }
        guard isInside(old) else { return self }
        let base = old.path == "/" ? "" : old.path
        return new.appending(path: String(path.dropFirst(base.count + 1))).normalized
    }

    /// The path with every symlink followed, as the file system reports it (/tmp is
    /// /private/tmp). Unlike `resolvingSymlinksInPath()`, which turns /private/tmp back into
    /// /tmp. Reads the disk; itself if the path doesn't exist.
    public var realPath: URL {
        guard let resolved = realpath(path, nil) else { return normalized }
        defer { free(resolved) }
        return URL(filePath: String(cString: resolved), directoryHint: .notDirectory)
    }

    /// The top of the startup disk, "/".
    public var isFileSystemRoot: Bool { path == "/" }

    /// Desktop, Documents and Downloads: macOS asks before an app looks inside them, and some
    /// lookups about the folder itself (its iCloud state, kind, localized name, icon) go through
    /// system helpers that count as looking inside. Listing Home asks nothing of them beyond
    /// the basics, so the prompt only comes when you open one.
    public func isGuardedFolder(home: URL) -> Bool {
        ["Desktop", "Documents", "Downloads"].contains { isSameFile(as: home.appending(path: $0)) }
    }

    /// The user's Trash, or a Trash folder on another disk (`/Volumes/X/.Trashes/501`).
    public func isTrashFolder(home: URL) -> Bool {
        isSameFile(as: home.appending(path: ".Trash")) || path.contains("/.Trashes/")
    }
}
