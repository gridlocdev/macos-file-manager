import Foundation

/// A name pattern as typed in Find or Select by Pattern. Several patterns can be separated by
/// ";" ("*.jpg;*.png"). A pattern with * or ? is a wildcard that must match the whole name;
/// anything else matches if the name contains it. Case never matters.
public struct NamePattern: Hashable, Sendable {
    public let text: String
    private let parts: [Part]

    private enum Part: Hashable {
        case contains(String)
        case wildcard(String)
    }

    public init(_ text: String) {
        self.text = text
        parts = text.split(separator: ";").compactMap { raw in
            let part = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !part.isEmpty else { return nil }
            return part.contains("*") || part.contains("?") ? .wildcard(part) : .contains(part)
        }
    }

    /// Nothing typed: matches every name.
    public var isEmpty: Bool { parts.isEmpty }

    public func matches(_ name: String) -> Bool {
        guard !parts.isEmpty else { return true }
        let name = name.lowercased()
        return parts.contains { part in
            switch part {
            case .contains(let text): name.contains(text)
            case .wildcard(let pattern): Self.wildcard(Array(pattern), matches: Array(name))
            }
        }
    }

    /// The same match as a Spotlight query on file names, or nil when nothing was typed.
    public var spotlightPredicate: NSPredicate? {
        let predicates = parts.map { part in
            switch part {
            case .contains(let text): NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", text)
            case .wildcard(let pattern): NSPredicate(format: "kMDItemFSName LIKE[cd] %@", pattern)
            }
        }
        // Spotlight throws on an OR of a single predicate.
        guard predicates.count > 1 else { return predicates.first }
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    /// * is any run of characters, ? is one character.
    private static func wildcard(_ pattern: [Character], matches name: [Character]) -> Bool {
        var p = 0, n = 0
        var star: Int?, starMatch = 0
        while n < name.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == name[n] {
                p += 1
                n += 1
            } else if p < pattern.count, pattern[p] == "*" {
                star = p
                starMatch = n
                p += 1
            } else if let star {
                p = star + 1
                starMatch += 1
                n = starMatch
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }
}

/// What Find looks for: a name plus optional kind, date and size filters.
public struct SearchCriteria: Hashable, Sendable {
    public var text = ""
    public var kind = Kind.any
    public var date = DateRange.any
    public var size = SizeRange.any
    /// Only items with this Finder tag; nil for any.
    public var tag: String?

    public init(
        text: String = "", kind: Kind = .any, date: DateRange = .any, size: SizeRange = .any, tag: String? = nil
    ) {
        self.text = text
        self.kind = kind
        self.date = date
        self.size = size
        self.tag = tag
    }

    public enum Kind: String, CaseIterable, Sendable {
        case any, folder, document, image, audio, video, archive, application

        public var title: String {
            switch self {
            case .any: "Any Kind"
            case .folder: "Folders"
            case .document: "Documents"
            case .image: "Images"
            case .audio: "Music and Audio"
            case .video: "Movies"
            case .archive: "Archives"
            case .application: "Applications"
            }
        }

        /// File extensions for each kind (folders are matched by `isFolder`).
        var extensions: Set<String> {
            switch self {
            case .any, .folder: []
            case .document:
                [
                    "txt", "md", "rtf", "rtfd", "pdf", "doc", "docx", "odt", "pages", "xls", "xlsx", "ods", "numbers",
                    "csv", "tsv", "ppt", "pptx", "odp", "key", "epub", "html", "htm", "json", "xml", "yaml", "yml",
                ]
            case .image:
                [
                    "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "svg", "raw", "cr2",
                    "cr3", "nef", "arw", "dng", "psd", "ico", "icns", "avif",
                ]
            case .audio: ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "ogg", "opus", "alac", "mid", "midi"]
            case .video: ["mov", "mp4", "m4v", "avi", "mkv", "webm", "wmv", "mpg", "mpeg", "3gp"]
            case .archive: ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "iso", "pkg"]
            case .application: ["app"]
            }
        }

        func matches(_ item: FileItem) -> Bool {
            switch self {
            case .any: true
            case .folder: item.isFolder
            default: !item.isFolder && extensions.contains(item.url.pathExtension.lowercased())
            }
        }
    }

    public enum DateRange: String, CaseIterable, Sendable {
        case any, today, week, month, year

        public var title: String {
            switch self {
            case .any: "Any Date"
            case .today: "Today"
            case .week: "Past Week"
            case .month: "Past Month"
            case .year: "Past Year"
            }
        }

        /// The earliest modification date that counts, or nil for any date.
        func start(now: Date, calendar: Calendar) -> Date? {
            switch self {
            case .any: nil
            case .today: calendar.startOfDay(for: now)
            case .week: calendar.date(byAdding: .day, value: -7, to: now)
            case .month: calendar.date(byAdding: .month, value: -1, to: now)
            case .year: calendar.date(byAdding: .year, value: -1, to: now)
            }
        }
    }

    /// Size filters only match files (a folder has no size in the list).
    public enum SizeRange: String, CaseIterable, Sendable {
        case any, small, medium, large

        public var title: String {
            switch self {
            case .any: "Any Size"
            case .small: "Under 1 MB"
            case .medium: "1 MB to 100 MB"
            case .large: "Over 100 MB"
            }
        }

        func matches(_ item: FileItem) -> Bool {
            let mb: Int64 = 1_000_000
            switch self {
            case .any: return true
            case .small, .medium, .large:
                guard !item.isFolder, let size = item.size else { return false }
                return self == .small ? size < mb : self == .medium ? size >= mb && size <= 100 * mb : size > 100 * mb
            }
        }
    }

    /// No text and no filters: everything matches.
    public var isEmpty: Bool { NamePattern(text).isEmpty && hasNoFilters }
    public var hasNoFilters: Bool { kind == .any && date == .any && size == .any && tag == nil }

    private func hasTag(_ item: FileItem) -> Bool {
        guard let tag else { return true }
        return item.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    public func matches(_ item: FileItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard NamePattern(text).matches(item.name), kind.matches(item), size.matches(item), hasTag(item)
        else { return false }
        if let start = date.start(now: now, calendar: calendar) {
            guard let modified = item.modified, modified >= start else { return false }
        }
        return true
    }

    /// Filters a list (makes the name pattern once).
    public func filter(_ items: [FileItem], now: Date = Date(), calendar: Calendar = .current) -> [FileItem] {
        guard !isEmpty else { return items }
        let pattern = NamePattern(text)
        let start = date.start(now: now, calendar: calendar)
        return items.filter { item in
            guard pattern.matches(item.name), kind.matches(item), size.matches(item), hasTag(item) else { return false }
            if let start { return (item.modified ?? .distantPast) >= start }
            return true
        }
    }
}

public enum Selection {
    /// Invert Selection: everything that wasn't selected.
    public static func inverted<ID: Hashable>(_ selected: Set<ID>, in all: [ID]) -> Set<ID> {
        Set(all.filter { !selected.contains($0) })
    }
}
