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

    /// The user's Trash, or a Trash folder on another disk (`/Volumes/X/.Trashes/501`).
    public func isTrashFolder(home: URL) -> Bool {
        isSameFile(as: home.appending(path: ".Trash")) || path.contains("/.Trashes/")
    }
}
