import Foundation
import Testing

@testable import FileManagerCore

@Suite struct NamePatternTests {
    @Test func plainTextMatchesAnywhereIgnoringCase() {
        let pattern = NamePattern("report")
        #expect(pattern.matches("Q3 Report.pdf"))
        #expect(!pattern.matches("notes.txt"))
    }

    @Test func wildcardsMatchTheWholeName() {
        #expect(NamePattern("*.txt").matches("notes.TXT"))
        #expect(!NamePattern("*.txt").matches("notes.txt.bak"))
        #expect(NamePattern("img_????.jpg").matches("IMG_0042.jpg"))
        #expect(!NamePattern("img_????.jpg").matches("IMG_42.jpg"))
        #expect(NamePattern("a*b*c").matches("aXXbYYc"))
        #expect(!NamePattern("a*b*c").matches("aXXbYY"))
    }

    @Test func severalPatternsSeparatedBySemicolons() {
        let pattern = NamePattern("*.jpg; *.png")
        #expect(pattern.matches("a.jpg"))
        #expect(pattern.matches("b.png"))
        #expect(!pattern.matches("c.gif"))
    }

    /// Spotlight throws on an OR with a single term, so one pattern is a plain predicate.
    @Test func spotlightPredicate() {
        #expect(NamePattern("").spotlightPredicate == nil)
        #expect(!(NamePattern("*.txt").spotlightPredicate is NSCompoundPredicate))
        let two = NamePattern("*.jpg;report").spotlightPredicate as? NSCompoundPredicate
        #expect(two?.subpredicates.count == 2)
    }

    @Test func emptyMatchesEverything() {
        #expect(NamePattern("").isEmpty)
        #expect(NamePattern(" ; ").matches("anything"))
    }
}

@Suite struct SearchCriteriaTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func file(_ name: String, size: Int64 = 10, daysOld: Double = 0, folder: Bool = false) -> FileItem {
        FileItem(
            url: URL(filePath: "/x/\(name)"), name: name, isFolder: folder, size: folder ? nil : size,
            modified: now.addingTimeInterval(-daysOld * 86_400))
    }

    @Test func kindFilter() {
        let criteria = SearchCriteria(kind: .image)
        #expect(criteria.matches(file("a.HEIC"), now: now, calendar: calendar))
        #expect(!criteria.matches(file("a.txt"), now: now, calendar: calendar))
        #expect(SearchCriteria(kind: .folder).matches(file("Photos", folder: true), now: now, calendar: calendar))
        #expect(!SearchCriteria(kind: .image).matches(file("x.png", folder: true), now: now, calendar: calendar))
    }

    @Test func dateFilter() {
        let week = SearchCriteria(date: .week)
        #expect(week.matches(file("a", daysOld: 3), now: now, calendar: calendar))
        #expect(!week.matches(file("a", daysOld: 9), now: now, calendar: calendar))
        #expect(SearchCriteria(date: .year).matches(file("a", daysOld: 300), now: now, calendar: calendar))
    }

    @Test func sizeFilterSkipsFolders() {
        #expect(SearchCriteria(size: .small).matches(file("a", size: 500), now: now, calendar: calendar))
        #expect(SearchCriteria(size: .large).matches(file("a", size: 200_000_000), now: now, calendar: calendar))
        #expect(!SearchCriteria(size: .medium).matches(file("a", size: 500), now: now, calendar: calendar))
        #expect(!SearchCriteria(size: .small).matches(file("F", folder: true), now: now, calendar: calendar))
    }

    @Test func filterCombinesNameAndFilters() {
        let items = [file("a.png"), file("b.png", daysOld: 40), file("c.txt")]
        let found = SearchCriteria(text: "*.png", date: .month).filter(items, now: now, calendar: calendar)
        #expect(found.map(\.name) == ["a.png"])
        #expect(SearchCriteria().filter(items).count == 3)
    }

    @Test func invertSelection() {
        #expect(Selection.inverted([2], in: [1, 2, 3]) == [1, 3])
        #expect(Selection.inverted([], in: [1, 2]) == [1, 2])
    }
}

@Suite struct BatchRenameTests {
    func items(_ names: [String], folder: String = "/f") -> [BatchRename.Item] {
        names.map { BatchRename.Item(url: URL(filePath: "\(folder)/\($0)"), isFolder: !$0.contains(".")) }
    }

    func newNames(_ names: [String], _ options: BatchRenameOptions, existing: Set<String> = []) -> [String] {
        BatchRename.preview(items(names), options: options) { _ in existing.union(names) }.entries.map(\.newName)
    }

    @Test func findAndReplaceLeavesExtension() {
        var options = BatchRenameOptions()
        options.find = "txt"
        options.replace = "doc"
        #expect(newNames(["txt notes.txt"], options) == ["doc notes.txt"])
        options.includeExtension = true
        #expect(newNames(["txt notes.txt"], options) == ["doc notes.doc"])
    }

    @Test func findIgnoresCaseUnlessAsked() {
        var options = BatchRenameOptions()
        options.find = "IMG"
        options.replace = "Photo"
        #expect(newNames(["img_1.jpg"], options) == ["Photo_1.jpg"])
        options.matchCase = true
        #expect(newNames(["img_1.jpg"], options) == ["img_1.jpg"])
    }

    @Test func regexWithGroups() {
        var options = BatchRenameOptions()
        options.useRegex = true
        options.find = #"(\d+)-(\d+)"#
        options.replace = "$2-$1"
        #expect(newNames(["10-20.txt"], options) == ["20-10.txt"])
        options.find = "("
        let preview = BatchRename.preview(items(["a.txt"]), options: options) { _ in [] }
        #expect(preview.patternError != nil)
        #expect(!preview.canRename)
    }

    @Test func newNameWithNumbers() {
        var options = BatchRenameOptions()
        options.newName = "Holiday"
        options.numbering = .after
        options.digits = 2
        #expect(newNames(["x.jpg", "y.jpg", "z.png"], options) == ["Holiday 01.jpg", "Holiday 02.jpg", "Holiday 03.png"])
        options.numbering = .before
        options.separator = "_"
        options.startNumber = 9
        #expect(newNames(["x.jpg", "y.jpg"], options) == ["09_Holiday.jpg", "10_Holiday.jpg"])
    }

    @Test func caseChanges() {
        var options = BatchRenameOptions()
        options.caseChange = .upper
        #expect(newNames(["notes.txt", "Folder"], options) == ["NOTES.txt", "FOLDER"])
        options.caseChange = .title
        #expect(newNames(["my notes.txt"], options) == ["My Notes.txt"])
    }

    @Test func problems() {
        var options = BatchRenameOptions()
        options.newName = "same"
        var preview = BatchRename.preview(items(["a.txt", "b.txt"]), options: options) { _ in ["a.txt", "b.txt"] }
        #expect(preview.entries.allSatisfy { $0.problem != nil })
        #expect(!preview.canRename)

        options = BatchRenameOptions()
        options.find = "a"
        options.replace = "taken"
        preview = BatchRename.preview(items(["a.txt"]), options: options) { _ in ["a.txt", "Taken.txt"] }
        #expect(preview.entries[0].problem != nil)

        options.replace = "x/y"
        preview = BatchRename.preview(items(["a.txt"]), options: options) { _ in ["a.txt"] }
        #expect(preview.entries[0].problem != nil)

        // Nothing changes: nothing to rename.
        preview = BatchRename.preview(items(["a.txt"]), options: BatchRenameOptions()) { _ in ["a.txt"] }
        #expect(!preview.canRename)
    }

    @Test func sameNamesInDifferentFoldersAreFine() {
        var options = BatchRenameOptions()
        options.newName = "cover"
        let both = items(["a.jpg"], folder: "/one") + items(["b.jpg"], folder: "/two")
        let preview = BatchRename.preview(both, options: options) { _ in [] }
        #expect(preview.canRename)
    }

    @Test func swappingNamesGoesThroughTemporaryNames() {
        var options = BatchRenameOptions()
        options.useRegex = true
        options.find = "^(a|b)$"
        // a → b and b → a.
        let preview = BatchRename.preview(items(["a.txt", "b.txt"]), options: options) { _ in ["a.txt", "b.txt"] }
        var entries = preview.entries
        entries[0].newName = "b.txt"
        entries[1].newName = "a.txt"
        var n = 0
        let moves = BatchRename.moves(entries) {
            n += 1
            return "tmp\(n)"
        }
        #expect(moves.map { "\($0.from.lastPathComponent)>\($0.to.lastPathComponent)" }
            == ["a.txt>tmp1", "b.txt>tmp2", "tmp1>b.txt", "tmp2>a.txt"])
    }

    @Test func takingANameThatIsBeingVacatedWaitsForIt() {
        let entries = [
            BatchRename.Entry(url: URL(filePath: "/f/a.txt"), newName: "b.txt"),
            BatchRename.Entry(url: URL(filePath: "/f/b.txt"), newName: "c.txt"),
            BatchRename.Entry(url: URL(filePath: "/f/same.txt"), newName: "same.txt"),
        ]
        let moves = BatchRename.moves(entries) { "tmp" }
        #expect(moves.map { "\($0.from.lastPathComponent)>\($0.to.lastPathComponent)" }
            == ["a.txt>tmp", "b.txt>c.txt", "tmp>b.txt"])
    }

    @Test func caseOnlyChangeIsADirectMove() {
        let entries = [BatchRename.Entry(url: URL(filePath: "/f/a.txt"), newName: "A.txt")]
        #expect(BatchRename.moves(entries).map(\.to.lastPathComponent) == ["A.txt"])
    }
}

@Suite struct SearchPrefilterTests {
    @Test func filesWhoseNameCantMatchAreSkippedEarly() {
        let criteria = SearchCriteria(text: "report")
        #expect(criteria.mightMatch(fileNamed: "Report 2024.pdf"))
        #expect(!criteria.mightMatch(fileNamed: "notes.txt"))
        // "*.pdf" also matches with the extension hidden ("Report" shown): the name on disk counts.
        #expect(SearchCriteria(text: "*.pdf").mightMatch(fileNamed: "Report.pdf"))
        #expect(SearchCriteria(text: "report").mightMatch(fileNamed: "report.txt"))
    }
}
