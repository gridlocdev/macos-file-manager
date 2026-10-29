import Foundation
import Testing

@testable import FileManagerCore

@Suite struct FileNamingTests {
    @Test func keepBoth() {
        #expect(FileNaming.keepBoth("notes.txt", existing: ["notes.txt"]) == "notes (2).txt")
        #expect(FileNaming.keepBoth("notes.txt", existing: ["notes.txt", "Notes (2).txt"]) == "notes (3).txt")
        #expect(FileNaming.keepBoth("notes (2).txt", existing: ["notes (2).txt"]) == "notes (3).txt")
        #expect(FileNaming.keepBoth("Projects", isFolder: true, existing: ["Projects"]) == "Projects (2)")
        #expect(FileNaming.keepBoth("v1.2", isFolder: true, existing: ["v1.2"]) == "v1.2 (2)")
        #expect(FileNaming.keepBoth(".config", existing: [".config"]) == ".config (2)")
        #expect(FileNaming.keepBoth("free.txt", existing: ["other.txt"]) == "free.txt")
    }

    @Test func duplicate() {
        #expect(FileNaming.duplicate("notes.txt", existing: ["notes.txt"]) == "notes - Copy.txt")
        #expect(
            FileNaming.duplicate("notes.txt", existing: ["notes.txt", "notes - Copy.txt"]) == "notes - Copy (2).txt")
        #expect(FileNaming.duplicate("Projects", isFolder: true, existing: []) == "Projects - Copy")
    }

    @Test func problems() {
        #expect(FileNaming.problem(with: "ok.txt") == nil)
        #expect(FileNaming.problem(with: "  ") != nil)
        #expect(FileNaming.problem(with: "a/b") != nil)
        #expect(FileNaming.problem(with: "a:b") != nil)
        #expect(FileNaming.problem(with: "..") != nil)
    }

    @Test func renameSelectsBaseName() {
        #expect(FileNaming.baseLength(of: "notes.txt", isFolder: false) == 5)
        #expect(FileNaming.baseLength(of: "archive.tar.gz", isFolder: false) == 11)
        #expect(FileNaming.baseLength(of: "v1.2", isFolder: true) == 4)
        #expect(FileNaming.baseLength(of: ".zshrc", isFolder: false) == 6)
    }
}

/// An in-memory tree: paths ending in "/" are folders, others files with a size.
struct FakeTree: FileTree {
    var entries: [String: FileTreeEntry]

    init(_ paths: [String: Int64]) {
        var entries: [String: FileTreeEntry] = [:]
        for (path, size) in paths {
            let isFolder = path.hasSuffix("/")
            let clean = isFolder ? String(path.dropLast()) : path
            entries[clean] = FileTreeEntry(isFolder: isFolder, size: size)
            // Parent folders exist too.
            var parent = (clean as NSString).deletingLastPathComponent
            while parent != "/" && !parent.isEmpty {
                entries[parent] = entries[parent] ?? FileTreeEntry(isFolder: true)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        self.entries = entries
    }

    func entry(at url: URL) -> FileTreeEntry? { entries[url.path] }

    func children(of folder: URL) -> [URL] {
        entries.keys.filter { ($0 as NSString).deletingLastPathComponent == folder.path }.sorted()
            .map { URL(fileURLWithPath: $0) }
    }
}

@Suite struct TransferPlannerTests {
    func u(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test func copiesIntoEmptySpot() throws {
        let tree = FakeTree(["/a/notes.txt": 10, "/b/": 0])
        let plan = try TransferPlanner(tree: tree).plan([u("/a/notes.txt")], into: u("/b"), mode: .copy) { _ in .skip }
        #expect(plan.steps == [.copy(u("/a/notes.txt"), to: u("/b/notes.txt"))])
        #expect(plan.units == 10)
        #expect(plan.results == [u("/b/notes.txt")])
    }

    @Test func reportsFileConflictsAndMergesFolders() throws {
        let tree = FakeTree([
            "/a/Docs/one.txt": 1, "/a/Docs/two.txt": 2, "/a/Docs/Sub/three.txt": 3,
            "/b/Docs/two.txt": 9, "/b/Docs/Sub/": 0,
        ])
        let planner = TransferPlanner(tree: tree)
        let conflicts = try planner.conflicts([u("/a/Docs")], into: u("/b"), mode: .copy)
        #expect(conflicts.map(\.destination) == [u("/b/Docs/two.txt")])

        let plan = try planner.plan([u("/a/Docs")], into: u("/b"), mode: .copy) { _ in .replace }
        #expect(
            plan.steps == [
                .copy(u("/a/Docs/Sub/three.txt"), to: u("/b/Docs/Sub/three.txt")),
                .copy(u("/a/Docs/one.txt"), to: u("/b/Docs/one.txt")),
                .trash(u("/b/Docs/two.txt")),
                .copy(u("/a/Docs/two.txt"), to: u("/b/Docs/two.txt")),
            ])
        #expect(plan.results == [u("/b/Docs")])
    }

    @Test func keepBothAndSkip() throws {
        let tree = FakeTree(["/a/x.txt": 1, "/a/y.txt": 1, "/b/x.txt": 1, "/b/y.txt": 1])
        let plan = try TransferPlanner(tree: tree).plan([u("/a/x.txt"), u("/a/y.txt")], into: u("/b"), mode: .move) {
            $0.source.lastPathComponent == "x.txt" ? .keepBoth : .skip
        }
        #expect(plan.steps == [.move(u("/a/x.txt"), to: u("/b/x (2).txt"))])
        #expect(plan.results == [u("/b/x (2).txt")])
    }

    @Test func movingAMergedFolderRemovesTheEmptySource() throws {
        let tree = FakeTree(["/a/Docs/one.txt": 1, "/b/Docs/": 0])
        let plan = try TransferPlanner(tree: tree).plan([u("/a/Docs")], into: u("/b"), mode: .move) { _ in .skip }
        #expect(
            plan.steps == [
                .move(u("/a/Docs/one.txt"), to: u("/b/Docs/one.txt")),
                .removeEmptyFolder(u("/a/Docs")),
            ])
    }

    @Test func fileOverFolderIsAConflict() throws {
        let tree = FakeTree(["/a/Docs": 1, "/b/Docs/": 0])
        let conflicts = try TransferPlanner(tree: tree).conflicts([u("/a/Docs")], into: u("/b"), mode: .copy)
        #expect(conflicts.first?.destinationIsFolder == true)
        #expect(conflicts.first?.sourceIsFolder == false)
    }

    @Test func copyIntoSameFolderDuplicates() throws {
        let tree = FakeTree(["/a/notes.txt": 1])
        let plan = try TransferPlanner(tree: tree).plan([u("/a/notes.txt")], into: u("/a"), mode: .copy) { _ in .skip }
        #expect(plan.steps == [.copy(u("/a/notes.txt"), to: u("/a/notes - Copy.txt"))])
    }

    @Test func moveIntoSameFolderDoesNothing() throws {
        let tree = FakeTree(["/a/notes.txt": 1])
        let plan = try TransferPlanner(tree: tree).plan([u("/a/notes.txt")], into: u("/a"), mode: .move) { _ in .skip }
        #expect(plan.steps.isEmpty)
    }

    @Test func refusesToGoIntoItself() {
        let tree = FakeTree(["/a/Docs/Sub/": 0])
        #expect(throws: TransferError.intoItself("Docs")) {
            try TransferPlanner(tree: tree).plan([u("/a/Docs")], into: u("/a/Docs/Sub"), mode: .move) { _ in .skip }
        }
    }

    @Test func sameNameFromTwoFoldersKeepsBoth() throws {
        let tree = FakeTree(["/a/x.txt": 1, "/c/x.txt": 1, "/b/": 0])
        let plan = try TransferPlanner(tree: tree).plan([u("/a/x.txt"), u("/c/x.txt")], into: u("/b"), mode: .copy) {
            _ in .skip
        }
        #expect(plan.results == [u("/b/x.txt"), u("/b/x (2).txt")])
    }
}

@Suite struct FileUndoTests {
    func u(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test func inverseReversesInOrder() {
        let executed: [ExecutedStep] = [
            .trashed(u("/b/x"), trashURL: u("/T/x")),
            .copied(u("/a/x"), to: u("/b/x")),
            .moved(u("/a/y"), to: u("/b/y")),
            .createdFolder(u("/b/New Folder")),
            .removedFolder(u("/a/Docs")),
        ]
        #expect(
            FileUndo.inverse(of: executed) == [
                .createFolder(u("/a/Docs")),
                .trash(u("/b/New Folder")),
                .move(u("/b/y"), to: u("/a/y")),
                .trash(u("/b/x")),
                .move(u("/T/x"), to: u("/b/x")),
            ])
    }

    @Test func permanentDeleteCantBeUndone() {
        #expect(FileUndo.inverse(of: [.deleted(u("/a"))]) == nil)
    }
}

/// Runs against a temporary folder, with a fake Trash inside it.
@Suite struct FileStepExecutorTests {
    let root: URL
    let executor: FileStepExecutor

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileManagerTests-\(UUID().uuidString)")
        let trash = root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        executor = FileStepExecutor { url in
            let target = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }

    func file(_ name: String, _ text: String = "x") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func copyThenUndoThenRedo() throws {
        let source = try file("a/notes.txt", "hello")
        let target = root.appendingPathComponent("b/notes.txt")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let done = executor.run([.copy(source, to: target)])
        #expect(done.error == nil)
        #expect(try String(contentsOf: target, encoding: .utf8) == "hello")

        let undo = try #require(FileUndo.inverse(of: done.executed))
        let undone = executor.run(undo)
        #expect(!exists(target))
        #expect(exists(source))

        let redo = try #require(FileUndo.inverse(of: undone.executed))
        _ = executor.run(redo)
        #expect(exists(target))
    }

    @Test func renameCaseOnly() throws {
        let source = try file("notes.txt")
        let target = root.appendingPathComponent("Notes.txt")
        let done = executor.run([.move(source, to: target)])
        #expect(done.error == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.contains("Notes.txt"))
        #expect(!names.contains("notes.txt"))
    }

    @Test func stopsAtFirstErrorAndKeepsWhatRan() throws {
        let a = try file("a.txt")
        let missing = root.appendingPathComponent("missing.txt")
        let done = executor.run([
            .move(a, to: root.appendingPathComponent("a2.txt")),
            .move(missing, to: root.appendingPathComponent("m2.txt")),
            .createFolder(root.appendingPathComponent("never")),
        ])
        #expect(done.error != nil)
        #expect(done.executed.count == 1)
        #expect(!exists(root.appendingPathComponent("never")))
    }

    @Test func createFileRefusesToOverwrite() throws {
        let existing = try file("x.txt", "keep me")
        let done = executor.run([.createFile(existing)])
        #expect(done.error != nil)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep me")
    }

    @Test func cancelStopsBeforeNextStep() throws {
        var calls = 0
        let done = executor.run(
            [.createFolder(root.appendingPathComponent("one")), .createFolder(root.appendingPathComponent("two"))],
            isCancelled: {
                calls += 1
                return calls > 1
            })
        #expect(done.cancelled)
        #expect(done.executed.count == 1)
    }

    @Test func movePutsBackIntoMissingFolder() throws {
        let item = try file("t/x.txt")
        let original = root.appendingPathComponent("gone/deeper/x.txt")
        let done = executor.run([.move(item, to: original)])
        #expect(done.error == nil)
        #expect(exists(original))
    }

    @Test func plansAndRunsAMergeOnDisk() throws {
        _ = try file("a/Docs/one.txt")
        _ = try file("a/Docs/two.txt", "new")
        let old = try file("b/Docs/two.txt", "old")
        let plan = try TransferPlanner(tree: DiskFileTree()).plan(
            [root.appendingPathComponent("a/Docs")], into: root.appendingPathComponent("b"), mode: .move
        ) { _ in .replace }
        let done = executor.run(plan.steps)
        #expect(done.error == nil)
        #expect(try String(contentsOf: old, encoding: .utf8) == "new")
        #expect(exists(root.appendingPathComponent("b/Docs/one.txt")))
        #expect(!exists(root.appendingPathComponent("a/Docs")))

        // Undo puts everything back, including the replaced file from the Trash.
        _ = executor.run(try #require(FileUndo.inverse(of: done.executed)))
        #expect(try String(contentsOf: old, encoding: .utf8) == "old")
        #expect(exists(root.appendingPathComponent("a/Docs/two.txt")))
        #expect(exists(root.appendingPathComponent("a/Docs/one.txt")))
    }
}
