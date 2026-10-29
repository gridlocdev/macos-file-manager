import Foundation
import Testing

@testable import FileManagerCore

@Suite struct FilePathsTests {
    @Test func trailingSlashIsTheSameFolder() {
        let a = URL(filePath: "/Users/me/src/")
        let b = URL(filePath: "/Users/me/src", directoryHint: .notDirectory)
        #expect(a != b)
        #expect(a.isSameFile(as: b))
        #expect(a.normalized == b.normalized)
    }

    @Test func canonicalResolvesDots() {
        #expect(URL(filePath: "/a/b/../c/").canonical == URL(filePath: "/a/c", directoryHint: .notDirectory))
        #expect(URL(filePath: "/a/./b").canonical.path == "/a/b")
    }

    @Test func inside() {
        let src = URL(filePath: "/Users/me/src")
        #expect(URL(filePath: "/Users/me/src/app/x.swift").isInside(src))
        #expect(!URL(filePath: "/Users/me/src").isInside(src))
        #expect(!URL(filePath: "/Users/me/srcs/x").isInside(src))
        #expect(URL(filePath: "/Users").isInside(URL(filePath: "/")))
        #expect(URL(filePath: "/Users/me/src/x").isDirectlyInside(URL(filePath: "/Users/me/src/")))
        #expect(!URL(filePath: "/Users/me/src/a/x").isDirectlyInside(src))
    }

    @Test func replacingFolder() {
        let real = URL(filePath: "/private/tmp")
        let shown = URL(filePath: "/tmp")
        #expect(URL(filePath: "/private/tmp/a/b.txt").replacingFolder(real, with: shown).path == "/tmp/a/b.txt")
        #expect(URL(filePath: "/private/tmp").replacingFolder(real, with: shown).path == "/tmp")
        #expect(URL(filePath: "/Users/me/x").replacingFolder(real, with: shown).path == "/Users/me/x")
        #expect(URL(filePath: "/private/tmpfile").replacingFolder(real, with: shown).path == "/private/tmpfile")
    }

    @Test func root() {
        #expect(URL(filePath: "/").isFileSystemRoot)
        #expect(!URL(filePath: "/Users").isFileSystemRoot)
    }

    @Test func trash() {
        let home = URL(filePath: "/Users/me")
        #expect(URL(filePath: "/Users/me/.Trash/").isTrashFolder(home: home))
        #expect(URL(filePath: "/Volumes/Disk/.Trashes/501").isTrashFolder(home: home))
        #expect(!URL(filePath: "/Users/me/Trash").isTrashFolder(home: home))
    }
}
