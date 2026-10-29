import Foundation

/// One row in a folder listing.
public struct FileItem: Identifiable, Hashable, Sendable {
    public var url: URL
    public var name: String
    /// A folder you navigate into (packages like .app count as files).
    public var isFolder: Bool
    public var isHidden: Bool
    public var size: Int64?
    public var modified: Date?
    public var kind: String
    public var created: Date?
    /// When it was put in this folder (Finder's Date Added).
    public var added: Date?
    /// POSIX mode bits (0o755), for the Permissions column.
    public var permissions: Int?
    /// Finder tags ("Red", "Work").
    public var tags: [String] = []
    /// Whether it's in iCloud Drive and downloaded; nil for items that aren't in iCloud.
    public var cloud: CloudStatus?

    public var id: URL { url }

    /// The extension as shown in the Extension column ("txt"); folders have none.
    public var fileExtension: String { isFolder ? "" : url.pathExtension.lowercased() }

    public init(
        url: URL, name: String, isFolder: Bool, isHidden: Bool = false,
        size: Int64? = nil, modified: Date? = nil, kind: String = "",
        created: Date? = nil, added: Date? = nil, permissions: Int? = nil
    ) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.isHidden = isHidden
        self.size = size
        self.modified = modified
        self.kind = kind
        self.created = created
        self.added = added
        self.permissions = permissions
    }
}

public struct FileSort: Hashable, Sendable {
    public enum Column: String, CaseIterable, Sendable {
        case name, modified, kind, size, created, added, ext, permissions, tags

        public var title: String {
            switch self {
            case .name: "Name"
            case .modified: "Date Modified"
            case .kind: "Kind"
            case .size: "Size"
            case .created: "Date Created"
            case .added: "Date Added"
            case .ext: "Extension"
            case .permissions: "Permissions"
            case .tags: "Tags"
            }
        }

        /// Shown until you choose otherwise (right-click the column headers).
        public var isShownByDefault: Bool { [.name, .modified, .kind, .size].contains(self) }
    }

    public var column: Column
    public var ascending: Bool
    public var foldersFirst: Bool

    public init(column: Column = .name, ascending: Bool = true, foldersFirst: Bool = true) {
        self.column = column
        self.ascending = ascending
        self.foldersFirst = foldersFirst
    }

    /// Folders first (if set), then the column, then name as the tie-breaker. Names compare
    /// like Finder and Explorer: case-insensitive, numbers by value ("2" before "10").
    public func sorted(_ items: [FileItem]) -> [FileItem] {
        items.sorted { a, b in
            if foldersFirst, a.isFolder != b.isFolder { return a.isFolder }
            let order = compare(a, b)
            if order != .orderedSame { return ascending ? order == .orderedAscending : order == .orderedDescending }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private func compare(_ a: FileItem, _ b: FileItem) -> ComparisonResult {
        switch column {
        case .name:
            return a.name.localizedStandardCompare(b.name)
        case .kind:
            return a.kind.localizedStandardCompare(b.kind)
        case .modified:
            return order(a.modified ?? .distantPast, b.modified ?? .distantPast)
        case .size:
            return order(a.size ?? -1, b.size ?? -1)
        case .created:
            return order(a.created ?? .distantPast, b.created ?? .distantPast)
        case .added:
            return order(a.added ?? .distantPast, b.added ?? .distantPast)
        case .ext:
            return a.fileExtension.localizedStandardCompare(b.fileExtension)
        case .permissions:
            return order(a.permissions ?? -1, b.permissions ?? -1)
        case .tags:
            // Untagged items last.
            let left = a.tags.first ?? "\u{10FFFF}", right = b.tags.first ?? "\u{10FFFF}"
            return left.localizedStandardCompare(right)
        }
    }

    private func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }
}

/// An iCloud Drive item's state.
public enum CloudStatus: String, Hashable, Sendable {
    /// Downloaded and up to date.
    case current
    /// Only in iCloud; opening it downloads it.
    case notDownloaded
    case downloading
    case uploading

    public var title: String {
        switch self {
        case .current: "Downloaded"
        case .notDownloaded: "In iCloud only"
        case .downloading: "Downloading"
        case .uploading: "Uploading"
        }
    }
}

/// Finder's standard tag colours, by name.
public enum TagColor {
    public static let standard = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]

    /// Index into `standard`, or nil for a tag without a standard colour.
    public static func index(of tag: String) -> Int? {
        standard.firstIndex { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }
}
