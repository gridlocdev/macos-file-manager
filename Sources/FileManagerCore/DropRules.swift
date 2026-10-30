import Foundation

/// What a drag-and-drop does, like Explorer and Finder: on the same disk it moves, onto another
/// disk it copies. Holding Opt always copies and Cmd always moves.
public enum DropRules {
    public enum Operation: Sendable, Equatable { case copy, move, none }

    /// - sources: the dragged items.
    /// - folder: where they'd land.
    /// - sameVolume: whether two URLs are on the same disk.
    /// - sameItem: whether two URLs are the same item (`URL.isSameItem` for the real disk).
    public static func operation(
        dropping sources: [URL], into folder: URL,
        option: Bool, command: Bool,
        sameVolume: (URL, URL) -> Bool,
        sameItem: (URL, URL) -> Bool = { $0.standardizedFileURL.path == $1.standardizedFileURL.path }
    ) -> Operation {
        // Onto itself or into its own subfolder.
        for source in sources where folder.isItemOrInside(source, isSameItem: sameItem) { return .none }
        if option { return .copy }
        let alreadyThere = sources.allSatisfy { sameItem($0.deletingLastPathComponent(), folder) }
        if command { return alreadyThere ? .none : .move }
        // Dropping back where they came from does nothing (copy with Opt to duplicate).
        if alreadyThere { return .none }
        return sources.allSatisfy { sameVolume($0, folder) } ? .move : .copy
    }
}

/// Total size of a folder's contents, for Get Info.
public struct FolderSize: Sendable, Equatable {
    /// Sum of file sizes (what the Size column shows for files).
    public var bytes: Int64 = 0
    /// Space actually used on disk.
    public var allocatedBytes: Int64 = 0
    public var files = 0
    public var folders = 0

    public init() {}

    /// Walks the folder (including hidden items and package contents). Stops early, returning
    /// the partial total, when `isCancelled` returns true.
    public static func measure(_ url: URL, isCancelled: () -> Bool = { false }) -> FolderSize {
        var total = FolderSize()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [])
        else { return total }
        for case let item as URL in walker {
            if isCancelled() { break }
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true && values.isSymbolicLink != true {
                total.folders += 1
            } else {
                total.files += 1
                total.bytes += Int64(values.fileSize ?? 0)
                total.allocatedBytes += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

public enum Permissions {
    /// "drwxr-xr-x" style, as `ls -l` shows it.
    public static func symbolic(_ posix: Int, isFolder: Bool) -> String {
        let letters: [(Int, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        return String(isFolder ? "d" : "-") + String(letters.map { posix & $0.0 != 0 ? $0.1 : "-" })
    }

    /// "Read & Write" / "Read only" / "Write only" / "No access" for one rwx triplet.
    public static func access(_ triplet: Int) -> String {
        switch (triplet & 4 != 0, triplet & 2 != 0) {
        case (true, true): "Read & Write"
        case (true, false): "Read only"
        case (false, true): "Write only"
        case (false, false): "No access"
        }
    }
}
