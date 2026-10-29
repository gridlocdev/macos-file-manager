import Foundation

/// Renaming several items at once: a new name, find and replace, a case change and numbers,
/// applied in that order to each name (without its extension unless asked).
public struct BatchRenameOptions: Hashable, Sendable {
    /// Replaces each name when not empty ("Holiday" + numbers gives "Holiday 1", "Holiday 2"…).
    public var newName = ""
    public var find = ""
    public var replace = ""
    public var matchCase = false
    /// Find is a regular expression; Replace can use $1, $2… for its groups.
    public var useRegex = false
    public var caseChange = CaseChange.unchanged
    public var numbering = Numbering.none
    public var startNumber = 1
    /// Pads numbers with zeros to this many digits (3 gives 001).
    public var digits = 1
    public var separator = " "
    /// Find, replace and case changes also apply to the extension.
    public var includeExtension = false

    public init() {}

    public enum CaseChange: String, CaseIterable, Sendable {
        case unchanged, lower, upper, title

        public var title: String {
            switch self {
            case .unchanged: "Unchanged"
            case .lower: "lowercase"
            case .upper: "UPPERCASE"
            case .title: "Title Case"
            }
        }
    }

    public enum Numbering: String, CaseIterable, Sendable {
        case none, before, after

        public var title: String {
            switch self {
            case .none: "None"
            case .before: "Before Name"
            case .after: "After Name"
            }
        }
    }
}

public enum BatchRename {
    public struct Item: Hashable, Sendable {
        public var url: URL
        public var isFolder: Bool

        public init(url: URL, isFolder: Bool) {
            self.url = url
            self.isFolder = isFolder
        }
    }

    public struct Entry: Hashable, Sendable {
        public var url: URL
        public var newName: String
        /// Why it can't be renamed to `newName`, or nil.
        public var problem: String?

        public var name: String { url.lastPathComponent }
        public var isChanged: Bool { newName != name }
        public var target: URL { url.deletingLastPathComponent().appendingPathComponent(newName) }
    }

    public struct Preview: Hashable, Sendable {
        public var entries: [Entry]
        /// The Find pattern isn't a valid regular expression.
        public var patternError: String?

        public var canRename: Bool {
            patternError == nil && entries.contains(where: \.isChanged) && !entries.contains { $0.problem != nil }
        }
    }

    /// The new name for each item, in order, with any problems: an invalid name, two items
    /// getting the same name, or a name already used by something else in the folder.
    /// - existingNames: the names in a folder (any case).
    public static func preview(
        _ items: [Item], options: BatchRenameOptions, existingNames: (URL) -> Set<String>
    ) -> Preview {
        var regex: NSRegularExpression?
        if !options.find.isEmpty {
            let pattern = options.useRegex ? options.find : NSRegularExpression.escapedPattern(for: options.find)
            do {
                regex = try NSRegularExpression(pattern: pattern, options: options.matchCase ? [] : [.caseInsensitive])
            } catch {
                let entries = items.map { Entry(url: $0.url, newName: $0.url.lastPathComponent) }
                return Preview(entries: entries, patternError: "The Find pattern isn't a valid regular expression.")
            }
        }
        var entries = items.enumerated().map { index, item in
            Entry(
                url: item.url,
                newName: newName(
                    item.url.lastPathComponent, isFolder: item.isFolder, number: options.startNumber + index,
                    options: options, regex: regex))
        }

        // Problems, folder by folder.
        let folders = Dictionary(grouping: entries.indices) { entries[$0].url.deletingLastPathComponent().path }
        for (folder, indices) in folders {
            let existing = Set(existingNames(URL(filePath: folder)).map { $0.lowercased() })
            let batchNames = Set(indices.map { entries[$0].name.lowercased() })
            var counts: [String: Int] = [:]
            for i in indices { counts[entries[i].newName.lowercased(), default: 0] += 1 }
            for i in indices where entries[i].isChanged {
                let new = entries[i].newName
                if let problem = FileNaming.problem(with: new) {
                    entries[i].problem = problem
                } else if counts[new.lowercased(), default: 0] > 1 {
                    entries[i].problem = "Another item would get this name too."
                } else if existing.contains(new.lowercased()), !batchNames.contains(new.lowercased()) {
                    entries[i].problem = "There's already an item with this name."
                }
            }
        }
        return Preview(entries: entries, patternError: nil)
    }

    static func newName(
        _ name: String, isFolder: Bool, number: Int, options: BatchRenameOptions, regex: NSRegularExpression?
    ) -> String {
        var (base, ext) = FileNaming.split(name, isFolder: isFolder)
        if options.includeExtension {
            base = name
            ext = ""
        }
        if !options.newName.isEmpty {
            // The new name replaces the name but keeps the extension.
            base = options.includeExtension ? options.newName + FileNaming.split(name, isFolder: isFolder).ext : options.newName
        }
        if let regex {
            let range = NSRange(base.startIndex..., in: base)
            let template = options.useRegex ? options.replace : NSRegularExpression.escapedTemplate(for: options.replace)
            base = regex.stringByReplacingMatches(in: base, range: range, withTemplate: template)
        }
        switch options.caseChange {
        case .unchanged: break
        case .lower: base = base.lowercased()
        case .upper: base = base.uppercased()
        case .title: base = base.capitalized
        }
        if options.numbering != .none {
            let digits = String(number)
            let padded = String(repeating: "0", count: max(0, options.digits - digits.count)) + digits
            if options.includeExtension {
                // Numbers go next to the name, not after the extension.
                var (b, e) = FileNaming.split(base, isFolder: isFolder)
                b = options.numbering == .before ? padded + options.separator + b : b + options.separator + padded
                return b + e
            }
            base = options.numbering == .before ? padded + options.separator + base : base + options.separator + padded
        }
        return base + ext
    }

    /// The moves that rename the changed entries. An item taking a name another item in the
    /// batch still has (swapping "a" and "b") goes through a temporary name first.
    public static func moves(_ entries: [Entry], temporaryName: () -> String = { ".\(UUID().uuidString)" })
        -> [(from: URL, to: URL)]
    {
        let changed = entries.filter(\.isChanged)
        let sources = Set(changed.map { $0.url.path.lowercased() })
        var toTemporary: [(URL, URL)] = []
        var direct: [(URL, URL)] = []
        var fromTemporary: [(URL, URL)] = []
        for entry in changed {
            let target = entry.target
            // A case-only change of its own name is fine (the executor handles it).
            let takesAnotherName = sources.contains(target.path.lowercased())
                && target.path.lowercased() != entry.url.path.lowercased()
            if takesAnotherName {
                let temp = entry.url.deletingLastPathComponent().appendingPathComponent(temporaryName())
                toTemporary.append((entry.url, temp))
                fromTemporary.append((temp, target))
            } else {
                direct.append((entry.url, target))
            }
        }
        // Direct targets are free names, so those moves can go first; then every name the
        // temporary items want has been vacated.
        return (toTemporary + direct + fromTemporary).map { (from: $0.0, to: $0.1) }
    }
}
