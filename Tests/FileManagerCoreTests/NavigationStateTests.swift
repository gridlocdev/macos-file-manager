import Foundation
import Testing

@testable import FileManagerCore

@Suite struct BreadcrumbTests {
    @Test func startupDisk() {
        let segments = Breadcrumbs.segments(
            for: URL(filePath: "/Users/me/src"), volumes: ["/": "Macintosh HD"], startupDiskName: "Macintosh HD")
        #expect(segments.map(\.title) == ["Macintosh HD", "Users", "me", "src"])
        #expect(segments.map(\.url.path) == ["/", "/Users", "/Users/me", "/Users/me/src"])
    }

    @Test func otherDisk() {
        let segments = Breadcrumbs.segments(
            for: URL(filePath: "/Volumes/USB Stick/Photos"),
            volumes: ["/": "Macintosh HD", "/Volumes/USB Stick": "USB Stick"], startupDiskName: "Macintosh HD")
        #expect(segments.map(\.title) == ["USB Stick", "Photos"])
        #expect(segments.first?.url.path == "/Volumes/USB Stick")
    }

    @Test func iCloudDriveAndAppFoldersByName() {
        let home = URL(filePath: "/Users/me")
        let base = "/Users/me/Library/Mobile Documents"
        func titles(_ path: String) -> [String] {
            Breadcrumbs.segments(
                for: URL(filePath: path), volumes: [:], startupDiskName: "HD", home: home, iCloudHome: home,
                appName: { $0 == "com~apple~Numbers" ? "Numbers" : nil }
            ).map(\.title)
        }
        #expect(titles(base + "/com~apple~CloudDocs/Taxes") == ["iCloud Drive", "Taxes"])
        #expect(titles(base + "/com~apple~Numbers/Documents/2026") == ["iCloud Drive", "Numbers", "2026"])
        let numbers = Breadcrumbs.segments(
            for: URL(filePath: base + "/com~apple~Numbers/Documents"), volumes: [:], startupDiskName: "HD",
            iCloudHome: home, appName: { _ in "Numbers" })
        #expect(numbers.map(\.url.path) == [base + "/com~apple~CloudDocs", base + "/com~apple~Numbers/Documents"])
        // An app's private data, or no name for it: the plain path.
        #expect(titles(base + "/com~apple~mail/Data") == ["~", "Library", "Mobile Documents", "com~apple~mail", "Data"])
        #expect(titles(base + "/com~apple~Pages/Documents").count == 5)
    }

    @Test func rootAlone() {
        let segments = Breadcrumbs.segments(for: URL(filePath: "/"), volumes: [:], startupDiskName: "HD")
        #expect(segments.map(\.title) == ["HD"])
    }

    @Test func homeShortened() {
        let home = URL(filePath: "/Users/me")
        let inside = Breadcrumbs.segments(
            for: URL(filePath: "/Users/me/src/app"), volumes: [:], startupDiskName: "HD", home: home)
        #expect(inside.map(\.title) == ["~", "src", "app"])
        #expect(inside.map(\.url.path) == ["/Users/me", "/Users/me/src", "/Users/me/src/app"])
        let atHome = Breadcrumbs.segments(for: home, volumes: [:], startupDiskName: "HD", home: home)
        #expect(atHome.map(\.title) == ["~"])
        // Outside home (and a folder whose name only starts the same) keeps the full path.
        let outside = Breadcrumbs.segments(
            for: URL(filePath: "/Users/meg"), volumes: [:], startupDiskName: "HD", home: home)
        #expect(outside.map(\.title) == ["HD", "Users", "meg"])
    }

    @Test func diskWithSimilarName() {
        let segments = Breadcrumbs.segments(
            for: URL(filePath: "/Volumes/USB2/x"), volumes: ["/Volumes/USB": "USB"], startupDiskName: "HD")
        #expect(segments.map(\.title) == ["HD", "Volumes", "USB2", "x"])
    }
}

@Suite struct SidebarListTests {
    @Test func recentsNewestFirstWithoutDuplicates() {
        var recent = RecentFolders(limit: 3)
        for path in ["/a", "/b", "/a", "/c", "/d"] { recent.visit(path) }
        #expect(recent.paths == ["/d", "/c", "/a"])
    }

    @Test func pinAddsMovesAndUnpins() {
        var pins = PinnedFolders(paths: ["/a", "/b", "/c"])
        pins.pin(["/x"], at: 1)
        #expect(pins.paths == ["/a", "/x", "/b", "/c"])
        pins.pin(["/c"], at: 0)
        #expect(pins.paths == ["/c", "/a", "/x", "/b"])
        pins.pin(["/a"])
        #expect(pins.paths == ["/c", "/x", "/b", "/a"])
        pins.unpin("/x")
        #expect(pins.paths == ["/c", "/b", "/a"])
    }

    @Test func moveLikeSwiftUI() {
        var pins = PinnedFolders(paths: ["/a", "/b", "/c", "/d"])
        pins.move(from: [0], to: 3)
        #expect(pins.paths == ["/b", "/c", "/a", "/d"])
        pins.move(from: [3], to: 0)
        #expect(pins.paths == ["/d", "/b", "/c", "/a"])
    }
}

@Suite struct SessionStateTests {
    @Test func dropsMissingFoldersAndEmptyWindows() {
        let session = SessionState(windows: [
            .init(tabs: ["/a", "/gone", "/b"], selected: 2),
            .init(tabs: ["/gone"]),
            .init(tabs: ["/gone", "/c"], selected: 0),
        ])
        let restored = session.restorable { $0 != "/gone" }
        #expect(restored.windows == [.init(tabs: ["/a", "/b"], selected: 1), .init(tabs: ["/c"], selected: 0)])
    }

    @Test func roundTripsThroughJSON() throws {
        let session = SessionState(windows: [.init(tabs: ["/a", "/b"], selected: 1)])
        let data = try JSONEncoder().encode(session)
        #expect(try JSONDecoder().decode(SessionState.self, from: data) == session)
    }
}
