import Foundation

/// Turns what the user typed in the address bar into a folder URL, and completes partial paths.
public enum PathInput {
    /// Accepts absolute paths, `~`, `~/x`, `file://` URLs and paths relative to `current`.
    public static func resolve(_ text: String, relativeTo current: URL, home: URL) -> URL? {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("file://") {
            guard let url = URL(string: path), url.isFileURL else { return nil }
            path = url.path
        }
        if path == "~" {
            path = home.path
        } else if path.hasPrefix("~/") {
            path = home.path + path.dropFirst(1)
        } else if !path.hasPrefix("/") {
            path = current.path + "/" + path
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// Display form of a folder: home becomes `~`.
    public static func display(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    /// Tab completion: extends the last path component to the longest prefix shared by the
    /// matching subfolders (case-insensitive), adding "/" when exactly one matches.
    /// `subfolders` lists folder names inside a directory. Returns nil when nothing matches.
    public static func complete(
        _ text: String, relativeTo current: URL, home: URL,
        subfolders: (URL) -> [String]
    ) -> String? {
        let slash = text.lastIndex(of: "/")
        let parentText = slash.map { String(text[...$0]) } ?? ""
        let partial = slash.map { String(text[text.index(after: $0)...]) } ?? text
        let parentURL: URL
        if parentText.isEmpty {
            parentURL = current
        } else {
            guard let url = resolve(parentText, relativeTo: current, home: home) else { return nil }
            parentURL = url
        }
        let showHidden = partial.hasPrefix(".")
        let matches = subfolders(parentURL)
            .filter { showHidden || !$0.hasPrefix(".") }
            .filter { $0.lowercased().hasPrefix(partial.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let first = matches.first else { return nil }
        if matches.count == 1 { return parentText + first + "/" }
        let common = matches.dropFirst().reduce(first) { commonPrefix($0, $1) }
        // At least as long as what was typed: also fixes its case to match the folders.
        return parentText + (common.count >= partial.count ? common : partial)
    }

    private static func commonPrefix(_ a: String, _ b: String) -> String {
        var result = ""
        for (x, y) in zip(a, b) {
            guard x.lowercased() == y.lowercased() else { break }
            result.append(x)
        }
        return result
    }
}
