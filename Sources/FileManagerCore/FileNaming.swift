import Foundation

/// Names for new, duplicated and conflicting items, Explorer style.
public enum FileNaming {
    /// Splits "notes.txt" into ("notes", ".txt"). Folders, dotfiles (".config") and names
    /// without a dot have no extension.
    public static func split(_ name: String, isFolder: Bool = false) -> (base: String, ext: String) {
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[dot...]))
    }

    /// The first of "base.ext", "base (2).ext", "base (3).ext"… not in `existing`
    /// (compared case-insensitively, as on a Mac disk).
    public static func unique(_ name: String, isFolder: Bool = false, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var (base, ext) = split(name, isFolder: isFolder)
        // "notes (2).txt" continues as "notes (3).txt", not "notes (2) (2).txt".
        var start = 2
        if let match = base.firstMatch(of: /^(.*) \((\d+)\)$/), let n = Int(match.2) {
            base = String(match.1)
            start = n + 1
        }
        var n = start
        while taken.contains("\(base) (\(n))\(ext)".lowercased()) { n += 1 }
        return "\(base) (\(n))\(ext)"
    }

    /// Keep both: "notes.txt" next to an existing "notes.txt" becomes "notes (2).txt".
    public static func keepBoth(_ name: String, isFolder: Bool = false, existing: Set<String>) -> String {
        unique(name, isFolder: isFolder, existing: existing)
    }

    /// Duplicate: "notes.txt" → "notes - Copy.txt", then "notes - Copy (2).txt".
    public static func duplicate(_ name: String, isFolder: Bool = false, existing: Set<String>) -> String {
        let (base, ext) = split(name, isFolder: isFolder)
        return unique("\(base) - Copy\(ext)", isFolder: isFolder, existing: existing)
    }

    public static let newFolderName = "New Folder"
    public static let newTextFileName = "New Text File.txt"

    /// Why a typed name can't be used, or nil if it's fine.
    public static func problem(with name: String) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "The name can't be empty." }
        if name.contains("/") || name.contains(":") { return "The name can't contain “/” or “:”." }
        if name == "." || name == ".." { return "“\(name)” is reserved." }
        if name.utf8.count > 255 { return "The name is too long." }
        return nil
    }

    /// How many characters to select when renaming: the name without its extension.
    public static func baseLength(of name: String, isFolder: Bool) -> Int {
        (split(name, isFolder: isFolder).base as NSString).length
    }
}
