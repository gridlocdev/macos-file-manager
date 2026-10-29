import Foundation
import Testing

@testable import FileManagerCore

@Suite struct ViewSettingsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func file(_ name: String, kind: String = "Text", size: Int64? = 10, daysOld: Double? = 0, folder: Bool = false)
        -> FileItem
    {
        FileItem(
            url: URL(filePath: "/x/\(name)"), name: name, isFolder: folder, size: folder ? nil : size,
            modified: daysOld.map { now.addingTimeInterval(-$0 * 86_400) }, kind: folder ? "Folder" : kind)
    }

    @Test func zoomStepsThroughSizesAndStopsAtTheEnds() {
        var view = FolderView()
        view.mode = .icons
        var zoomed = view.zoom(in: true)
        #expect(zoomed)
        #expect(view.iconSize == 96)
        view.iconSize = 256
        zoomed = view.zoom(in: true)
        #expect(!zoomed)
        view.resetZoom()
        #expect(view.iconSize == FolderView.defaultIconSize)

        view.mode = .details
        zoomed = view.zoom(in: false)
        #expect(!zoomed)
        zoomed = view.zoom(in: true)
        #expect(zoomed)
        #expect(view.listIconSize == 24)
        #expect(view.iconSize == FolderView.defaultIconSize)
    }

    @Test func memoryKeepsTheMostRecentFolders() throws {
        var memory = FolderViewMemory()
        memory.limit = 2
        var icons = FolderView()
        icons.mode = .icons
        memory.remember(icons, for: "/a")
        memory.remember(FolderView(), for: "/b")
        memory.remember(icons, for: "/a")
        memory.remember(FolderView(), for: "/c")
        #expect(memory.view(for: "/a")?.mode == .icons)
        #expect(memory.view(for: "/b") == nil)
        #expect(memory.count == 2)

        let data = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(FolderViewMemory.self, from: data)
        #expect(decoded.view(for: "/a")?.mode == .icons)
    }

    @Test func groupByKindPutsFoldersFirst() {
        let items = [file("b.txt"), file("a.png", kind: "PNG image"), file("Docs", folder: true), file("c.txt")]
        let groups = Grouping.groups(items, by: .kind)
        #expect(groups.map(\.title) == ["Folders", "PNG image", "Text"])
        #expect(groups[2].items.map(\.name) == ["b.txt", "c.txt"])
    }

    @Test func groupByDate() {
        let items = [file("old", daysOld: 400), file("now", daysOld: 0.01), file("y", daysOld: 1), file("w", daysOld: 4),
            file("none", daysOld: nil)]
        let titles = Grouping.groups(items, by: .modified, now: now, calendar: calendar).map(\.title)
        #expect(titles == ["Today", "Yesterday", "Past Week", "Older", "Unknown"])
    }

    @Test func groupBySizeLikeExplorer() {
        let items = [file("big", size: 2 * 1024 * 1024 * 1024), file("empty", size: 0), file("tiny", size: 100),
            file("F", folder: true)]
        let titles = Grouping.groups(items, by: .size).map(\.title)
        #expect(titles == ["Folders", "Empty", "Tiny (under 16 KB)", "Huge (1 to 4 GB)"])
    }

    @Test func rowsHaveHeadingsOnlyWhenGrouping() {
        let items = [file("a.txt"), file("Docs", folder: true)]
        #expect(Grouping.rows(items, by: .none).count == 2)
        let rows = Grouping.rows(items, by: .kind)
        #expect(rows.count == 4)
        #expect(rows[0] == .header("Folders", count: 1))
        #expect(rows[1].item?.name == "Docs")
    }

    @Test func newColumnsSort() {
        var a = file("a.zip")
        a.permissions = 0o755
        var b = file("b.txt")
        b.permissions = 0o644
        #expect(FileSort(column: .ext).sorted([a, b]).map(\.name) == ["b.txt", "a.zip"])
        #expect(FileSort(column: .permissions).sorted([a, b]).map(\.name) == ["b.txt", "a.zip"])
        #expect(FileSort.Column.allCases.filter(\.isShownByDefault) == [.name, .modified, .kind, .size])
    }
}
