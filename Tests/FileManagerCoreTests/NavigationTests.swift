import Foundation
import Testing

@testable import FileManagerCore

@Suite struct NavigationHistoryTests {
    let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b"), c = URL(fileURLWithPath: "/c")

    @Test func backAndForward() {
        var h = NavigationHistory(start: a)
        h.visit(b)
        h.visit(c)
        #expect(h.goBack() == b)
        #expect(h.goBack() == a)
        #expect(h.goBack() == nil)
        #expect(h.goForward() == b)
        #expect(h.current == b)
    }

    @Test func visitingClearsForward() {
        var h = NavigationHistory(start: a)
        h.visit(b)
        _ = h.goBack()
        h.visit(c)
        #expect(!h.canGoForward)
        #expect(h.back == [a])
    }

    @Test func revisitingCurrentIsIgnored() {
        var h = NavigationHistory(start: a)
        h.visit(a)
        #expect(!h.canGoBack)
    }
}

@Suite struct PathInputTests {
    let home = URL(fileURLWithPath: "/Users/me")
    let current = URL(fileURLWithPath: "/Users/me/src")

    func resolve(_ s: String) -> String? {
        PathInput.resolve(s, relativeTo: current, home: home)?.path
    }

    @Test func resolvesForms() {
        #expect(resolve("/tmp") == "/tmp")
        #expect(resolve("~") == "/Users/me")
        #expect(resolve("~/Downloads/") == "/Users/me/Downloads")
        #expect(resolve("apps") == "/Users/me/src/apps")
        #expect(resolve("..") == "/Users/me")
        #expect(resolve("  /tmp  ") == "/tmp")
        #expect(resolve("file:///Users/me/Desktop") == "/Users/me/Desktop")
        #expect(resolve("") == nil)
    }

    @Test func displayAbbreviatesHome() {
        #expect(PathInput.display(home, home: home) == "~")
        #expect(PathInput.display(current, home: home) == "~/src")
        #expect(PathInput.display(URL(fileURLWithPath: "/Users/meow"), home: home) == "/Users/meow")
    }

    func complete(_ s: String) -> String? {
        PathInput.complete(s, relativeTo: current, home: home) { url in
            switch url.path {
            case "/Users/me": ["Desktop", "Documents", "Downloads", ".config"]
            case "/Users/me/src": ["apps", "games"]
            default: []
            }
        }
    }

    @Test func completesSingleMatchWithSlash() {
        #expect(complete("~/Des") == "~/Desktop/")
        #expect(complete("ga") == "games/")
        #expect(complete("~/.c") == "~/.config/")
    }

    @Test func completesToCommonPrefix() {
        #expect(complete("~/do") == "~/Do")
        #expect(complete("~/Doc") == "~/Documents/")
    }

    @Test func skipsHiddenAndReportsNoMatch() {
        #expect(complete("~/") == "~/D")
        #expect(complete("~/zzz") == nil)
    }
}

@Suite struct FileSortTests {
    func item(_ name: String, folder: Bool = false, size: Int64? = nil, kind: String = "") -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/x/\(name)"), name: name, isFolder: folder, size: size, kind: kind)
    }

    @Test func foldersFirstAndNaturalNames() {
        let items = [item("file10"), item("file2"), item("Zeta", folder: true), item("alpha")]
        let names = FileSort().sorted(items).map(\.name)
        #expect(names == ["Zeta", "alpha", "file2", "file10"])
    }

    @Test func mixedWhenFoldersFirstIsOff() {
        let items = [item("b"), item("a", folder: true)]
        #expect(FileSort(foldersFirst: false).sorted(items).map(\.name) == ["a", "b"])
    }

    @Test func sizeDescendingKeepsFoldersFirst() {
        let items = [item("small", size: 1), item("big", size: 9), item("dir", folder: true)]
        let sort = FileSort(column: .size, ascending: false)
        #expect(sort.sorted(items).map(\.name) == ["dir", "big", "small"])
    }

    @Test func tiesBreakByName() {
        let items = [item("b", kind: "Text"), item("a", kind: "Text")]
        #expect(FileSort(column: .kind).sorted(items).map(\.name) == ["a", "b"])
    }
}
