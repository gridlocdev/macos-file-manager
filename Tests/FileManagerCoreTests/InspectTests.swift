import Foundation
import Testing

@testable import FileManagerCore

@Suite struct DropRulesTests {
    func u(_ path: String) -> URL { URL(fileURLWithPath: path) }
    let sameDisk: (URL, URL) -> Bool = { _, _ in true }
    let otherDisk: (URL, URL) -> Bool = { _, _ in false }

    func op(_ sources: [String], _ folder: String, option: Bool = false, command: Bool = false,
            same: Bool = true) -> DropRules.Operation {
        DropRules.operation(dropping: sources.map(u), into: u(folder), option: option, command: command,
            sameVolume: same ? sameDisk : otherDisk)
    }

    @Test func moveOnSameDiskCopyAcrossDisks() {
        #expect(op(["/a/x"], "/b") == .move)
        #expect(op(["/a/x"], "/Volumes/USB", same: false) == .copy)
    }

    @Test func modifiersOverride() {
        #expect(op(["/a/x"], "/b", option: true) == .copy)
        #expect(op(["/a/x"], "/Volumes/USB", command: true, same: false) == .move)
    }

    @Test func nothingWhenDroppedWhereItIs() {
        #expect(op(["/a/x"], "/a") == .none)
        #expect(op(["/a/x"], "/a", command: true) == .none)
        // Opt-drag in place duplicates, like Finder.
        #expect(op(["/a/x"], "/a", option: true) == .copy)
    }

    @Test func neverIntoItself() {
        #expect(op(["/a/Docs"], "/a/Docs") == .none)
        #expect(op(["/a/Docs"], "/a/Docs/Sub", option: true) == .none)
        #expect(op(["/a/Doc"], "/a/Docs") == .move, "a prefix of the name isn't a parent")
    }
}

@Suite struct InspectTests {
    @Test func permissions() {
        #expect(Permissions.symbolic(0o755, isFolder: true) == "drwxr-xr-x")
        #expect(Permissions.symbolic(0o644, isFolder: false) == "-rw-r--r--")
        #expect(Permissions.symbolic(0o600, isFolder: false) == "-rw-------")
        #expect(Permissions.access(6) == "Read & Write")
        #expect(Permissions.access(4) == "Read only")
        #expect(Permissions.access(0) == "No access")
    }

    @Test func folderSizeCountsEverything() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolderSize-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub/.hidden"), withIntermediateDirectories: true)
        try Data(count: 100).write(to: root.appendingPathComponent("a.bin"))
        try Data(count: 50).write(to: root.appendingPathComponent("sub/b.bin"))
        try Data(count: 7).write(to: root.appendingPathComponent("sub/.hidden/c"))

        let size = FolderSize.measure(root)
        #expect(size.bytes == 157)
        #expect(size.files == 3)
        #expect(size.folders == 2)
        #expect(size.allocatedBytes >= size.bytes)
    }

    @Test func folderSizeStopsWhenCancelled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolderSize-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<5 { try Data(count: 1).write(to: root.appendingPathComponent("\(i)")) }
        #expect(FolderSize.measure(root, isCancelled: { true }).files == 0)
    }
}
