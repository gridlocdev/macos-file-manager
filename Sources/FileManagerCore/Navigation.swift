import Foundation

/// The clickable parts of the address bar: the disk, then each folder down to the current one.
public enum Breadcrumbs {
    public struct Segment: Hashable, Sendable {
        public var title: String
        public var url: URL
    }

    /// - volumes: mount point path → disk name, for disks other than the startup disk.
    /// - startupDiskName: the title for "/".
    /// - home: when given, the home folder and everything above it are one "~" segment.
    /// - iCloudHome: when given (the home folder), iCloud Drive and the apps' folders in it go by
    ///   name, as in Finder: "iCloud Drive › Numbers" rather than "Library › Mobile Documents ›
    ///   com~apple~Numbers › Documents".
    /// - appName: an app's name from its iCloud container's folder name ("com~apple~Numbers").
    public static func segments(
        for url: URL, volumes: [String: String], startupDiskName: String, home: URL? = nil,
        iCloudHome: URL? = nil, appName: (String) -> String? = { _ in nil }
    ) -> [Segment] {
        let path = url.standardizedFileURL.path
        if let iCloudHome, let segments = iCloudSegments(path, home: iCloudHome, appName: appName) { return segments }
        if let home {
            let homePath = home.standardizedFileURL.path
            if homePath != "/", path == homePath || path.hasPrefix(homePath + "/") {
                var segments = [Segment(title: "~", url: URL(filePath: homePath))]
                var current = homePath
                for part in path.dropFirst(homePath.count).split(separator: "/") {
                    current = (current as NSString).appendingPathComponent(String(part))
                    segments.append(Segment(title: String(part), url: URL(filePath: current)))
                }
                return segments
            }
        }
        // The most specific mounted disk the folder is on ("/Volumes/USB").
        let mount = volumes.keys
            .filter { $0 != "/" && (path == $0 || path.hasPrefix($0 + "/")) }
            .max { $0.count < $1.count }
        var segments: [Segment]
        var base: String
        if let mount {
            segments = [Segment(title: volumes[mount] ?? (mount as NSString).lastPathComponent, url: URL(filePath: mount))]
            base = mount
        } else {
            segments = [Segment(title: startupDiskName, url: URL(filePath: "/"))]
            base = "/"
        }
        let rest = path.dropFirst(base.count).split(separator: "/")
        var current = base
        for part in rest {
            current = (current as NSString).appendingPathComponent(String(part))
            segments.append(Segment(title: String(part), url: URL(filePath: current)))
        }
        return segments
    }

    /// Nil when `path` isn't in iCloud Drive or an app's folder in it.
    private static func iCloudSegments(_ path: String, home: URL, appName: (String) -> String?) -> [Segment]? {
        let containers = home.standardizedFileURL.path + "/Library/Mobile Documents"
        guard path.hasPrefix(containers + "/") else { return nil }
        let parts = path.dropFirst(containers.count + 1).split(separator: "/").map(String.init)
        let drive = containers + "/com~apple~CloudDocs"
        var segments = [Segment(title: "iCloud Drive", url: URL(filePath: drive))]
        var current: String
        var rest: ArraySlice<String>
        if parts.first == "com~apple~CloudDocs" {
            current = drive
            rest = parts.dropFirst()
        } else if parts.count >= 2, parts[1] == "Documents", let name = appName(parts[0]) {
            current = containers + "/" + parts[0] + "/Documents"
            segments.append(Segment(title: name, url: URL(filePath: current)))
            rest = parts.dropFirst(2)
        } else {
            return nil
        }
        for part in rest {
            current += "/" + part
            segments.append(Segment(title: part, url: URL(filePath: current)))
        }
        return segments
    }
}

/// Folders visited lately, newest first, for the sidebar.
public struct RecentFolders: Codable, Equatable, Sendable {
    public private(set) var paths: [String]
    public var limit: Int

    public init(paths: [String] = [], limit: Int = 10) {
        self.paths = paths
        self.limit = limit
    }

    public mutating func visit(_ path: String) {
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > limit { paths.removeLast(paths.count - limit) }
    }

    public mutating func remove(_ path: String) { paths.removeAll { $0 == path } }
}

/// The sidebar's pinned folders, in the user's order.
public struct PinnedFolders: Codable, Equatable, Sendable {
    public private(set) var paths: [String]

    public init(paths: [String]) { self.paths = paths }

    /// Adds folders at `index` (end by default). Already-pinned folders move there instead.
    public mutating func pin(_ new: [String], at index: Int? = nil) {
        var position = min(index ?? paths.count, paths.count)
        for path in new {
            if let existing = paths.firstIndex(of: path) {
                paths.remove(at: existing)
                if existing < position { position -= 1 }
            }
            paths.insert(path, at: position)
            position += 1
        }
    }

    public mutating func unpin(_ path: String) { paths.removeAll { $0 == path } }

    public func isPinned(_ path: String) -> Bool { paths.contains(path) }

    /// SwiftUI's onMove arguments.
    public mutating func move(from source: IndexSet, to destination: Int) {
        let moving = source.map { paths[$0] }
        var remaining = paths.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: min(insertAt, remaining.count))
        paths = remaining
    }
}

/// Open windows and their tabs, saved on quit and reopened at launch.
public struct SessionState: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var tabs: [String]
        public var selected: Int

        public init(tabs: [String], selected: Int = 0) {
            self.tabs = tabs
            self.selected = selected
        }
    }

    public var windows: [Window]

    public init(windows: [Window] = []) { self.windows = windows }

    /// Drops folders that no longer exist and windows left with no tabs; keeps the selected tab
    /// pointing at the same folder where possible.
    public func restorable(exists: (String) -> Bool) -> SessionState {
        SessionState(
            windows: windows.compactMap { window in
                let kept = window.tabs.enumerated().filter { exists($0.element) }
                guard !kept.isEmpty else { return nil }
                let selected = kept.firstIndex { $0.offset == window.selected } ?? 0
                return Window(tabs: kept.map(\.element), selected: selected)
            })
    }
}
