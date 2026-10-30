import Foundation
import FileManagerCore
import Observation

/// Pinned folders and recent folders, shared by every window and kept in UserDefaults.
@MainActor @Observable
final class SidebarStore {
    static let shared = SidebarStore()

    private(set) var pins: PinnedFolders
    private(set) var recent: RecentFolders

    private static let pinsKey = "sidebarPins"
    private static let recentKey = "recentFolders"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Snapshot runs start from the standard sidebar, not yours.
        guard !Windows.isSnapshotRun else {
            pins = PinnedFolders(paths: Self.defaultPins())
            recent = RecentFolders()
            return
        }
        pins = defaults.data(forKey: Self.pinsKey).flatMap { try? JSONDecoder().decode(PinnedFolders.self, from: $0) }
            ?? PinnedFolders(paths: Self.defaultPins())
        recent = defaults.data(forKey: Self.recentKey).flatMap { try? JSONDecoder().decode(RecentFolders.self, from: $0) }
            ?? RecentFolders()
    }

    /// Home, Desktop, Documents, Downloads, Applications and iCloud Drive (if signed in).
    static func defaultPins() -> [String] {
        let home = Windows.snapshotHome ?? FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [home, home + "/Desktop", home + "/Documents", home + "/Downloads", "/Applications"]
        let iCloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if !Windows.isSnapshotRun, FileManager.default.fileExists(atPath: iCloud) { paths.append(iCloud) }
        return paths
    }

    func pin(_ paths: [String], at index: Int? = nil) {
        pins.pin(paths, at: index)
        save()
    }

    func unpin(_ path: String) {
        pins.unpin(path)
        save()
    }

    func movePins(from source: IndexSet, to destination: Int) {
        pins.move(from: source, to: destination)
        save()
    }

    func visited(_ path: String) {
        recent.visit(path)
        save()
    }

    func forget(_ path: String) {
        recent.remove(path)
        save()
    }

    private func save() {
        // Snapshot runs leave the user's sidebar alone.
        guard !Windows.isSnapshotRun else { return }
        defaults.set(try? JSONEncoder().encode(pins), forKey: Self.pinsKey)
        defaults.set(try? JSONEncoder().encode(recent), forKey: Self.recentKey)
    }
}
