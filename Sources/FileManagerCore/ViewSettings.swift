import Foundation

/// How a folder is shown. Remembered per folder (`FolderViewMemory`), like Explorer.
public struct FolderView: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case details, icons

        public var title: String { self == .details ? "Details" : "Icons" }
    }

    public var mode = Mode.details
    public var sortColumn = FileSort.Column.name
    public var ascending = true
    public var groupBy = GroupBy.none
    /// Icon size in the icon view, in points.
    public var iconSize = FolderView.defaultIconSize
    /// Icon size in the details list (the row grows with it).
    public var listIconSize = FolderView.defaultListIconSize

    public init() {}

    public static let iconSizes = [32, 48, 64, 96, 128, 192, 256]
    public static let listIconSizes = [16, 24, 32]
    public static let defaultIconSize = 64
    public static let defaultListIconSize = 16

    /// Zoom (Cmd+= / Cmd+-) works on whichever view is showing. False when already at the end.
    @discardableResult
    public mutating func zoom(in zoomIn: Bool) -> Bool {
        switch mode {
        case .icons: Self.step(&iconSize, in: Self.iconSizes, up: zoomIn)
        case .details: Self.step(&listIconSize, in: Self.listIconSizes, up: zoomIn)
        }
    }

    /// Cmd+0.
    public mutating func resetZoom() {
        switch mode {
        case .icons: iconSize = Self.defaultIconSize
        case .details: listIconSize = Self.defaultListIconSize
        }
    }

    private static func step(_ value: inout Int, in sizes: [Int], up: Bool) -> Bool {
        let next = up ? sizes.first { $0 > value } : sizes.last { $0 < value }
        guard let next else { return false }
        value = next
        return true
    }

    public var sort: FileSort {
        get { FileSort(column: sortColumn, ascending: ascending) }
        set {
            sortColumn = newValue.column
            ascending = newValue.ascending
        }
    }
}

extension FileSort.Column: Codable {}

/// Views chosen for folders, kept in Application Support (never in the folders themselves).
/// Holds the most recently changed `limit` folders.
public struct FolderViewMemory: Codable, Sendable {
    private var views: [String: FolderView] = [:]
    private var order: [String] = []
    public var limit = 2000

    public init() {}

    public func view(for path: String) -> FolderView? { views[path] }

    public mutating func remember(_ view: FolderView, for path: String) {
        order.removeAll { $0 == path }
        order.append(path)
        views[path] = view
        while order.count > limit { views[order.removeFirst()] = nil }
    }

    public var count: Int { views.count }
}

public enum GroupBy: String, Codable, CaseIterable, Sendable {
    case none, kind, modified, size

    public var title: String {
        switch self {
        case .none: "None"
        case .kind: "Kind"
        case .modified: "Date Modified"
        case .size: "Size"
        }
    }
}

/// A row in a grouped list: a group's heading or an item.
public enum ListRow: Hashable, Sendable {
    case header(String, count: Int)
    case item(FileItem)

    public var item: FileItem? {
        if case .item(let item) = self { item } else { nil }
    }
}

public enum Grouping {
    public struct Group: Hashable, Sendable {
        public var title: String
        public var items: [FileItem]
    }

    /// Groups in a fixed order (Folders first; newest dates first; smallest sizes first),
    /// each keeping the items' sorted order. Empty groups are left out.
    public static func groups(
        _ items: [FileItem], by groupBy: GroupBy, now: Date = Date(), calendar: Calendar = .current
    ) -> [Group] {
        guard groupBy != .none else { return [Group(title: "", items: items)] }
        var buckets: [String: [FileItem]] = [:]
        var rank: [String: Int] = [:]
        for item in items {
            let (title, order) = bucket(item, by: groupBy, now: now, calendar: calendar)
            buckets[title, default: []].append(item)
            rank[title] = order
        }
        return buckets.keys
            .sorted { a, b in
                rank[a]! != rank[b]! ? rank[a]! < rank[b]! : a.localizedStandardCompare(b) == .orderedAscending
            }
            .map { Group(title: $0, items: buckets[$0]!) }
    }

    /// Headings and items, ready for the list. No headings when not grouping.
    public static func rows(
        _ items: [FileItem], by groupBy: GroupBy, now: Date = Date(), calendar: Calendar = .current
    ) -> [ListRow] {
        guard groupBy != .none else { return items.map(ListRow.item) }
        return groups(items, by: groupBy, now: now, calendar: calendar).flatMap { group in
            [ListRow.header(group.title, count: group.items.count)] + group.items.map(ListRow.item)
        }
    }

    /// The group's title and its place in the order.
    static func bucket(_ item: FileItem, by groupBy: GroupBy, now: Date, calendar: Calendar) -> (String, Int) {
        switch groupBy {
        case .none:
            return ("", 0)
        case .kind:
            // Alphabetical after Folders (rank 1 ties sort by title).
            return item.isFolder ? ("Folders", 0) : (item.kind.isEmpty ? "Other" : item.kind, 1)
        case .modified:
            guard let date = item.modified else { return ("Unknown", 9) }
            if calendar.isDate(date, inSameDayAs: now) { return ("Today", 0) }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                calendar.isDate(date, inSameDayAs: yesterday)
            {
                return ("Yesterday", 1)
            }
            let ago = now.timeIntervalSince(date)
            let day = 86_400.0
            if ago < 7 * day { return ("Past Week", 2) }
            if let month = calendar.date(byAdding: .month, value: -1, to: now), date >= month { return ("Past Month", 3) }
            if let year = calendar.date(byAdding: .year, value: -1, to: now), date >= year { return ("Past Year", 4) }
            return ("Older", 5)
        case .size:
            // Explorer's size groups.
            guard !item.isFolder else { return ("Folders", 0) }
            let size = item.size ?? 0
            let kb: Int64 = 1024, mb = 1024 * kb, gb = 1024 * mb
            switch size {
            case 0: return ("Empty", 1)
            case ..<(16 * kb): return ("Tiny (under 16 KB)", 2)
            case ..<mb: return ("Small (16 KB to 1 MB)", 3)
            case ..<(128 * mb): return ("Medium (1 to 128 MB)", 4)
            case ..<gb: return ("Large (128 MB to 1 GB)", 5)
            case ..<(4 * gb): return ("Huge (1 to 4 GB)", 6)
            default: return ("Gigantic (over 4 GB)", 7)
            }
        }
    }
}
